import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firestore_optimize/src/database/dot_util.dart';

void main() {
  group('all', () {
    group('DotNotation', () {
      test('should create DotNotation with field path and value', () {
        final dotNotation = DotNotation('user.name', 'John Doe');

        expect(dotNotation.fieldPath, 'user.name');
        expect(dotNotation.value, 'John Doe');
      });

      test('should have proper toString representation', () {
        final dotNotation = DotNotation('user.age', 25);

        expect(dotNotation.toString(), 'DotNotation{fieldPath: user.age, value: 25}');
      });

      test('should handle null values', () {
        final dotNotation = DotNotation('user.email', null);

        expect(dotNotation.fieldPath, 'user.email');
        expect(dotNotation.value, null);
        expect(dotNotation.toString(), 'DotNotation{fieldPath: user.email, value: null}');
      });
    });

    group('toDotNotation', () {
      test('should handle empty map', () {
        final result = toDotNotation({});

        expect(result, isEmpty);
      });

      test('should handle simple flat map', () {
        final data = {
          'name': 'John',
          'age': 30,
          'active': true,
        };

        final result = toDotNotation(data);

        expect(result.length, 3);
        expect(result.any((dot) => dot.fieldPath == 'name' && dot.value == 'John'), true);
        expect(result.any((dot) => dot.fieldPath == 'age' && dot.value == 30), true);
        expect(result.any((dot) => dot.fieldPath == 'active' && dot.value == true), true);
      });

      test('should handle nested maps', () {
        final data = {
          'user': {
            'profile': {
              'name': 'Jane',
              'age': 25,
            },
            'settings': {
              'theme': 'dark',
            },
          },
          'status': 'active',
        };

        final result = toDotNotation(data);

        expect(result.length, 4);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.name' && dot.value == 'Jane'), true);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.age' && dot.value == 25), true);
        expect(result.any((dot) => dot.fieldPath == 'user.settings.theme' && dot.value == 'dark'), true);
        expect(result.any((dot) => dot.fieldPath == 'status' && dot.value == 'active'), true);
      });

      test('should handle lists as single values', () {
        final data = {
          'tags': ['flutter', 'dart', 'mobile'],
          'scores': [95, 87, 92],
          'user': {
            'hobbies': ['reading', 'coding'],
          },
        };

        final result = toDotNotation(data);

        expect(result.length, 3);
        expect(
            result.any(
                (dot) => dot.fieldPath == 'tags' && dot.value.toString() == ['flutter', 'dart', 'mobile'].toString()),
            true);
        expect(result.any((dot) => dot.fieldPath == 'scores' && dot.value.toString() == [95, 87, 92].toString()), true);
        expect(
            result.any(
                (dot) => dot.fieldPath == 'user.hobbies' && dot.value.toString() == ['reading', 'coding'].toString()),
            true);
      });

      test('should handle mixed data types', () {
        final data = {
          'string': 'hello',
          'number': 42,
          'boolean': false,
          'nullValue': null,
          'list': [1, 2, 3],
          'nested': {
            'double': 3.14,
            'innerList': ['a', 'b'],
          },
        };

        final result = toDotNotation(data);

        expect(result.length, 7);
        expect(result.any((dot) => dot.fieldPath == 'string' && dot.value == 'hello'), true);
        expect(result.any((dot) => dot.fieldPath == 'number' && dot.value == 42), true);
        expect(result.any((dot) => dot.fieldPath == 'boolean' && dot.value == false), true);
        expect(result.any((dot) => dot.fieldPath == 'nullValue' && dot.value == null), true);
        expect(result.any((dot) => dot.fieldPath == 'list' && dot.value.toString() == [1, 2, 3].toString()), true);
        expect(result.any((dot) => dot.fieldPath == 'nested.double' && dot.value == 3.14), true);
        expect(
            result.any((dot) => dot.fieldPath == 'nested.innerList' && dot.value.toString() == ['a', 'b'].toString()),
            true);
      });

      test('should handle deeply nested structures', () {
        final data = {
          'level1': {
            'level2': {
              'level3': {
                'level4': {
                  'value': 'deep',
                },
              },
            },
          },
        };

        final result = toDotNotation(data);

        expect(result.length, 1);
        expect(result.first.fieldPath, 'level1.level2.level3.level4.value');
        expect(result.first.value, 'deep');
      });

      test('should handle empty nested maps', () {
        final data = {
          'user': {
            'name': 'John',
            'profile': {},
          },
          'settings': {},
        };

        final result = toDotNotation(data);

        expect(result.length, 3);
        expect(result[0].fieldPath, 'user.name');
        expect(result[0].value, 'John');
        expect(result[1].fieldPath, 'user.profile');
        expect(result[1].value, {});
        expect(result[2].fieldPath, 'settings');
        expect(result[2].value, {});
      });

      test('should handle maps with numeric keys as strings', () {
        final data = {
          'items': {
            '0': 'first',
            '1': 'second',
          },
          'count': 2,
        };

        final result = toDotNotation(data);

        expect(result.length, 3);
        expect(result.any((dot) => dot.fieldPath == 'items.0' && dot.value == 'first'), true);
        expect(result.any((dot) => dot.fieldPath == 'items.1' && dot.value == 'second'), true);
        expect(result.any((dot) => dot.fieldPath == 'count' && dot.value == 2), true);
      });

      test('should handle complex real-world example', () {
        final data = {
          'user': {
            'id': 'user123',
            'profile': {
              'firstName': 'John',
              'lastName': 'Doe',
              'contact': {
                'email': 'john@example.com',
                'phone': '+1234567890',
              },
            },
            'preferences': {
              'notifications': true,
              'theme': 'dark',
            },
            'tags': ['premium', 'verified'],
          },
          'metadata': {
            'createdAt': '2023-01-01',
            'version': 1,
          },
          'active': true,
        };

        final result = toDotNotation(data);

        expect(result.length, 11);
        expect(result.any((dot) => dot.fieldPath == 'user.id' && dot.value == 'user123'), true);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.firstName' && dot.value == 'John'), true);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.lastName' && dot.value == 'Doe'), true);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.contact.email' && dot.value == 'john@example.com'),
            true);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.contact.phone' && dot.value == '+1234567890'), true);
        expect(result.any((dot) => dot.fieldPath == 'user.preferences.notifications' && dot.value == true), true);
        expect(result.any((dot) => dot.fieldPath == 'user.preferences.theme' && dot.value == 'dark'), true);
        expect(
            result.any(
                (dot) => dot.fieldPath == 'user.tags' && dot.value.toString() == ['premium', 'verified'].toString()),
            true);
        expect(result.any((dot) => dot.fieldPath == 'metadata.createdAt' && dot.value == '2023-01-01'), true);
        expect(result.any((dot) => dot.fieldPath == 'metadata.version' && dot.value == 1), true);
        expect(result.any((dot) => dot.fieldPath == 'active' && dot.value == true), true);
      });

      test('should maintain existing dot notation', () {
        final data = {
          'settings.preferences.username': 'Johnny',
          'user': {
            'id': 'user123',
            'profile': {
              'firstName': 'John',
            },
          },
        };

        final result = toDotNotation(data);
        print(result);

        expect(result.length, 3);
        expect(
            result.any(
                (dot) => dot.fieldPath == 'settings.preferences.username' && dot.value == 'Johnny' && dot.wasDot),
            true);
        expect(result.any((dot) => dot.fieldPath == 'user.id' && dot.value == 'user123' && !dot.wasDot), true);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.firstName' && dot.value == 'John' && !dot.wasDot),
            true);
      });

      test('should handle dot notation with array remove', () {
        final data = {
          'tags': FieldValue.arrayRemove(['old-tag', 'deprecated']),
          'user': {
            'permissions': FieldValue.arrayRemove(['read-only']),
          },
        };

        final result = toDotNotation(data);

        expect(result.length, 2);
        expect(result.any((dot) => dot.fieldPath == 'tags' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'user.permissions' && dot.value is FieldValue), true);
      });

      test('should handle dot notation with array union', () {
        final data = {
          'tags': FieldValue.arrayUnion(['new-tag', 'featured']),
          'user': {
            'roles': FieldValue.arrayUnion(['admin']),
          },
          'metadata': {
            'flags': FieldValue.arrayUnion(['verified', 'premium']),
          },
        };

        final result = toDotNotation(data);

        expect(result.length, 3);
        expect(result.any((dot) => dot.fieldPath == 'tags' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'user.roles' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'metadata.flags' && dot.value is FieldValue), true);
      });

      test('should handle dot notation with delete', () {
        final data = {
          'temporaryField': FieldValue.delete(),
          'user': {
            'oldEmail': FieldValue.delete(),
            'profile': {
              'deprecated': FieldValue.delete(),
            },
          },
          'settings': {
            'cache': FieldValue.delete(),
          },
        };

        final result = toDotNotation(data);

        expect(result.length, 4);
        expect(result.any((dot) => dot.fieldPath == 'temporaryField' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'user.oldEmail' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.deprecated' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'settings.cache' && dot.value is FieldValue), true);

        // Verify all are FieldValue instances
        for (final dot in result) {
          expect(dot.value, isA<FieldValue>());
        }
      });

      test('should handle mixed FieldValue operations', () {
        final data = {
          'tags': FieldValue.arrayUnion(['new']),
          'oldTags': FieldValue.arrayRemove(['old']),
          'deprecated': FieldValue.delete(),
          'user': {
            'permissions': FieldValue.arrayUnion(['write']),
            'oldPermissions': FieldValue.delete(),
            'profile': {
              'name': 'John',
              'tempData': FieldValue.delete(),
            },
          },
          'normalField': 'normalValue',
        };

        final result = toDotNotation(data);

        expect(result.length, 8);

        // Check FieldValue operations
        expect(result.any((dot) => dot.fieldPath == 'tags' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'oldTags' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'deprecated' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'user.permissions' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'user.oldPermissions' && dot.value is FieldValue), true);
        expect(result.any((dot) => dot.fieldPath == 'user.profile.tempData' && dot.value is FieldValue), true);

        // Check normal values
        expect(result.any((dot) => dot.fieldPath == 'user.profile.name' && dot.value == 'John'), true);
        expect(result.any((dot) => dot.fieldPath == 'normalField' && dot.value == 'normalValue'), true);
      });
    });

    group('fromDotNotation', () {
      test('should handle empty map', () {
        final result = fromDotMap(DotMap({}));

        expect(result, isEmpty);
      });

      test('should handle simple flat keys without dots', () {
        final data = {
          'name': 'John',
          'age': 30,
          'active': true,
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'name': 'John',
          'age': 30,
          'active': true,
        });
      });

      test('should convert simple dot notation to nested structure', () {
        final data = {
          'user.name': 'John',
          'user.age': 30,
          'user.active': true,
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'user': {
            'name': 'John',
            'age': 30,
            'active': true,
          },
        });
      });

      test('should handle deeply nested dot notation', () {
        final data = {
          'user.profile.personal.name': 'Jane',
          'user.profile.personal.age': 25,
          'user.profile.contact.email': 'jane@example.com',
          'user.profile.contact.phone': '+1234567890',
          'user.settings.theme': 'dark',
          'user.settings.notifications': true,
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'user': {
            'profile': {
              'personal': {
                'name': 'Jane',
                'age': 25,
              },
              'contact': {
                'email': 'jane@example.com',
                'phone': '+1234567890',
              },
            },
            'settings': {
              'theme': 'dark',
              'notifications': true,
            },
          },
        });
      });

      test('should handle mixed dot notation and flat keys', () {
        final data = {
          'user.name': 'John',
          'user.profile.age': 30,
          'status': 'active',
          'metadata.version': 1,
          'simple': 'value',
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'user': {
            'name': 'John',
            'profile': {
              'age': 30,
            },
          },
          'status': 'active',
          'metadata': {
            'version': 1,
          },
          'simple': 'value',
        });
      });

      test('should handle various data types', () {
        final data = {
          'string.value': 'hello',
          'number.int': 42,
          'number.double': 3.14,
          'boolean.true': true,
          'boolean.false': false,
          'null.value': null,
          'list.items': [1, 2, 3],
          'list.strings': ['a', 'b', 'c'],
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'string': {'value': 'hello'},
          'number': {'int': 42, 'double': 3.14},
          'boolean': {'true': true, 'false': false},
          'null': {'value': null},
          'list': {
            'items': [1, 2, 3],
            'strings': ['a', 'b', 'c'],
          },
        });
      });

      test('should handle numeric keys as strings', () {
        final data = {
          'items.0.name': 'first',
          'items.0.value': 100,
          'items.1.name': 'second',
          'items.1.value': 200,
          'count': 2,
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'items': {
            '0': {
              'name': 'first',
              'value': 100,
            },
            '1': {
              'name': 'second',
              'value': 200,
            },
          },
          'count': 2,
        });
      });

      test('should handle FieldValue operations', () {
        final data = {
          'tags': FieldValue.arrayUnion(['new-tag']),
          'user.permissions': FieldValue.arrayRemove(['old-permission']),
          'user.profile.deprecated': FieldValue.delete(),
          'metadata.cache': FieldValue.delete(),
        };

        final result = fromDotMap(DotMap(data));

        expect(result['tags'], isA<FieldValue>());
        expect(result['user']['permissions'], isA<FieldValue>());
        expect(result['user']['profile']['deprecated'], isA<FieldValue>());
        expect(result['metadata']['cache'], isA<FieldValue>());
      });

      test('should handle complex real-world example', () {
        final data = {
          'user.id': 'user123',
          'user.profile.firstName': 'John',
          'user.profile.lastName': 'Doe',
          'user.profile.contact.email': 'john@example.com',
          'user.profile.contact.phone': '+1234567890',
          'user.preferences.notifications': true,
          'user.preferences.theme': 'dark',
          'user.tags': ['premium', 'verified'],
          'metadata.createdAt': '2023-01-01',
          'metadata.version': 1,
          'active': true,
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'user': {
            'id': 'user123',
            'profile': {
              'firstName': 'John',
              'lastName': 'Doe',
              'contact': {
                'email': 'john@example.com',
                'phone': '+1234567890',
              },
            },
            'preferences': {
              'notifications': true,
              'theme': 'dark',
            },
            'tags': ['premium', 'verified'],
          },
          'metadata': {
            'createdAt': '2023-01-01',
            'version': 1,
          },
          'active': true,
        });
      });

      test('should be inverse of toDotNotation for simple cases', () {
        final original = {
          'user': {
            'name': 'John',
            'age': 30,
          },
          'status': 'active',
        };

        final dotNotations = toDotNotation(original);
        final dotMap = <String, dynamic>{};
        for (final dot in dotNotations) {
          dotMap[dot.fieldPath] = dot.value;
        }

        final reconstructed = fromDotMap(DotMap(dotMap));

        expect(reconstructed, original);
      });

      test('should handle single level deep paths', () {
        final data = {
          'user.name': 'John',
          'user.age': 30,
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'user': {
            'name': 'John',
            'age': 30,
          },
        });
      });

      test('should handle very deep nesting', () {
        final data = {
          'level1.level2.level3.level4.level5.value': 'deep',
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'level1': {
            'level2': {
              'level3': {
                'level4': {
                  'level5': {
                    'value': 'deep',
                  },
                },
              },
            },
          },
        });
      });

      test('should handle keys with special characters', () {
        final data = {
          'user.profile.first-name': 'John',
          'user.profile.last_name': 'Doe',
          'user.settings.theme-color': 'blue',
        };

        final result = fromDotMap(DotMap(data));

        expect(result, {
          'user': {
            'profile': {
              'first-name': 'John',
              'last_name': 'Doe',
            },
            'settings': {
              'theme-color': 'blue',
            },
          },
        });
      });

      group('Path Conflicts and Edge Cases', () {
        test('should throw when conflicting paths with simple value vs nested structure', () {
          final data = {
            'user': 'SimpleString',
            'user.name': 'John',
            'user.age': 30,
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Path conflict detected'),
            )),
          );
        });

        test('should throw on complex conflicting paths', () {
          final data = {
            'config': 'basic-config',
            'config.database.host': 'localhost',
            'config.database.port': 5432,
            'config.api.version': 'v1',
            'settings.theme': 'light',
            'settings.notifications': true,
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Path conflict detected'),
            )),
          );
        });

        test('should throw on multiple levels of conflicts', () {
          final data = {
            'data': 'root-value',
            'data.level1': 'level1-value',
            'data.level1.level2': 'level2-value',
            'data.level1.level2.level3': 'level3-value',
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Path conflict detected'),
            )),
          );
        });

        test('should throw on conflicts with different data types', () {
          final data = {
            'value': 42,
            'value.string': 'text',
            'value.boolean': true,
            'value.list': [1, 2, 3],
            'number': 3.14,
            'number.precision': 2,
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Path conflict detected'),
            )),
          );
        });

        test('should handle empty key parts (consecutive dots)', () {
          final data = {
            'user..name': 'John',
            'valid.key': 'value',
            'another...key': 'test',
            '.startDot': 'value',
            'endDot.': 'value',
          };

          final result = fromDotMap(DotMap(data));

          // Should only process valid keys
          expect(result, {
            'valid': {
              'key': 'value',
            },
          });
        });

        test('should handle empty strings as keys', () {
          final data = {
            '': 'empty-key',
            'normal.key': 'value',
            'user.': 'trailing-dot',
          };

          final result = fromDotMap(DotMap(data));

          // Should only process valid keys
          expect(result, {
            'normal': {
              'key': 'value',
            },
          });
        });

        test('should throw on single character key conflicts', () {
          final data = {
            'a': 'single',
            'a.b': 'nested',
            'x.y.z': 'deep',
            'a.b.c.d.e.f': 'very-deep',
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Path conflict detected'),
            )),
          );
        });

        test('should throw on conflicts with FieldValue operations', () {
          final data = {
            'tags': ['existing', 'tags'],
            'tags.add': FieldValue.arrayUnion(['new']),
            'tags.remove': FieldValue.arrayRemove(['old']),
            'user': FieldValue.delete(),
            'user.name': 'John',
            'user.profile.email': 'john@example.com',
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Path conflict detected'),
            )),
          );
        });

        test('should throw on null value conflicts', () {
          final data = {
            'data': null,
            'data.value': 'should-cause-error',
            'config': null,
            'config.setting': true,
            'valid.null': null,
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Path conflict detected'),
            )),
          );
        });

        test('should preserve order when no conflicts exist', () {
          final data = {
            'z.last': 'last',
            'a.first': 'first',
            'm.middle': 'middle',
            'b.second': 'second',
          };

          final result = fromDotMap(DotMap(data));

          expect(result, {
            'z': {'last': 'last'},
            'a': {'first': 'first'},
            'm': {'middle': 'middle'},
            'b': {'second': 'second'},
          });
        });

        test('should handle mixed valid and invalid keys', () {
          final data = {
            'valid.key1': 'value1',
            '': 'empty',
            'valid.key2': 'value2',
            'invalid..key': 'invalid',
            'valid.key3': 'value3',
            'another.': 'trailing',
            'valid.nested.deep': 'deep-value',
          };

          final result = fromDotMap(DotMap(data));

          expect(result, {
            'valid': {
              'key1': 'value1',
              'key2': 'value2',
              'key3': 'value3',
              'nested': {
                'deep': 'deep-value',
              },
            },
          });
        });

        test('should throw on extremely deep conflicts', () {
          final data = {
            'a.b.c.d.e.f.g.h.i.j': 'deep-value',
            'a': 'root-value',
            'a.b.c': 'mid-value',
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Path conflict detected'),
            )),
          );
        });

        test('should provide detailed error messages for conflicts', () {
          final data = {
            'user': 'John',
            'user.profile.name': 'Jane',
          };

          expect(
            () => fromDotMap(DotMap(data)),
            throwsA(isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('Path conflict detected'),
                contains('user.profile.name'),
                contains('user'),
                contains('String'),
                contains('John'),
              ]),
            )),
          );
        });

        test('should handle valid cases without conflicts', () {
          final data = {
            // Valid cases without conflicts
            'user.name': 'John',
            'user.profile.email': 'john@example.com',
            'settings.theme.colors.primary': '#blue',
            'settings.theme.colors.secondary': '#green',
            'config.database.host': 'localhost',
            'config.database.port': 5432,
          };

          final result = fromDotMap(DotMap(data));

          expect(result, {
            'user': {
              'name': 'John',
              'profile': {
                'email': 'john@example.com',
              },
            },
            'settings': {
              'theme': {
                'colors': {
                  'primary': '#blue',
                  'secondary': '#green',
                },
              },
            },
            'config': {
              'database': {
                'host': 'localhost',
                'port': 5432,
              },
            },
          });
        });
      });
    });

    group('isDot', () {
      test('should return true for maps with dot notation keys', () {
        expect(isDot({'user.name': 'John', 'user.age': 30}), true);
      });

      test('should return false for maps without dot notation keys', () {
        expect(isDot({'user': 'John', 'age': 30}), false);
      });

      test('should return false for empty map', () {
        expect(isDot({}), false);
      });

      test('should return true if any key contains dots', () {
        expect(isDot({'normalKey': 'value', 'dot.key': 'value'}), true);
      });
    });
  });
}
