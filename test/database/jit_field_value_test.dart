import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firestore_optimize/src/database/jit_field_value.dart';

void main() {
  group('JitFieldValue', () {
    group('JitArrayUnion', () {
      test('should create FieldValue.arrayUnion when replace() is called', () {
        final jitArrayUnion = JitFieldValue.arrayUnion(['item1', 'item2']);
        final fieldValue = jitArrayUnion.replace();
        
        expect(fieldValue, isA<FieldValue>());
        // Note: We can't directly test the internal value of FieldValue,
        // but we can verify it's the correct type
      });

      test('should handle empty array', () {
        final jitArrayUnion = JitFieldValue.arrayUnion([]);
        final fieldValue = jitArrayUnion.replace();
        
        expect(fieldValue, isA<FieldValue>());
      });

      test('should handle array with mixed types', () {
        final jitArrayUnion = JitFieldValue.arrayUnion(['string', 42, true, {'key': 'value'}]);
        final fieldValue = jitArrayUnion.replace();
        
        expect(fieldValue, isA<FieldValue>());
      });

      test('should be equal when elements are the same', () {
        final union1 = JitFieldValue.arrayUnion(['a', 'b']);
        final union2 = JitFieldValue.arrayUnion(['a', 'b']);
        
        expect(union1, equals(union2));
        expect(union1.hashCode, equals(union2.hashCode));
      });

      test('should not be equal when elements are different', () {
        final union1 = JitFieldValue.arrayUnion(['a', 'b']);
        final union2 = JitFieldValue.arrayUnion(['a', 'c']);
        
        expect(union1, isNot(equals(union2)));
      });
    });

    group('JitArrayRemove', () {
      test('should create FieldValue.arrayRemove when replace() is called', () {
        final jitArrayRemove = JitFieldValue.arrayRemove(['item1', 'item2']);
        final fieldValue = jitArrayRemove.replace();
        
        expect(fieldValue, isA<FieldValue>());
      });

      test('should handle empty array', () {
        final jitArrayRemove = JitFieldValue.arrayRemove([]);
        final fieldValue = jitArrayRemove.replace();
        
        expect(fieldValue, isA<FieldValue>());
      });
    });

    group('JitDelete', () {
      test('should create FieldValue.delete when replace() is called', () {
        final jitDelete = JitFieldValue.delete();
        final fieldValue = jitDelete.replace();
        
        expect(fieldValue, isA<FieldValue>());
      });
    });

    group('JitIncrement', () {
      test('should create FieldValue.increment when replace() is called', () {
        final jitIncrement = JitFieldValue.increment(5);
        final fieldValue = jitIncrement.replace();
        
        expect(fieldValue, isA<FieldValue>());
      });

      test('should handle negative increment', () {
        final jitIncrement = JitFieldValue.increment(-3);
        final fieldValue = jitIncrement.replace();
        
        expect(fieldValue, isA<FieldValue>());
      });

      test('should handle decimal increment', () {
        final jitIncrement = JitFieldValue.increment(2.5);
        final fieldValue = jitIncrement.replace();
        
        expect(fieldValue, isA<FieldValue>());
      });
    });

    group('JitServerTimestamp', () {
      test('should create FieldValue.serverTimestamp when replace() is called', () {
        final jitServerTimestamp = JitFieldValue.serverTimestamp();
        final fieldValue = jitServerTimestamp.replace();

        expect(fieldValue, isA<FieldValue>());
      });
    });
  });

  group('replaceAllJitFieldValues', () {
    test('should replace JitFieldValue instances in flat map', () {
      final input = {
        'name': 'John',
        'count': JitFieldValue.increment(1),
        'tags': JitFieldValue.arrayUnion(['new_tag']),
        'removed': JitFieldValue.delete(),
      };

      final result = replaceAllJitFieldValues(input);

      expect(result['name'], equals('John'));
      expect(result['count'], isA<FieldValue>());
      expect(result['tags'], isA<FieldValue>());
      expect(result['removed'], isA<FieldValue>());
    });

    test('should replace JitServerTimestamp instances in flat map', () {
      final input = {
        'name': 'John',
        'timestamp': JitFieldValue.serverTimestamp(),
      };

      final result = replaceAllJitFieldValues(input);

      expect(result['name'], equals('John'));
      expect(result['timestamp'], isA<FieldValue>());
    });

    test('should handle nested maps', () {
      final input = {
        'user': {
          'name': 'John',
          'count': JitFieldValue.increment(1),
          'profile': {
            'tags': JitFieldValue.arrayUnion(['tag1']),
            'age': 25,
          }
        },
        'status': 'active',
      };

      final result = replaceAllJitFieldValues(input);

      expect(result['user'], isA<Map<String, dynamic>>());
      expect(result['user']['name'], equals('John'));
      expect(result['user']['count'], isA<FieldValue>());
      expect(result['user']['profile'], isA<Map<String, dynamic>>());
      expect(result['user']['profile']['tags'], isA<FieldValue>());
      expect(result['user']['profile']['age'], equals(25));
      expect(result['status'], equals('active'));
    });

    test('should handle arrays with JitFieldValues', () {
      final input = {
        'operations': [
          JitFieldValue.increment(1),
          'string_value',
          {
            'nested': JitFieldValue.delete(),
            'value': 42,
          },
          [
            JitFieldValue.arrayUnion(['nested_array']),
            'another_string',
          ]
        ]
      };

      final result = replaceAllJitFieldValues(input);

      final operations = result['operations'] as List;
      expect(operations[0], isA<FieldValue>()); // increment
      expect(operations[1], equals('string_value'));
      expect(operations[2], isA<Map<String, dynamic>>());
      expect((operations[2] as Map)['nested'], isA<FieldValue>()); // delete
      expect((operations[2] as Map)['value'], equals(42));
      expect(operations[3], isA<List>());
      expect((operations[3] as List)[0], isA<FieldValue>()); // arrayUnion
      expect((operations[3] as List)[1], equals('another_string'));
    });

    test('should handle empty map', () {
      final input = <String, dynamic>{};
      final result = replaceAllJitFieldValues(input);
      
      expect(result, isEmpty);
    });

    test('should handle map with no JitFieldValues', () {
      final input = {
        'name': 'John',
        'age': 30,
        'active': true,
        'scores': [1, 2, 3],
        'metadata': {
          'created': 'today',
          'tags': ['tag1', 'tag2'],
        }
      };

      final result = replaceAllJitFieldValues(input);

      expect(result, equals(input));
    });

    test('should handle deeply nested structures', () {
      final input = {
        'level1': {
          'level2': {
            'level3': {
              'level4': {
                'increment': JitFieldValue.increment(10),
                'delete': JitFieldValue.delete(),
                'regular': 'value',
              }
            }
          }
        }
      };

      final result = replaceAllJitFieldValues(input);

      final level4 = result['level1']['level2']['level3']['level4'];
      expect(level4['increment'], isA<FieldValue>());
      expect(level4['delete'], isA<FieldValue>());
      expect(level4['regular'], equals('value'));
    });

    test('should handle complex mixed scenario', () {
      final input = {
        'user_id': 'user123',
        'counters': {
          'views': JitFieldValue.increment(1),
          'likes': JitFieldValue.increment(2),
        },
        'tags': JitFieldValue.arrayUnion(['new_tag', 'another_tag']),
        'removed_tags': JitFieldValue.arrayRemove(['old_tag']),
        'metadata': {
          'created_at': 'timestamp',
          'updated_fields': [
            'field1',
            {
              'field_name': 'complex_field',
              'operation': JitFieldValue.delete(),
            }
          ],
          'cache': JitFieldValue.delete(),
        },
        'settings': {
          'notifications': true,
          'preferences': {
            'theme': 'dark',
            'language': 'en',
          }
        }
      };

      final result = replaceAllJitFieldValues(input);

      // Check top level
      expect(result['user_id'], equals('user123'));
      expect(result['tags'], isA<FieldValue>());
      expect(result['removed_tags'], isA<FieldValue>());

      // Check counters
      expect(result['counters']['views'], isA<FieldValue>());
      expect(result['counters']['likes'], isA<FieldValue>());

      // Check metadata
      expect(result['metadata']['created_at'], equals('timestamp'));
      expect(result['metadata']['cache'], isA<FieldValue>());

      // Check array with nested map
      final updatedFields = result['metadata']['updated_fields'] as List;
      expect(updatedFields[0], equals('field1'));
      expect(updatedFields[1]['field_name'], equals('complex_field'));
      expect(updatedFields[1]['operation'], isA<FieldValue>());

      // Check unchanged nested structure
      expect(result['settings']['notifications'], isTrue);
      expect(result['settings']['preferences']['theme'], equals('dark'));
      expect(result['settings']['preferences']['language'], equals('en'));
    });
  });

  group('replaceAllJitFieldValues with dropDeletes flag', () {
    test('should drop JitDelete values when dropDeletes is true', () {
      final input = {
        'name': 'John',
        'count': JitFieldValue.increment(1),
        'tags': JitFieldValue.arrayUnion(['new_tag']),
        'removed': JitFieldValue.delete(),
        'status': 'active',
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      expect(result['name'], equals('John'));
      expect(result['count'], isA<FieldValue>());
      expect(result['tags'], isA<FieldValue>());
      expect(result['status'], equals('active'));
      expect(result.containsKey('removed'), isFalse);
    });

    test('should keep JitDelete values when dropDeletes is false (default)', () {
      final input = {
        'name': 'John',
        'removed': JitFieldValue.delete(),
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: false);

      expect(result['name'], equals('John'));
      expect(result['removed'], isA<FieldValue>());
      expect(result.containsKey('removed'), isTrue);
    });

    test('should drop JitDelete values in nested maps when dropDeletes is true', () {
      final input = {
        'user': {
          'name': 'John',
          'count': JitFieldValue.increment(1),
          'toDelete': JitFieldValue.delete(),
          'profile': {
            'tags': JitFieldValue.arrayUnion(['tag1']),
            'age': 25,
            'removeThis': JitFieldValue.delete(),
          }
        },
        'status': 'active',
        'deleteThis': JitFieldValue.delete(),
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      expect(result['user'], isA<Map<String, dynamic>>());
      expect(result['user']['name'], equals('John'));
      expect(result['user']['count'], isA<FieldValue>());
      expect(result['user'].containsKey('toDelete'), isFalse);
      expect(result['user']['profile'], isA<Map<String, dynamic>>());
      expect(result['user']['profile']['tags'], isA<FieldValue>());
      expect(result['user']['profile']['age'], equals(25));
      expect(result['user']['profile'].containsKey('removeThis'), isFalse);
      expect(result['status'], equals('active'));
      expect(result.containsKey('deleteThis'), isFalse);
    });

    test('should drop JitDelete values in arrays when dropDeletes is true', () {
      final input = {
        'operations': [
          JitFieldValue.increment(1),
          'string_value',
          JitFieldValue.delete(),
          {
            'nested': JitFieldValue.delete(),
            'value': 42,
          },
          [
            JitFieldValue.arrayUnion(['nested_array']),
            JitFieldValue.delete(),
            'another_string',
          ]
        ]
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      final operations = result['operations'] as List;
      expect(operations.length, equals(4)); // One JitDelete removed from top level
      expect(operations[0], isA<FieldValue>()); // increment
      expect(operations[1], equals('string_value'));
      expect(operations[2], isA<Map<String, dynamic>>());
      expect((operations[2] as Map)['value'], equals(42));
      expect((operations[2] as Map).containsKey('nested'), isFalse); // JitDelete dropped
      expect(operations[3], isA<List>());
      final nestedArray = operations[3] as List;
      expect(nestedArray.length, equals(2)); // One JitDelete removed from nested array
      expect(nestedArray[0], isA<FieldValue>()); // arrayUnion
      expect(nestedArray[1], equals('another_string'));
    });

    test('should handle empty results when all values are JitDelete and dropDeletes is true', () {
      final input = {
        'delete1': JitFieldValue.delete(),
        'delete2': JitFieldValue.delete(),
        'nested': {
          'delete3': JitFieldValue.delete(),
          'delete4': JitFieldValue.delete(),
        }
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      expect(result.containsKey('delete1'), isFalse);
      expect(result.containsKey('delete2'), isFalse);
      expect(result['nested'], isA<Map<String, dynamic>>());
      expect((result['nested'] as Map).isEmpty, isTrue);
    });

    test('should handle arrays with only JitDelete values when dropDeletes is true', () {
      final input = {
        'operations': [
          JitFieldValue.delete(),
          JitFieldValue.delete(),
        ],
        'mixed': [
          'keep_this',
          JitFieldValue.delete(),
          'keep_this_too',
        ]
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      expect((result['operations'] as List).isEmpty, isTrue);
      expect((result['mixed'] as List).length, equals(2));
      expect((result['mixed'] as List)[0], equals('keep_this'));
      expect((result['mixed'] as List)[1], equals('keep_this_too'));
    });

    test('should not affect other JitFieldValue types when dropDeletes is true', () {
      final input = {
        'increment': JitFieldValue.increment(5),
        'arrayUnion': JitFieldValue.arrayUnion(['item']),
        'arrayRemove': JitFieldValue.arrayRemove(['item']),
        'delete': JitFieldValue.delete(),
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      expect(result['increment'], isA<FieldValue>());
      expect(result['arrayUnion'], isA<FieldValue>());
      expect(result['arrayRemove'], isA<FieldValue>());
      expect(result.containsKey('delete'), isFalse);
    });

    test('should handle deeply nested JitDelete values when dropDeletes is true', () {
      final input = {
        'level1': {
          'level2': {
            'level3': {
              'level4': {
                'increment': JitFieldValue.increment(10),
                'delete': JitFieldValue.delete(),
                'regular': 'value',
                'level5': {
                  'deepDelete': JitFieldValue.delete(),
                  'keepThis': 'value',
                }
              }
            }
          }
        }
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      final level4 = result['level1']['level2']['level3']['level4'];
      expect(level4['increment'], isA<FieldValue>());
      expect(level4.containsKey('delete'), isFalse);
      expect(level4['regular'], equals('value'));
      expect(level4['level5']['keepThis'], equals('value'));
      expect((level4['level5'] as Map).containsKey('deepDelete'), isFalse);
    });
  });

  group('replaceAllJitFieldValues with dot notation keys', () {
    test('should handle dot notation keys without expanding them', () {
      final input = {
        'a.b.c': JitFieldValue.delete(),
        'a.b.d': JitFieldValue.increment(1),
        'x.y.z': 'regular_value',
        'simple_key': JitFieldValue.arrayUnion(['item']),
      };

      final result = replaceAllJitFieldValues(input);

      expect(result['a.b.c'], isA<FieldValue>());
      expect(result['a.b.d'], isA<FieldValue>());
      expect(result['x.y.z'], equals('regular_value'));
      expect(result['simple_key'], isA<FieldValue>());
      
      // Ensure the structure is flat, not nested
      expect(result.containsKey('a'), isFalse);
      expect(result.length, equals(4));
    });

    test('should drop dot notation JitDelete keys when dropDeletes is true', () {
      final input = {
        'user.profile.name': 'John',
        'user.profile.age': JitFieldValue.increment(1),
        'user.settings.theme': JitFieldValue.delete(),
        'user.settings.notifications': true,
        'metadata.created': JitFieldValue.delete(),
        'metadata.updated': 'timestamp',
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      expect(result['user.profile.name'], equals('John'));
      expect(result['user.profile.age'], isA<FieldValue>());
      expect(result['user.settings.notifications'], isTrue);
      expect(result['metadata.updated'], equals('timestamp'));
      
      // These should be dropped
      expect(result.containsKey('user.settings.theme'), isFalse);
      expect(result.containsKey('metadata.created'), isFalse);
      
      expect(result.length, equals(4));
    });

    test('should handle mixed dot notation and regular keys', () {
      final input = {
        'user': {
          'name': 'John',
          'settings.theme': JitFieldValue.delete(),
        },
        'profile.data.age': JitFieldValue.increment(1),
        'tags': JitFieldValue.arrayUnion(['tag1']),
        'cache.invalidate': JitFieldValue.delete(),
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      expect(result['user'], isA<Map<String, dynamic>>());
      expect(result['user']['name'], equals('John'));
      expect((result['user'] as Map).containsKey('settings.theme'), isFalse);
      expect(result['profile.data.age'], isA<FieldValue>());
      expect(result['tags'], isA<FieldValue>());
      expect(result.containsKey('cache.invalidate'), isFalse);
    });

    test('should handle dot notation keys in arrays', () {
      final input = {
        'operations': [
          {
            'field.path.name': JitFieldValue.delete(),
            'field.path.value': 42,
          },
          {
            'another.field': JitFieldValue.increment(1),
            'regular_field': 'value',
          }
        ]
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      final operations = result['operations'] as List;
      expect(operations.length, equals(2));
      
      final firstOp = operations[0] as Map;
      expect(firstOp.containsKey('field.path.name'), isFalse);
      expect(firstOp['field.path.value'], equals(42));
      
      final secondOp = operations[1] as Map;
      expect(secondOp['another.field'], isA<FieldValue>());
      expect(secondOp['regular_field'], equals('value'));
    });

    test('should handle complex dot notation scenarios', () {
      final input = {
        // Firestore-style updates
        'user.profile.personal.name': 'John Doe',
        'user.profile.personal.age': JitFieldValue.increment(1),
        'user.profile.settings.theme': 'dark',
        'user.profile.settings.language': JitFieldValue.delete(),
        'user.permissions.read': true,
        'user.permissions.write': JitFieldValue.delete(),
        
        // Mixed with regular nested structure
        'metadata': {
          'created.at': 'timestamp',
          'cache.data': JitFieldValue.delete(),
          'version': 1,
        },
        
        // Array with dot notation
        'updates': [
          'user.last.login',
          JitFieldValue.delete(),
          {
            'field.name': 'test.field',
            'operation': JitFieldValue.arrayUnion(['value']),
          }
        ]
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      // Check dot notation keys are preserved and processed correctly
      expect(result['user.profile.personal.name'], equals('John Doe'));
      expect(result['user.profile.personal.age'], isA<FieldValue>());
      expect(result['user.profile.settings.theme'], equals('dark'));
      expect(result['user.permissions.read'], isTrue);
      
      // Deleted keys should be gone
      expect(result.containsKey('user.profile.settings.language'), isFalse);
      expect(result.containsKey('user.permissions.write'), isFalse);
      
      // Check nested structure
      expect(result['metadata'], isA<Map<String, dynamic>>());
      expect(result['metadata']['created.at'], equals('timestamp'));
      expect(result['metadata']['version'], equals(1));
      expect((result['metadata'] as Map).containsKey('cache.data'), isFalse);
      
      // Check array
      final updates = result['updates'] as List;
      expect(updates.length, equals(2)); // One JitDelete removed
      expect(updates[0], equals('user.last.login'));
      expect(updates[1], isA<Map<String, dynamic>>());
      expect((updates[1] as Map)['field.name'], equals('test.field'));
      expect((updates[1] as Map)['operation'], isA<FieldValue>());
    });

    test('should handle edge cases with dot notation', () {
      final input = {
        '': JitFieldValue.delete(), // Empty key
        '.': JitFieldValue.increment(1), // Just a dot
        '..': JitFieldValue.delete(), // Multiple dots
        'a.': JitFieldValue.arrayUnion(['item']), // Trailing dot
        '.b': 'value', // Leading dot
        'a.b.': JitFieldValue.delete(), // Trailing dot with path
        'normal_key': 'normal_value',
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      expect(result['.'], isA<FieldValue>());
      expect(result['a.'], isA<FieldValue>());
      expect(result['.b'], equals('value'));
      expect(result['normal_key'], equals('normal_value'));
      
      // These should be dropped
      expect(result.containsKey(''), isFalse);
      expect(result.containsKey('..'), isFalse);
      expect(result.containsKey('a.b.'), isFalse);
    });
  });

  group('replaceAllJitFieldValues with partial dot notation', () {
    test('should handle dot notation keys pointing to nested objects', () {
      final input = {
        'user.profile': {
          'name': 'John',
          'age': JitFieldValue.increment(1),
          'settings': {
            'theme': 'dark',
            'notifications': JitFieldValue.delete(),
          }
        },
        'metadata.cache': {
          'lastUpdated': 'timestamp',
          'invalidate': JitFieldValue.delete(),
        },
        'simple_key': 'simple_value',
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      // Check dot notation key with nested object
      expect(result['user.profile'], isA<Map<String, dynamic>>());
      expect(result['user.profile']['name'], equals('John'));
      expect(result['user.profile']['age'], isA<FieldValue>());
      expect(result['user.profile']['settings'], isA<Map<String, dynamic>>());
      expect(result['user.profile']['settings']['theme'], equals('dark'));
      expect((result['user.profile']['settings'] as Map).containsKey('notifications'), isFalse);

      // Check another dot notation key with nested object
      expect(result['metadata.cache'], isA<Map<String, dynamic>>());
      expect(result['metadata.cache']['lastUpdated'], equals('timestamp'));
      expect((result['metadata.cache'] as Map).containsKey('invalidate'), isFalse);

      // Check simple key
      expect(result['simple_key'], equals('simple_value'));
    });

    test('should handle mixed full and partial dot notation', () {
      final input = {
        // Full dot notation (no nesting)
        'user.profile.name': 'John',
        'user.profile.age': JitFieldValue.increment(1),
        'user.settings.theme': JitFieldValue.delete(),
        
        // Partial dot notation (dot notation key with nested object)
        'user.permissions': {
          'read': true,
          'write': JitFieldValue.delete(),
          'admin': {
            'users': false,
            'system': JitFieldValue.delete(),
          }
        },
        
        // Regular nested structure
        'metadata': {
          'created': 'timestamp',
          'cache.enabled': JitFieldValue.delete(), // dot notation within regular nesting
          'version': 1,
        }
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      // Check full dot notation
      expect(result['user.profile.name'], equals('John'));
      expect(result['user.profile.age'], isA<FieldValue>());
      expect(result.containsKey('user.settings.theme'), isFalse);

      // Check partial dot notation
      expect(result['user.permissions'], isA<Map<String, dynamic>>());
      expect(result['user.permissions']['read'], isTrue);
      expect((result['user.permissions'] as Map).containsKey('write'), isFalse);
      expect(result['user.permissions']['admin'], isA<Map<String, dynamic>>());
      expect(result['user.permissions']['admin']['users'], isFalse);
      expect((result['user.permissions']['admin'] as Map).containsKey('system'), isFalse);

      // Check regular nested with dot notation inside
      expect(result['metadata'], isA<Map<String, dynamic>>());
      expect(result['metadata']['created'], equals('timestamp'));
      expect(result['metadata']['version'], equals(1));
      expect((result['metadata'] as Map).containsKey('cache.enabled'), isFalse);
    });

    test('should handle deeply nested partial dot notation', () {
      final input = {
        'app.config.database': {
          'host': 'localhost',
          'port': 5432,
          'credentials': {
            'username': 'user',
            'password': JitFieldValue.delete(),
            'options': {
              'ssl': true,
              'timeout': JitFieldValue.increment(30),
              'deprecated_setting': JitFieldValue.delete(),
            }
          },
          'pool_size': JitFieldValue.increment(10),
        },
        'app.features.enabled': {
          'auth': true,
          'analytics': JitFieldValue.delete(),
          'cache': {
            'redis': true,
            'memory': false,
            'cleanup_job': JitFieldValue.delete(),
          }
        }
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      // Check first partial dot notation
      final dbConfig = result['app.config.database'] as Map<String, dynamic>;
      expect(dbConfig['host'], equals('localhost'));
      expect(dbConfig['port'], equals(5432));
      expect(dbConfig['pool_size'], isA<FieldValue>());
      
      final credentials = dbConfig['credentials'] as Map<String, dynamic>;
      expect(credentials['username'], equals('user'));
      expect(credentials.containsKey('password'), isFalse);
      
      final options = credentials['options'] as Map<String, dynamic>;
      expect(options['ssl'], isTrue);
      expect(options['timeout'], isA<FieldValue>());
      expect(options.containsKey('deprecated_setting'), isFalse);

      // Check second partial dot notation
      final features = result['app.features.enabled'] as Map<String, dynamic>;
      expect(features['auth'], isTrue);
      expect(features.containsKey('analytics'), isFalse);
      
      final cache = features['cache'] as Map<String, dynamic>;
      expect(cache['redis'], isTrue);
      expect(cache['memory'], isFalse);
      expect(cache.containsKey('cleanup_job'), isFalse);
    });

    test('should handle arrays within partial dot notation', () {
      final input = {
        'user.preferences': {
          'themes': ['dark', 'light'],
          'notifications': [
            {
              'type': 'email',
              'enabled': true,
              'frequency': JitFieldValue.delete(),
            },
            {
              'type': 'push',
              'enabled': JitFieldValue.delete(),
              'sound': true,
            },
            JitFieldValue.delete(),
          ],
          'languages': JitFieldValue.arrayUnion(['es', 'fr']),
        },
        'app.modules': [
          {
            'name': 'auth',
            'config.timeout': JitFieldValue.increment(30),
            'deprecated': JitFieldValue.delete(),
          },
          'billing',
          JitFieldValue.delete(),
        ]
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      // Check partial dot notation with arrays
      final preferences = result['user.preferences'] as Map<String, dynamic>;
      expect(preferences['themes'], equals(['dark', 'light']));
      expect(preferences['languages'], isA<FieldValue>());
      
      final notifications = preferences['notifications'] as List;
      expect(notifications.length, equals(2)); // One JitDelete removed
      expect((notifications[0] as Map)['type'], equals('email'));
      expect((notifications[0] as Map)['enabled'], isTrue);
      expect((notifications[0] as Map).containsKey('frequency'), isFalse);
      expect((notifications[1] as Map)['type'], equals('push'));
      expect((notifications[1] as Map)['sound'], isTrue);
      expect((notifications[1] as Map).containsKey('enabled'), isFalse);

      // Check array at top level with partial dot notation inside
      final modules = result['app.modules'] as List;
      expect(modules.length, equals(2)); // One JitDelete removed
      expect((modules[0] as Map)['name'], equals('auth'));
      expect((modules[0] as Map)['config.timeout'], isA<FieldValue>());
      expect((modules[0] as Map).containsKey('deprecated'), isFalse);
      expect(modules[1], equals('billing'));
    });

    test('should handle edge cases with partial dot notation', () {
      final input = {
        // Empty object with dot notation key
        'empty.path': {},
        
        // Dot notation key with object containing only JitDelete values
        'delete.only': {
          'field1': JitFieldValue.delete(),
          'field2': JitFieldValue.delete(),
        },
        
        // Nested dot notation keys
        'outer.path': {
          'inner.path': {
            'value': 42,
            'delete_me': JitFieldValue.delete(),
          },
          'another.inner': JitFieldValue.increment(1),
        },
        
        // Complex mixed scenario
        'config.app.settings': {
          'theme.dark': true,
          'cache': {
            'enabled': true,
            'ttl.seconds': JitFieldValue.increment(300),
            'cleanup': JitFieldValue.delete(),
          },
          'features.experimental': JitFieldValue.delete(),
        }
      };

      final result = replaceAllJitFieldValues(input, dropDeletes: true);

      // Check empty object is preserved
      expect(result['empty.path'], isA<Map>());
      expect((result['empty.path'] as Map).isEmpty, isTrue);

      // Check object with only deletes becomes empty
      expect(result['delete.only'], isA<Map>());
      expect((result['delete.only'] as Map).isEmpty, isTrue);

      // Check nested dot notation
      final outer = result['outer.path'] as Map<String, dynamic>;
      expect(outer['inner.path'], isA<Map<String, dynamic>>());
      expect((outer['inner.path'] as Map)['value'], equals(42));
      expect((outer['inner.path'] as Map).containsKey('delete_me'), isFalse);
      expect(outer['another.inner'], isA<FieldValue>());

      // Check complex mixed scenario
      final config = result['config.app.settings'] as Map<String, dynamic>;
      expect(config['theme.dark'], isTrue);
      expect(config.containsKey('features.experimental'), isFalse);
      expect(config['cache'], isA<Map<String, dynamic>>());
      expect((config['cache'] as Map)['enabled'], isTrue);
      expect((config['cache'] as Map)['ttl.seconds'], isA<FieldValue>());
      expect((config['cache'] as Map).containsKey('cleanup'), isFalse);
    });

    test('should maintain consistency between full and partial dot notation', () {
      // This test ensures that using full dot notation vs partial dot notation
      // produces equivalent results for the same logical structure
      
      final fullDotNotation = {
        'user.profile.name': 'John',
        'user.profile.age': JitFieldValue.increment(1),
        'user.profile.settings.theme': 'dark',
        'user.profile.settings.notifications': JitFieldValue.delete(),
      };

      final partialDotNotation = {
        'user.profile': {
          'name': 'John',
          'age': JitFieldValue.increment(1),
          'settings': {
            'theme': 'dark',
            'notifications': JitFieldValue.delete(),
          }
        }
      };

      final result1 = replaceAllJitFieldValues(fullDotNotation, dropDeletes: true);
      final result2 = replaceAllJitFieldValues(partialDotNotation, dropDeletes: true);

      // Full dot notation result
      expect(result1['user.profile.name'], equals('John'));
      expect(result1['user.profile.age'], isA<FieldValue>());
      expect(result1['user.profile.settings.theme'], equals('dark'));
      expect(result1.containsKey('user.profile.settings.notifications'), isFalse);

      // Partial dot notation result
      expect(result2['user.profile'], isA<Map<String, dynamic>>());
      expect(result2['user.profile']['name'], equals('John'));
      expect(result2['user.profile']['age'], isA<FieldValue>());
      expect(result2['user.profile']['settings']['theme'], equals('dark'));
      expect((result2['user.profile']['settings'] as Map).containsKey('notifications'), isFalse);

      // Both should have the same number of top-level keys for their respective structures
      expect(result1.length, equals(3));
      expect(result2.length, equals(1));
    });
  });
}