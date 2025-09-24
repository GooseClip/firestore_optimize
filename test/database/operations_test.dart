import 'package:flutter_test/flutter_test.dart';
import 'package:firestore_optimize/src/database/operations.dart';

void main() {
  group('all', () {
    group('SetOperation', () {
      group('finalize with merge: false', () {
        test('should convert from dot notation to nested map', () {
          final operation = SetOperation(
            path: DocumentPath("users/123"),
            data: {"user.name": "John", "user.age": 30, "status": "active"},
            merge: false,
          );

          final result = operation.finalize;

          expect(result, {
            "user": {"name": "John", "age": 30},
            "status": "active",
          });
        });

        test('should handle nested maps without dot notation', () {
          final operation = SetOperation(
            path: DocumentPath("users/123"),
            data: {
              "user": {"name": "John", "age": 30},
              "status": "active",
            },
            merge: false,
          );

          final result = operation.finalize;

          expect(result, {
            "user": {"name": "John", "age": 30},
            "status": "active",
          });
        });

        test('should handle empty data', () {
          final operation = SetOperation(path: DocumentPath("users/123"), data: {}, merge: false);

          final result = operation.finalize;

          expect(result, {});
        });
      });
    });

    group('UpdateOperation', () {
      test('toString should return correct format', () {
        final operation = UpdateOperation(path: DocumentPath("users/123"), data: {"name": "John"});

        expect(operation.toString(), "[UpdateOperation][users/123]");
      });

      test('should preserve existing dot notation', () {
        final operation = UpdateOperation(
          path: DocumentPath("users/123"),
          data: {"user.name": "John", "user.age": 30, "status": "active"},
        );

        final result = operation.finalize;

        expect(result, {"user.name": "John", "user.age": 30, "status": "active"});
      });

      test('should handle empty data', () {
        final operation = UpdateOperation(path: DocumentPath("users/123"), data: {});

        final result = operation.finalize;

        expect(result, {});
      });
    });
  });
}
