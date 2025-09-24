import 'package:flutter_test/flutter_test.dart';
import 'package:firestore_optimize/src/database/operations.dart';
import 'package:firestore_optimize/src/database/optimizer/join_operations_mixin.dart';

class MockJoiner with JoinOperationsMixin {
  MockJoiner(this._operations);

  List<BatchOperation> _operations;

  @override
  List<BatchOperation> get operations => _operations;

  @override
  set operations(List<BatchOperation> value) {
    _operations = value;
  }
}

void main() {
  group('all', () {
    group("set on set", () {
      final initial = {
        "a": {"b": 1, "c": 2},
      };
      test("merge false for both - overwrite", () {
        final joiner = MockJoiner([]);
        final previous = SetOperation(path: DocumentPath("test"), data: initial, merge: false);
        final incoming = SetOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 99},
          },
          merge: false,
        );
        final i = joiner.$applySetonSet(previous, incoming);
        expect(i, 1);
        expect(joiner.operations.length, 1);
        expect(joiner.operations.first, isA<SetOperation>());
        final result = joiner.operations.first as SetOperation;
        expect(result != incoming, true);
        expect(result != previous, true);
        expect(result.merge, false);
        expect(result.data, {
          "a": {"b": 99},
        });
      });

      test("merge false for incoming - overwrite", () {
        final joiner = MockJoiner([]);
        final previous = SetOperation(path: DocumentPath("test"), data: initial, merge: true);
        final incoming = SetOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 99},
          },
          merge: false,
        );
        final i = joiner.$applySetonSet(previous, incoming);
        expect(i, 1);
        expect(joiner.operations.length, 1);
        expect(joiner.operations.first, isA<SetOperation>());
        final result = joiner.operations.first as SetOperation;
        expect(result != incoming, true);
        expect(result != previous, true);
        expect(result.merge, false);
        expect(result.data, {
          "a": {"b": 99},
        });
      });

      test("merge true for incoming - merge", () {
        final joiner = MockJoiner([]);
        final previous = SetOperation(path: DocumentPath("test"), data: initial, merge: false);
        final incoming = SetOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 99},
          },
          merge: true,
        );
        final i = joiner.$applySetonSet(previous, incoming);
        expect(i, 1);
        expect(joiner.operations.length, 1);
        expect(joiner.operations.first, isA<SetOperation>());
        final result = joiner.operations.first as SetOperation;
        expect(result != incoming, true);
        expect(result != previous, true);
        expect(result.merge, false);
        expect(result.data, {
          "a": {"b": 99, "c": 2},
        });
      });

      test("merge true for both - merge", () {
        final joiner = MockJoiner([]);
        final previous = SetOperation(path: DocumentPath("test"), data: initial, merge: true);
        final incoming = SetOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 99},
          },
          merge: true,
        );
        final i = joiner.$applySetonSet(previous, incoming);
        expect(i, 1);
        expect(joiner.operations.length, 1);
        expect(joiner.operations.first, isA<SetOperation>());
        final result = joiner.operations.first as SetOperation;
        expect(result != incoming, true);
        expect(result != previous, true);
        expect(result.merge, true);
        expect(result.data, {
          "a": {"b": 99, "c": 2},
        });
      });
    });

    group("update on set", () {
      test("merge false for both - overwrite parts", () {
        final joiner = MockJoiner([]);
        final previous = SetOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 1, "c": 2},
            "b": "stub",
          },
          merge: false,
        );
        final incoming = UpdateOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 99},
            "c": 123,
          },
        );
        expect(incoming.merge, false);
        final i = joiner.$applyUpdateOnSet(previous, incoming);
        expect(i, 1);
        expect(joiner.operations.length, 1);
        expect(joiner.operations.first, isA<SetOperation>());
        final result = joiner.operations.first as SetOperation;
        expect(result != incoming, true);
        expect(result != previous, true);
        expect(result.merge, false);
        expect(result.data, {
          "a": {"b": 99},
          "b": "stub",
          "c": 123,
        });
      });

      test("merge false for incoming - overwrite parts", () {
        final joiner = MockJoiner([]);
        final previous = SetOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 1, "c": 2},
            "b": "stub",
          },
          merge: true,
        );
        final incoming = UpdateOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 99},
            "c": 123,
          },
        );
        expect(incoming.merge, false);
        final i = joiner.$applyUpdateOnSet(previous, incoming);
        expect(i, 1);
        expect(joiner.operations.length, 1);
        expect(joiner.operations.first, isA<SetOperation>());
        final result = joiner.operations.first as SetOperation;
        expect(result != incoming, true);
        expect(result != previous, true);
        expect(result.merge, true);
        expect(result.data, {
          "a": {"b": 99},
          "b": "stub",
          "c": 123,
        });
      });

      test("merge false for previous, true for incoming - join maps", () {
        final joiner = MockJoiner([]);
        final previous = SetOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 1, "c": 2},
            "b": "stub",
          },
          merge: false,
        );
        final incoming = UpdateOperation(path: DocumentPath("test"), data: {"a.b": 99, "a.d": 77, "c": 123});
        expect(incoming.merge, true);
        final i = joiner.$applyUpdateOnSet(previous, incoming);
        expect(i, 1);
        expect(joiner.operations.length, 1);
        expect(joiner.operations.first, isA<SetOperation>());
        final result = joiner.operations.first as SetOperation;
        expect(result != incoming, true);
        expect(result != previous, true);
        expect(result.merge, false);
        expect(result.data, {
          "a": {"b": 99, "c": 2, "d": 77},
          "b": "stub",
          "c": 123,
        });
      });

      test("merge true for both - join maps", () {
        final joiner = MockJoiner([]);
        final previous = SetOperation(
          path: DocumentPath("test"),
          data: {
            "a": {"b": 1, "c": 2},
            "b": "stub",
          },
          merge: true,
        );
        final incoming = UpdateOperation(path: DocumentPath("test"), data: {"a.b": 99, "a.d": 77, "c": 123});
        expect(incoming.merge, true);
        final i = joiner.$applyUpdateOnSet(previous, incoming);
        expect(i, 1);
        expect(joiner.operations.length, 1);
        expect(joiner.operations.first, isA<SetOperation>());
        final result = joiner.operations.first as SetOperation;
        expect(result != incoming, true);
        expect(result != previous, true);
        expect(result.merge, true);
        expect(result.data, {
          "a": {"b": 99, "c": 2, "d": 77},
          "b": "stub",
          "c": 123,
        });
      });

      group("set on update", () {
        test("merge false for both - full overwrite", () {
          final joiner = MockJoiner([]);
          final previous = UpdateOperation(
            path: DocumentPath("test"),
            data: {
              "a": {"b": 1, "c": 2},
              "b": "stub",
            },
          );
          final incoming = SetOperation(
            path: DocumentPath("test"),
            data: {
              "a": {"b": 99},
              "c": 123,
            },
            merge: false,
          );
          expect(incoming.merge, false);
          final i = joiner.$applySetonUpdate(previous, incoming);
          expect(i, 1);
          expect(joiner.operations.length, 1);
          expect(joiner.operations.first, isA<SetOperation>());
          final result = joiner.operations.first as SetOperation;
          expect(result != incoming, true);
          expect(result != previous, true);
          expect(result.merge, false);
          expect(result.data, {
            "a": {"b": 99},
            "c": 123,
          });
        });
        test("merge false for incoming - full overwrite", () {
          final joiner = MockJoiner([]);
          final previous = UpdateOperation(path: DocumentPath("test"), data: {"a.b": 1, "a.c": 2, "b": "stub"});
          final incoming = SetOperation(
            path: DocumentPath("test"),
            data: {
              "a": {"b": 99},
              "c": 123,
            },
            merge: false,
          );
          expect(previous.merge, true);
          expect(incoming.merge, false);
          final i = joiner.$applySetonUpdate(previous, incoming);
          expect(i, 1);
          expect(joiner.operations.length, 1);
          expect(joiner.operations.first, isA<SetOperation>());
          final result = joiner.operations.first as SetOperation;
          expect(result != incoming, true);
          expect(result != previous, true);
          expect(result.merge, false);
          expect(result.data, {
            "a": {"b": 99},
            "c": 123,
          });
        });
        test("merge false for previous - join maps", () {
          final joiner = MockJoiner([]);
          final previous = UpdateOperation(
            path: DocumentPath("test"),
            data: {
              "a": {"b": 1, "c": 2},
              "b": "stub",
            },
          );
          final incoming = SetOperation(
            path: DocumentPath("test"),
            data: {
              "a": {
                "b": 99,
                "d": {"e": 123},
              },
              "c": 123,
            },
            merge: true,
          );
          expect(previous.merge, false);
          expect(incoming.merge, true);
          final i = joiner.$applySetonUpdate(previous, incoming);
          expect(i, 1);
          expect(joiner.operations.length, 1);
          expect(joiner.operations.first, isA<SetOperation>());
          final result = joiner.operations.first as SetOperation;
          expect(result != incoming, true);
          expect(result != previous, true);
          expect(result.merge, true);
          expect(result.data, {
            "a": {
              "b": 99,
              "c": 2,
              "d": {"e": 123},
            },
            "b": "stub",
            "c": 123,
          });
        });

        test("merge true for both - join maps", () {
          final joiner = MockJoiner([]);
          final previous = UpdateOperation(path: DocumentPath("test"), data: {"a.b": 1, "a.c": 2, "b": "stub"});
          final incoming = SetOperation(
            path: DocumentPath("test"),
            data: {
              "a": {
                "b": 99,
                "d": {"e": 12},
              },
              "c": 123,
            },
            merge: true,
          );
          expect(previous.merge, true);
          expect(incoming.merge, true);
          final i = joiner.$applySetonUpdate(previous, incoming);
          expect(i, 1);
          expect(joiner.operations.length, 1);
          expect(joiner.operations.first, isA<SetOperation>());
          final result = joiner.operations.first as SetOperation;
          expect(result != incoming, true);
          expect(result != previous, true);
          expect(result.merge, true);
          expect(result.data, {'a.b': 99, 'a.c': 2, 'b': 'stub', 'a.d.e': 12, 'c': 123});
        });
      });

      group("update on update", () {
        test("merge false for both - partial overwrite", () {
          final joiner = MockJoiner([]);
          final previous = UpdateOperation(
            path: DocumentPath("test"),
            data: {
              "a": {"b": 1, "c": 2},
              "b": "stub",
            },
          );
          final incoming = UpdateOperation(
            path: DocumentPath("test"),
            data: {
              "a": {"b": 99},
              "c": 123,
            },
          );
          expect(previous.merge, false);
          expect(incoming.merge, false);
          final i = joiner.$applyUpdateOnUpdate(previous, incoming);
          expect(i, 1);
          expect(joiner.operations.length, 1);
          expect(joiner.operations.first, isA<UpdateOperation>());
          final result = joiner.operations.first as UpdateOperation;
          expect(result != incoming, true);
          expect(result != previous, true);
          expect(result.merge, false);
          expect(result.data, {
            "a": {"b": 99},
            "b": "stub",
            "c": 123,
          });
        });
        test("merge false for incoming - partial overwrite", () {
          final joiner = MockJoiner([]);
          final previous = UpdateOperation(
            path: DocumentPath("test"),
            data: {"a.b": 1, "a.c": 2, "b": "stub", "m.n.p": "should_remove", "m.n.o.a": 3, "m.n.o.b": 4, "z.x.y": 9},
          );
          final incoming = UpdateOperation(
            path: DocumentPath("test"),
            data: {
              "a": {"b": 99},
              "c": 123,
              "m": {
                "n": {"o": "replace"},
              },
            },
          );
          expect(previous.merge, true);
          expect(incoming.merge, false);
          final i = joiner.$applyUpdateOnUpdate(previous, incoming);
          expect(i, 1);
          expect(joiner.operations.length, 1);
          expect(joiner.operations.first, isA<UpdateOperation>());
          final result = joiner.operations.first as UpdateOperation;
          expect(result != incoming, true);
          expect(result != previous, true);
          expect(result.merge, true);
          expect(result.data, {
            "a": {"b": 99},
            "b": "stub",
            "c": 123,
            "m": {
              "n": {"o": "replace"},
            },
            "z.x.y": 9,
          });
        });
        test("merge false for previous - join maps", () {
          final joiner = MockJoiner([]);
          final previous = UpdateOperation(
            path: DocumentPath("test"),
            data: {
              "a": {"b": 99, "c": 22},
              "c": 123,
              "m": {
                "n": {"o": "replace"},
              },
            },
          );
          final incoming = UpdateOperation(
            path: DocumentPath("test"),
            data: {"a.b": 1, "b": "stub", "m.n.p": "should_add", "m.n.o.a": 3, "m.n.o.b": 4, "z.x.y": 9},
          );
          expect(previous.merge, false);
          expect(incoming.merge, true);
          final i = joiner.$applyUpdateOnUpdate(previous, incoming);
          expect(i, 1);
          expect(joiner.operations.length, 1);
          expect(joiner.operations.first, isA<UpdateOperation>());
          final result = joiner.operations.first as UpdateOperation;
          expect(result != incoming, true);
          expect(result != previous, true);
          expect(result.merge, true);
          expect(result.data, {
            "a": {"b": 1, "c": 22},
            "b": "stub",
            "c": 123,
            "m": {
              "n": {
                "p": "should_add",
                "o": {"a": 3, "b": 4},
              },
            },
            "z.x.y": 9,
          });
        });

        test("merge true for both - join maps", () {
          final joiner = MockJoiner([]);
          final previous = UpdateOperation(
            path: DocumentPath("test"),
            data: {
              "a.b": 1,
              "a.c": 2,
              "text": "stub",
              "d.e": 3,
              "d.f": 4,
              "text2": "overwrite",
              "e.a": {"b": 10},
              "f.a": {"b": 10},
              "g.a.b": {"c": 1},
            },
          );
          final incoming = UpdateOperation(
            path: DocumentPath("test"),
            data: {
              "a": {
                "b": 99,
                "d": {"e": 123},
              },
              "c": 123,
              "d.g": 5,
              "text2": 6,
              "e.a.b": 15,
              "f.b": {"c": 18},
              "g.a": 10,
            },
          );
          expect(previous.merge, true);
          expect(incoming.merge, true);
          final i = joiner.$applyUpdateOnUpdate(previous, incoming);
          expect(i, 1);
          expect(joiner.operations.length, 1);
          expect(joiner.operations.first, isA<UpdateOperation>());
          final result = joiner.operations.first as UpdateOperation;
          expect(result != incoming, true);
          expect(result != previous, true);
          expect(result.merge, true);
          expect(result.data, {
            "a": {
              "b": 99,
              "d": {"e": 123},
            },
            "text": "stub",
            "c": 123,
            "d.e": 3,
            "d.f": 4,
            "d.g": 5,
            "text2": 6,
            "e.a": {"b": 15},
            "f.a": {"b": 10},
            "f.b": {"c": 18},
            "g.a": 10,
          });
        });
      });
    });
  });
}
