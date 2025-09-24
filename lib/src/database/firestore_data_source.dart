import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'dot_util.dart';
import 'operations.dart';
import 'operations_manager.dart';
import 'rate_limit_manager.dart';

class CollectionChanges<T> {
  CollectionChanges({this.added = const [], this.modified = const [], this.removed = const []});

  final List<T> added;
  final List<T> modified;
  final List<T> removed;

  bool get isEmpty => added.isEmpty && modified.isEmpty && removed.isEmpty;

  @override
  String toString() {
    return "CollectionChanges{added: ${added.length}, modified: ${modified.length}, removed: ${removed.length}}\n"
        "Added:\n${added.map((e) => e.toString()).join("\n")}\n"
        "Modified:\n${modified.map((e) => e.toString()).join("\n")}\n"
        "Removed:\n${removed.map((e) => e.toString()).join("\n")}";
  }
}

String documentIdFromCurrentDate() {
  final iso = DateTime.now().toIso8601String();
  return iso.replaceAll(":", "-").replaceAll(".", "-");
}

typedef QueryBuilder = Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> query);

class FirestoreDataSource {
  FirestoreDataSource(this.instance, this.rateLimiter, this.batcher);

  factory FirestoreDataSource.defaultInstance() {
    final instance = FirebaseFirestore.instance;
    final batcher = OperationsManager(instance);
    final rateLimiter = RateLimitManager();
    return FirestoreDataSource(instance, rateLimiter, batcher);
  }

  final FirebaseFirestore instance;
  final RateLimitManager rateLimiter;
  final OperationsManager batcher;

  Future<DocumentReference> add({
    required CollectionPath path,
    required Map<String, dynamic> data,
    bool rateLimit = true,
  }) async {
    if (_containsFieldValue(data)) {
      throw Exception("[${path.split("/").last}] Use JitFieldValue instead of FieldValue");
    }

    if (rateLimit) {
      await rateLimiter.checkRateLimit(path, "insert", batched: false);
    }
    return instance.collection(path).add(data);
  }

  Future<void> set({
    required DocumentPath path,
    required Map<String, dynamic> data,
    bool batch = false,
    bool merge = false,
    bool rateLimit = true,
  }) async {
    if (_containsFieldValue(data)) {
      throw Exception("[${path.split("/").last}] Use JitFieldValue instead of FieldValue");
    }

    if (isDot(data)) {
      // Set will explicitly write the dot paths, e.g. a.b: 123 instead of forming a map - not expected
      throw Exception("[${path.split("/").last}] Dot notation with set is not supported");
    }

    // If we have a pending operation for this path, we don't need to rate limit as it only counts as 1
    final hasPending = batch && await batcher.hasPendingOperations(path);
    final canRateLimit = rateLimit && !hasPending && RateLimitManager.enabled;
    if (canRateLimit) {
      await batcher.busy();
      await rateLimiter.checkRateLimit(path, "set", batched: batch);
    }

    if (batch) {
      final optimized = await batcher.batchSet(path: path, data: data, merge: merge);

      // Release all matching paths currently waiting since we already have a pending batch
      if (canRateLimit) rateLimiter.release(path, optimized);
      return;
    }

    await batcher.set(path: path, data: data, merge: merge);
  }

  Future<void> update({
    required DocumentPath path,
    required Map<String, dynamic> data,
    bool batch = false,
    bool rateLimit = true,
  }) async {
    if (_containsFieldValue(data)) {
      throw Exception("[${path.split("/").last}] Use JitFieldValue instead of FieldValue");
    }

    // If we have a pending operation for this path, we don't need to rate limit as it only counts as 1
    final hasPending = batch && await batcher.hasPendingOperations(path);
    final canRateLimit = rateLimit && !hasPending && RateLimitManager.enabled;
    if (canRateLimit) {
      await batcher.busy();
      await rateLimiter.checkRateLimit(path, "update", batched: batch);
    }

    if (batch) {
      final optimized = await batcher.batchUpdate(path: path, data: data);

      // Release all matching paths currently waiting since we already have a pending batch
      if (canRateLimit) rateLimiter.release(path, optimized);

      return;
    }

    await batcher.update(path: path, data: data);
  }

  Future<void> delete({required DocumentPath path, bool batch = false, bool rateLimit = true}) async {
    // If we have a pending operation for this path, we don't need to rate limit as it only counts as 1
    final hasPending = batch && await batcher.hasPendingOperations(path);
    final canRateLimit = rateLimit && !hasPending && RateLimitManager.enabled;
    if (canRateLimit) {
      await batcher.busy();
      await rateLimiter.checkRateLimit(path, "delete", batched: batch);
    }

    if (batch) {
      final optimized = await batcher.batchDelete(path: path);

      // Release all matching paths currently waiting since we already have a pending batch
      if (canRateLimit) rateLimiter.release(path, optimized);
      return;
    }

    await batcher.delete(path: path);
  }

