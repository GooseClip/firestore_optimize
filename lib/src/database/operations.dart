import 'jit_field_value.dart';
import 'dot_util.dart';

extension type FirestorePathRoot(String s) implements CollectionPath {
  CollectionPath collection(String path) => CollectionPath("$this/$path");

  DocumentPath document(String path) => DocumentPath("$this/$path");
}
extension type FirestorePath(String s) implements String {}
extension type CollectionPath(String s) implements FirestorePath {
  DocumentPath document(String path) => DocumentPath("$this/$path");
}
extension type DocumentPath(String s) implements FirestorePath {}

abstract class BatchOperation {
  BatchOperation({required this.path});

  final DocumentPath path;
}

abstract class DataOperation extends BatchOperation {
  DataOperation({required super.path, required this.data, required this.merge});

  Map<String, dynamic> get finalize;

  Map<String, dynamic> data;

  bool merge;

  bool get overwrite => !merge;
}

/* 
 * SetOperation
 * merge false: This will overwrite
 * merge true: This is equivalent to Update while using dot notation. (todo validate)
 */
class SetOperation extends DataOperation {
  SetOperation({required super.path, required super.data, required super.merge});

  @override
  String toString() {
    return "[SetOperation][$path]";
  }

  @override
  Map<String, dynamic> get finalize {
    // Set will write the dot values to field values so we need to convert
    final r = replaceAllJitFieldValues(data, dropDeletes: overwrite);
    final m = fromDotMap(DotMap(r));
    return m;
  }
}

/* 
 * UpdateOperation
 * When using dot notation, individual fields will be set in maps.
 * When not using dot notation, maps will overwrite.
 */
class UpdateOperation extends DataOperation {
  UpdateOperation({required super.path, required super.data}) : super(merge: isDot(data));

  @override
  String toString() {
    return "[UpdateOperation][$path]";
  }

  @override
  Map<String, dynamic> get finalize {
    final m = replaceAllJitFieldValues(data);
    return m;
  }
}

class DeleteOperation extends BatchOperation {
  DeleteOperation({required super.path});

  @override
  String toString() {
    return "[DeleteOperation][$path]";
  }
}
