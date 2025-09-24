import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firestore_optimize/src/database/operations.dart';
import 'package:firestore_optimize/src/database/jit_field_value.dart';

void main() {
  group('SetOperation', () {
    test('set with overwrite - drop deletes', () {
      final operation = SetOperation(
        path: DocumentPath("doc"),
        data: {
          "user.name": "John",
          "user.age": 30,
          "user.username": JitDelete(),
          "settings": {
            "ip": "123.123.123.123",
          },
          "status": "active",
        },
        merge: false,
      );

      final result = operation.finalize;

      expect(result, {
        "user": {
          "name": "John",
          "age": 30,
        },
        "settings": {
          "ip": "123.123.123.123",
        },
        "status": "active"
      });
    });

    test('set with merge', () {
      final operation = SetOperation(
        path: DocumentPath("doc"),
        data: {
          "user.name": "John",
          "user.age": 30,
          "user.username": JitDelete(),
          "settings": {
            "ip": "123.123.123.123",
            "port": JitFieldValue.arrayUnion([8080, 8081]),
          },
          "status": "active",
        },
        merge: true,
      );

      final result = operation.finalize;

      expect(result, {
        "user": {
          "name": "John",
          "age": 30,
          "username": FieldValue.delete(),
        },
        "settings": {
          "ip": "123.123.123.123",
          "port": FieldValue.arrayUnion([8080, 8081]),
        },
        "status": "active"
      });
    });
  });

  group('UpdateOperation', () {
    test('update', () {
      final operation = UpdateOperation(
        path: DocumentPath("doc"),
           data: {
          "user.name": "John",
          "user.age": 30,
          "user.username": JitDelete(),
          "settings": {
            "ip": "123.123.123.123",
            "port": JitFieldValue.arrayUnion([8080, 8081]),
          },
          "status": "active",
        },
      );

      final result = operation.finalize;

      expect(result, {
        "user.name": "John",
        "user.age": 30,
        "user.username": FieldValue.delete(),
        "settings": {
          "ip": "123.123.123.123",
          "port": FieldValue.arrayUnion([8080, 8081]),
        },
        "status": "active"
      });
    });
  });
  ;
}
