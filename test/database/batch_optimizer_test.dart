import 'package:flutter_test/flutter_test.dart';
import 'package:firestore_optimize/src/database/operations.dart';
import 'package:firestore_optimize/src/database/optimizer/batch_optimizer_mixin.dart';
import 'package:firestore_optimize/src/database/dot_util.dart';
import 'package:firestore_optimize/src/database/optimizer/join_operations_mixin.dart';

class MockBatchManager with BatchOptimizerMixin, JoinOperationsMixin {
  MockBatchManager(this._operations);

  List<BatchOperation> _operations;

  @override
  List<BatchOperation> get operations => _operations;

  @override
  set operations(List<BatchOperation> value) {
    _operations = value;
  }
}

// NOTE: due to complexity - joins have been moved to their own test file
void main() {
  group('all', () {
    group('remove previous operations', () {
      test('removing a set operation', () {
        final optimizer = MockBatchManager([
          SetOperation(path: DocumentPath("a/b"), data: DotMap({}), merge: true),
        ]);

        final o = optimizer.$removePreviousOperations(DeleteOperation(path: DocumentPath("a/b")));
        expect(optimizer.operations, []);
        expect(o, 1);
      });

      test('removing an update operation', () {
        final optimizer = MockBatchManager([
          UpdateOperation(path: DocumentPath("a/b"), data: DotMap({})),
        ]);

        final o = optimizer.$removePreviousOperations(DeleteOperation(path: DocumentPath("a/b")));
        expect(optimizer.operations.length, 0);
        expect(o, 1);
      });

      test('removing an delete operation', () {
        final optimizer = MockBatchManager([
          DeleteOperation(path: DocumentPath("a/b")),
        ]);

        final o = optimizer.$removePreviousOperations(DeleteOperation(path: DocumentPath("a/b")));
        expect(optimizer.operations.length, 0);
        expect(o, 1);
      });

      test('removing a many operation', () {
        final optimizer = MockBatchManager([
          SetOperation(path: DocumentPath("a/b"), data: DotMap({}), merge: true),
          UpdateOperation(path: DocumentPath("a/b"), data: DotMap({})),
          DeleteOperation(path: DocumentPath("a/b")),
        ]);

        final o = optimizer.$removePreviousOperations(DeleteOperation(path: DocumentPath("a/b")));
        expect(optimizer.operations.length, 0);
        expect(o, 3);
      });

      test('preserve non-matching operation', () {
        final optimizer = MockBatchManager([
          SetOperation(path: DocumentPath("a/b"), data: DotMap({}), merge: false),
          UpdateOperation(path: DocumentPath("a/b"), data: DotMap({})),
          SetOperation(path: DocumentPath("c/d"), data: DotMap({}), merge: false),
          UpdateOperation(path: DocumentPath("c/d"), data: DotMap({})),
          DeleteOperation(path: DocumentPath("e/f")),
        ]);

        final o = optimizer.$removePreviousOperations(DeleteOperation(path: DocumentPath("a/b")));
        expect(optimizer.operations.length, 3);
        expect(optimizer.operations[0], isA<SetOperation>());
        expect(optimizer.operations[0].path, DocumentPath("c/d"));
        expect(optimizer.operations[1], isA<UpdateOperation>());
        expect(optimizer.operations[1].path, DocumentPath("c/d"));
        expect(optimizer.operations[2], isA<DeleteOperation>());
        expect(optimizer.operations[2].path, DocumentPath("e/f"));
        expect(o, 2);

        print("operations: ${optimizer.operations}");
      });

      test('use a set without merge - should be the same result', () {
        final optimizer = MockBatchManager([
          SetOperation(path: DocumentPath("a/b"), data: DotMap({}), merge: false),
          UpdateOperation(path: DocumentPath("a/b"), data: DotMap({})),
          SetOperation(path: DocumentPath("c/d"), data: DotMap({}), merge: true),
          UpdateOperation(path: DocumentPath("c/d"), data: DotMap({})),
          DeleteOperation(path: DocumentPath("e/f")),
        ]);

        final o = optimizer
            .$removePreviousOperations(SetOperation(path: DocumentPath("a/b"), data: DotMap({}), merge: false));
        expect(optimizer.operations.length, 3);
        expect(optimizer.operations[0], isA<SetOperation>());
        expect(optimizer.operations[0].path, DocumentPath("c/d"));
        expect(optimizer.operations[1], isA<UpdateOperation>());
        expect(optimizer.operations[1].path, DocumentPath("c/d"));
        expect(optimizer.operations[2], isA<DeleteOperation>());
        expect(optimizer.operations[2].path, DocumentPath("e/f"));
        expect(o, 2);

        print("operations: ${optimizer.operations}");
      });
    });
  });
}