  Future<void> transaction({
    required Iterable<Future<dynamic> Function(Transaction)> operations,
    Duration timeout = const Duration(seconds: 3),
    int maxAttempts = 5,
  }) async {
    await instance.runTransaction(
      (transaction) async {
        for (var operation in operations) {
          await operation(transaction);
        }
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }

  // watch collections and documents as streams
  Stream<List<T>> watchCollection<T>({
    required CollectionPath path,
    required T? Function(Map<String, dynamic>? data, String documentID) builder,
    QueryBuilder? queryBuilder,
    int Function(T lhs, T rhs)? sort,
    ListenSource source = ListenSource.defaultSource,
  }) {
    Query<Map<String, dynamic>> query = instance.collection(path);
    if (queryBuilder != null) {
      query = queryBuilder(query);
    }
    final snapshots = query.snapshots(source: source);
    return snapshots.map((snapshot) {
      final result = snapshot.docs
          .map((snapshot) {
            if (batcher.willMergeDelete(path.document(snapshot.id))) {
              // Merge yielding delete
              return null;
            }
            final data = batcher.mergePendingOperations(path.document(snapshot.id), snapshot.data());
            return builder(data, snapshot.id);
          })
          .whereType<T>()
          .toList();
      if (sort != null) {
        result.sort(sort);
      }
      return result;
    });
  }

  Stream<CollectionChanges<T>> watchCollectionChanges<T>({
    required CollectionPath path,
    required T? Function(Map<String, dynamic>? data, String documentID) builder,
    QueryBuilder? queryBuilder,
    int Function(T lhs, T rhs)? sort,
    ListenSource source = ListenSource.defaultSource,
  }) {
    Query<Map<String, dynamic>> query = instance.collection(path);
    if (queryBuilder != null) {
      query = queryBuilder(query);
    }

    final snapshots = query.snapshots(source: source);
    return snapshots.map((event) {
      final added = <T?>[];
      final modified = <T?>[];
      final removed = <T?>[];
      for (var change in event.docChanges) {
        switch (change.type) {
          case DocumentChangeType.added:
            added.add(builder(change.doc.data(), change.doc.id));
            break;
          case DocumentChangeType.modified:
            if (batcher.willMergeDelete(path.document(change.doc.id))) {
              removed.add(builder(change.doc.data(), change.doc.id));
              break;
            }
            final data = batcher.mergePendingOperations(path.document(change.doc.id), change.doc.data());
            modified.add(builder(data, change.doc.id));
            break;
          case DocumentChangeType.removed:
            removed.add(builder(change.doc.data(), change.doc.id));
            break;
        }
      }

      return CollectionChanges<T>(
        added: added.whereType<T>().toList(),
        modified: modified.whereType<T>().toList(),
        removed: removed.whereType<T>().toList(),
      );
    });
  }

  Stream<T?> watchDocument<T>({
    required DocumentPath path,
    required T? Function(Map<String, dynamic>? data, String documentID) builder,
    ListenSource source = ListenSource.defaultSource,
  }) {
    final reference = instance.doc(path);
    final Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots = reference.snapshots(source: source);
    return snapshots.map((snapshot) {
      if (batcher.willMergeDelete(path)) {
        return null;
      }
      final data = batcher.mergePendingOperations(path, snapshot.data());
      return builder(data, snapshot.id);
    });
  }

  // fetch collections and documents as futures
  Future<List<T>> fetchCollection<T>({
    required CollectionPath path,
    required T? Function(Map<String, dynamic>? data, String documentID) builder,
    QueryBuilder? queryBuilder,
    int Function(T lhs, T rhs)? sort,
    Source source = Source.serverAndCache,
  }) async {
    Query<Map<String, dynamic>> query = instance.collection(path);
    if (queryBuilder != null) {
      query = queryBuilder(query);
    }

    final snapshot = await query.get(GetOptions(source: source));
    final result = snapshot.docs
        .map((snapshot) {
          if (batcher.willMergeDelete(path.document(snapshot.id))) {
            // Merge yielding delete
            return null;
          }
          final data = batcher.mergePendingOperations(path.document(snapshot.id), snapshot.data());
          return builder(data, snapshot.id);
        })
        .whereType<T>() // Filter out nulls
        .toList();
    if (sort != null) {
      result.sort(sort);
    }
    return result;
  }

  Future<T?> fetchDocument<T>({
    required DocumentPath path,
    required T? Function(Map<String, dynamic>? data, String documentID) builder,
    Source source = Source.serverAndCache,
  }) async {
    final reference = instance.doc(path);
    final snapshot = await reference.get(GetOptions(source: source));

    if (batcher.willMergeDelete(path)) {
      // Merge yielding delete
      return null;
    }
    final data = batcher.mergePendingOperations(path, snapshot.data());
    return builder(data, snapshot.id);
  }

  Future<bool> documentExists({required DocumentPath path}) async {
    final reference = instance.doc(path);
    final snapshot = await reference.get();
    return snapshot.exists;
  }

  Future<int> countCollection(CollectionPath path) async {
    final snapshot = await instance.collection(path).count().get();
    return snapshot.count ?? 0;
  }
}

bool _containsFieldValue(dynamic data) {
  if (data is FieldValue) {
    return true;
  }
  if (data is Map<String, dynamic>) {
    for (var value in data.values) {
      if (_containsFieldValue(value)) {
        return true;
      }
    }
  }
  if (data is List) {
    for (var item in data) {
      if (_containsFieldValue(item)) {
        return true;
      }
    }
  }
  return false;
}
