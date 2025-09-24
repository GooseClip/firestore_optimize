import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'optimizer/batch_optimizer_mixin.dart';
import 'operations.dart';
import 'optimizer/join_operations_mixin.dart';

class OperationsManager with BatchOptimizerMixin, JoinOperationsMixin {
  OperationsManager(this.instance);

  final FirebaseFirestore instance;
  final Lock _lock = Lock();
  Timer? _batchTimer;
  int totalOperations = 0;

  // Helper method to create Duration from milliseconds
  Duration millis(int milliseconds) => Duration(milliseconds: milliseconds);

  @override
  List<BatchOperation> operations = [];

  Future<void> busy() async {
    await _lock.synchronized(() {});
  }

  Future<void> set({
    required DocumentPath path,
    required Map<String, dynamic> data,
    required bool merge,
  }) async {
    final op = SetOperation(path: path, data: data, merge: merge);
    await instance.doc(path).set(op.finalize, SetOptions(merge: merge));
  }

  Future<int> batchSet({
    required DocumentPath path,
    required Map<String, dynamic> data,
    required bool merge,
  }) async {
    return await $pushBatchOperation(SetOperation(path: path, data: data, merge: merge));
  }

  Future<void> update({
    required DocumentPath path,
    required Map<String, dynamic> data,
  }) async {
    final op = UpdateOperation(path: path, data: data);
    await instance.doc(path).update(op.finalize);
  }

  Future<int> batchUpdate({
    required DocumentPath path,
    required Map<String, dynamic> data,
  }) async {
    return await $pushBatchOperation(UpdateOperation(path: path, data: data));
  }

  Future<void> delete({
    required DocumentPath path,
  }) async {
    await instance.doc(path).delete();
  }

  Future<int> batchDelete({
    required DocumentPath path,
  }) async {
    return await $pushBatchOperation(DeleteOperation(path: path));
  }

  @visibleForTesting
  Future<int> $pushBatchOperation(BatchOperation operation) async {
    return await _lock.synchronized<int>(() async {
      _batchTimer?.cancel();
      _batchTimer = Timer(millis(1000), _commitBatch);
      return optimizeOperations(operation);
    });
  }

  Future<void> rush() async {
    _batchTimer?.cancel();
    await _commitBatch();
  }

  Future<void> _commitBatch() async {
    // Take a snapshot of the operations and clear the operations.
    final batchOperations = await _lock.synchronized<List<BatchOperation>>(() async {
      final ops = [...operations];
      operations.clear();
      return ops;
    });

    final batch = instance.batch();
    // Try commit all operations in a single batch
    try {
      for (var operation in batchOperations) {
        switch (operation) {
          case SetOperation():
            batch.set(instance.doc(operation.path), operation.finalize, SetOptions(merge: operation.merge));
          case UpdateOperation():
            batch.update(instance.doc(operation.path), operation.finalize);
          case DeleteOperation():
            batch.delete(instance.doc(operation.path));
        }
      }

      totalOperations += batchOperations.length;

      await batch.commit();
      return;
    } catch (e) {
      debugPrint("Error committing batch: $e");
    }

    // Failing over to individual commits

    // Map operations by type
    final setOperations = batchOperations.whereType<SetOperation>();
    final updateOperations = batchOperations.whereType<UpdateOperation>();
    final deleteOperations = batchOperations.whereType<DeleteOperation>();

    for (var op in setOperations) {
      try {
        await instance.doc(op.path).set(op.data!, SetOptions(merge: op.merge));
      } catch (e) {
          debugPrint("Set operation failed during failover: $e");
      }
    }

    for (var op in updateOperations) {
      try {
        await instance.doc(op.path).update(op.data!);
      } catch (e) {
        debugPrint("Update operation failed during failover: $e");
      }
    }

    for (var op in deleteOperations) {
      try {
        await instance.doc(op.path).delete();
      } catch (e) {
        debugPrint("Delete operation failed during failover: $e");
      }
    }

    //--------------------------------- BATCH DONE [FAIL OVER] ---------------------------------
    // debugPrint("Applied operations: ${batchOperations.map((e) => e.path.split("/").last).join(", ")}");
  }

  Future<bool> hasPendingOperations(DocumentPath path) async {
    return await _lock.synchronized(() async {
      return operations.any((operation) => operation.path == path);
    });
  }

  bool willMergeDelete(DocumentPath path) {
    final hits = operations.where((operation) => operation.path == path);
    if (hits.isEmpty) {
      return false;
    }

    return hits.last is DeleteOperation;
  }

  Map<String, dynamic>? mergePendingOperations(DocumentPath path, Map<String, dynamic>? data) {
    if (data == null) {
      debugPrint("Merge] Incoming data is null, path: $path, operations: ${operations.length}");
      return data;
    }

    final hits = operations.where((operation) => operation.path == path);
    if (hits.isEmpty) {
      return data;
    }

    final m = Merge(path, data);
    try {
      return m.apply(hits);
    } catch (e) {
      debugPrint("Merge] Failed with error: $e");
      return data;
    }
  }
}

class Merge with BatchOptimizerMixin, JoinOperationsMixin {
  Merge(DocumentPath path, Map<String, dynamic> incoming) {
    operations = [SetOperation(path: path, data: incoming, merge: false)];
  }

  @override
  late List<BatchOperation> operations;

  // Apply all pending batch operations on top of the known server state.
  // Returns null in the case of the last pending operation being a delete.
  Map<String, dynamic>? apply(Iterable<BatchOperation> pendingOperations) {
    for (var op in pendingOperations) {
      optimizeOperations(op);
    }

    if (operations.length != 1) {
      throw Exception("Unexpected merge result");
    }

    final op = operations.first;
    if (op is DataOperation) {
      return op.finalize;
    }

    return null;
  }
}
