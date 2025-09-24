import 'package:flutter_test/flutter_test.dart';
import 'package:firestore_optimize/src/database/optimizer/map_util.dart';
import 'package:firestore_optimize/src/database/dot_util.dart';
import 'package:firestore_optimize/src/database/jit_field_value.dart';

void main() {
  group('all', () {
    test('should handle various non-map value types overwriting dotted keys', () {
      final p = {
        "config.db.host": "localhost",
        "config.db.port": 5432,
        "config.cache.enabled": true,
        "config.cache.ttl": 3600,
      };
      final n = {
        "config.db": false, // Boolean
        "config.cache": null, // Null
      };

      final result = mergeMaps(p, n);

      expect(result, {
        "config.db": false, // Boolean overwrites dotted keys
        "config.cache": null, // Null overwrites dotted keys
      });
    });
    test('should handle array values overwriting dotted keys', () {
      final p = {"tags.system.auto": true, "tags.system.manual": false, "tags.user.custom": "value"};
      final n = {
        "tags.system": ["tag1", "tag2"], // Array
      };

      final result = mergeMaps(p, n);

      expect(result, {
        "tags.system": ["tag1", "tag2"], // Array overwrites dotted keys
        "tags.user.custom": "value", // Unrelated dotted key preserved
      });
    });
    test('overwrite submap value using dots', () {
      final p = {
        "g.a.b": {"c": 1},
      };
      final n = {"g.a": 10};

      final result = mergeMaps(p, n);

      expect(result, {"g.a": 10});
    });

    test('overwrite dots with non-merge maps', () {
      final p = {"a.b": 1, "a.c": 2, "b": "stub", "m.n.p": "should_remove", "m.n.o.a": 3, "m.n.o.b": 4, "z.x.y": 9};
      final n = {
        "a": {"b": 99},
        "c": 123,
        "m": {
          "n": {"o": "replace"},
        },
      };

      final result = mergeMaps(p, n);

      expect(result, {
        "a": {"b": 99},
        "b": "stub",
        "c": 123,
        "m": {
          "n": {"o": "replace"},
        },
        "z.x.y": 9,
      });
    });
    test('overwrite dot', () {
      final p = {'a.b': 1, 'a.c': 2, 'b': 'stub'};
      final n = {'a.b': 99, 'a.d.e': 12, 'c': 123};

      final result = mergeMaps(p, n);

      expect(result, {'a.b': 99, 'a.c': 2, 'b': 'stub', 'a.d.e': 12, 'c': 123});
    });

    group('basic merging', () {
      test('should merge simple maps without conflicts', () {
        final p = {'a': 1, 'b': 2};
        final n = DotMap({'c': 3, 'd': 4});

        final result = mergeMaps(p, n);

        expect(result, {'a': 1, 'b': 2, 'c': 3, 'd': 4});
      });

      test('should handle empty original map', () {
        final p = <String, dynamic>{};
        final n = DotMap({'a': 1, 'b': 2});

        final result = mergeMaps(p, n);

        expect(result, {'a': 1, 'b': 2});
      });

      test('should handle empty incoming map', () {
        final p = {'a': 1, 'b': 2};
        final n = DotMap(<String, dynamic>{});

        final result = mergeMaps(p, n);

        expect(result, {'a': 1, 'b': 2});
      });

      test('should handle both maps empty', () {
        final p = <String, dynamic>{};
        final n = DotMap(<String, dynamic>{});

        final result = mergeMaps(p, n);

        expect(result, <String, dynamic>{});
      });

      test('should override values when keys match', () {
        final p = {'a': 1, 'b': 2};
        final n = DotMap({'a': 10, 'c': 3});

        final result = mergeMaps(p, n);

        expect(result, {'a': 10, 'b': 2, 'c': 3});
      });
    });

    group('nested map handling', () {
      test('should merge nested maps', () {
        final p = {
          'user': {'name': 'John', 'age': 30},
          'settings': {'theme': 'light'},
        };
        final n = DotMap({'user.email': 'john@example.com', 'settings.notifications': true});

        final result = mergeMaps(p, n);

        expect(result, {
          'user': {'name': 'John', 'age': 30, 'email': 'john@example.com'},
          'settings': {'theme': 'light', 'notifications': true},
        });
      });

      test('should handle deep nested structures', () {
        final p = {
          'level1': {
            'level2': {
              'level3': {'value': 'original'},
            },
          },
        };
        final n = DotMap({'level1.level2.level3.newValue': 'added', 'level1.level2.newKey': 'another'});

        final result = mergeMaps(p, n);

        expect(result, {
          'level1': {
            'level2': {
              'level3': {'value': 'original', 'newValue': 'added'},
              'newKey': 'another',
            },
          },
        });
      });

      test('should override entire map when incoming overwrites path', () {
        final p = {
          'user': {'name': 'John', 'age': 30},
        };
        final n = DotMap({
          'user': {'email': 'john@example.com'},
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'user': {'email': 'john@example.com'},
        });
      });

      test('should override entire map when incoming overwrites with non-map', () {
        final p = {
          'user': {'name': 'John', 'age': 30},
        };
        final n = DotMap({'user': 'someid'});

        final result = mergeMaps(p, n);

        expect(result, {'user': "someid"});
      });

      test('should not include original values when incoming overwrites with deeper path', () {
        final p = {'config': 'simple_value'};
        final n = DotMap({'config.nested': 'new_value'});

        final result = mergeMaps(p, n);

        expect(result, {
          'config': {'nested': 'new_value'},
        });
      });
    });

    group('array handling', () {
      test('should preserve arrays when no conflicts', () {
        final p = {
          'tags': ['flutter', 'dart'],
          'scores': [85, 90, 95],
        };
        final n = DotMap({'name': 'John'});

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['flutter', 'dart'],
          'scores': [85, 90, 95],
          'name': 'John',
        });
      });

      test('should handle JitArrayUnion operations', () {
        final p = {
          'tags': ['flutter', 'dart'],
        };
        final n = DotMap({
          'tags': JitFieldValue.arrayUnion(['mobile', 'app']),
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['flutter', 'dart', 'mobile', 'app'],
        });
      });

      test('should handle JitArrayRemove operations', () {
        final p = {
          'tags': ['flutter', 'dart', 'mobile', 'web'],
        };
        final n = DotMap({
          'tags': JitFieldValue.arrayRemove(['mobile', 'web']),
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['flutter', 'dart'],
        });
      });

      test('should handle empty array with JitArrayUnion', () {
        final p = {'tags': <String>[]};
        final n = DotMap({
          'tags': JitFieldValue.arrayUnion(['flutter', 'dart']),
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['flutter', 'dart'],
        });
      });

      test('should replace with JitArrayUnion', () {
        final p = {'tags': 'tag1, tag2'};
        final n = DotMap({
          'tags': JitFieldValue.arrayUnion(['flutter', 'dart']),
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['flutter', 'dart'],
        });
      });

      test('should add JitArrayUnion if key not present', () {
        final p = {'another': 'stub'};
        final n = DotMap({
          'tags': JitFieldValue.arrayUnion(['flutter', 'dart']),
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'another': 'stub',
          'tags': JitFieldValue.arrayUnion(['flutter', 'dart']),
        });
      });

      test('should add JitArrayRemove if key not present', () {
        final p = {'another': 'stub'};
        final n = DotMap({
          'tags': JitFieldValue.arrayRemove(['flutter', 'dart']),
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'another': 'stub',
          'tags': JitFieldValue.arrayRemove(['flutter', 'dart']),
        });
      });

      test('should replace JitArrayUnion with array', () {
        final p = {
          'tags': JitFieldValue.arrayUnion(['flutter', 'dart']),
        };
        final n = DotMap({
          'tags': ['stub', 'another'],
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['stub', 'another'],
        });
      });

      test('should replace JitArrayRemove with array', () {
        final p = {
          'tags': JitFieldValue.arrayRemove(['flutter', 'dart']),
        };
        final n = DotMap({
          'tags': ['stub', 'another'],
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['stub', 'another'],
        });
      });

      test('should handle non-empty array with JitArrayUnion', () {
        final p = {
          'tags': ['existing'],
        };
        final n = DotMap({
          'tags': JitFieldValue.arrayUnion(['flutter', 'dart']),
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['existing', 'flutter', 'dart'],
        });
      });

      test('should handle array replacement', () {
        final p = {
          'tags': ['old', 'tags'],
        };
        final n = DotMap({
          'tags': ['new', 'tags'],
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'tags': ['new', 'tags'],
        });
      });

      test('should combine JitArrayRemove operations', () {
        final p = {
          'tags': JitFieldValue.arrayRemove(['a', 'b']),
        };
        final n = DotMap({
          'tags': JitFieldValue.arrayRemove(['c', 'd']),
        });

        final result = mergeMaps(p, n);

        expect(result['tags'], isA<JitArrayRemove>());
        final jitRemove = result['tags'] as JitArrayRemove;
        expect(jitRemove.elements, containsAll(['a', 'b', 'c', 'd']));
      });

      test('should combine JitArrayUnion operations', () {
        final p = {
          'tags': JitFieldValue.arrayUnion(['a', 'b']),
        };
        final n = DotMap({
          'tags': JitFieldValue.arrayUnion(['c', 'd']),
        });

        final result = mergeMaps(p, n);

        expect(result['tags'], isA<JitArrayUnion>());
        final jitUnion = result['tags'] as JitArrayUnion;
        expect(jitUnion.elements, ['a', 'b', 'c', 'd']);
      });

      test('should not include array when incoming overwrites with deeper path', () {
        final p = {
          'config': ['item1', 'item2'],
        };
        final n = DotMap({'config.nested': 'value'});

        final result = mergeMaps(p, n);

        expect(result, {
          'config': {'nested': 'value'},
        });
      });
    });

    group('JitDelete operations', () {
      test('should persist JitDelete ', () {
        final p = {'a': JitFieldValue.delete(), 'b': 2};
        final n = DotMap({'a': JitFieldValue.delete()});

        final result = mergeMaps(p, n);

        expect(result['b'], 2);
        expect(result['a'], isA<JitDelete>());
      });

      test('should overwrite JitDelete ', () {
        final p = {'a': JitFieldValue.delete(), 'b': 2};
        final n = DotMap({'a': 'stub'});

        final result = mergeMaps(p, n);

        expect(result['b'], 2);
        expect(result['a'], 'stub');
      });

      test('should handle JitDelete on simple values', () {
        final p = {'a': 1, 'b': 2};
        final n = DotMap({'a': JitFieldValue.delete()});

        final result = mergeMaps(p, n);

        expect(result['b'], 2);
        expect(result['a'], isA<JitDelete>());
      });

      test('should handle JitDelete on arrays', () {
        final p = {
          'tags': ['flutter', 'dart'],
          'scores': [85, 90],
        };
        final n = DotMap({'tags': JitFieldValue.delete()});

        final result = mergeMaps(p, n);

        expect(result['scores'], [85, 90]);
        expect(result['tags'], isA<JitDelete>());
      });

      test('should handle JitDelete on nested values', () {
        final p = {
          'user': {'name': 'John', 'email': 'john@example.com'},
        };
        final n = DotMap({'user.email': JitFieldValue.delete()});

        final result = mergeMaps(p, n);

        expect(result['user']['name'], 'John');
        expect(result['user']['email'], isA<JitDelete>());
      });
    });

    group('JitIncrement operations', () {
      test('should handle JitIncrement on simple values', () {
        final p = {'score': 100, 'level': 5};
        final n = DotMap({'score': JitFieldValue.increment(25)});

        final result = mergeMaps(p, n);

        expect(result['score'], 125);
        expect(result['level'], 5);
      });

      test('should combine JitIncrement operations', () {
        final p = {'score': JitFieldValue.increment(10)};
        final n = DotMap({'score': JitFieldValue.increment(25)});

        final result = mergeMaps(p, n);

        expect(result['score'], isA<JitIncrement>());
        final jitIncrement = result['score'] as JitIncrement;
        expect(jitIncrement.value, 35);
      });

      test('should handle JitIncrement with negative values', () {
        final p = {'score': JitFieldValue.increment(20)};
        final n = DotMap({'score': JitFieldValue.increment(-5)});

        final result = mergeMaps(p, n);

        expect(result['score'], isA<JitIncrement>());
        final jitIncrement = result['score'] as JitIncrement;
        expect(jitIncrement.value, 15);
      });

      test('should handle JitIncrement with double values', () {
        final p = {'score': JitFieldValue.increment(10.5)};
        final n = DotMap({'score': JitFieldValue.increment(4.3)});

        final result = mergeMaps(p, n);

        expect(result['score'], isA<JitIncrement>());
        final jitIncrement = result['score'] as JitIncrement;
        expect(jitIncrement.value, closeTo(14.8, 0.001));
      });
    });

    group('complex scenarios', () {
      test('should handle mixed JIT operations', () {
        final p = {
          'score': 100,
          'tags': ['flutter'],
          'metadata': {
            'version': 1,
            'flags': ['debug'],
          },
        };
        final n = DotMap({
          'score': JitFieldValue.increment(50),
          'tags': JitFieldValue.arrayUnion(['dart', 'mobile']),
          'metadata.version': JitFieldValue.increment(1),
          'metadata.flags': JitFieldValue.arrayRemove(['debug']),
          'metadata.created': 'today',
        });

        final result = mergeMaps(p, n);

        expect(result['score'], 150);

        expect(result['tags'], ['flutter', 'dart', 'mobile']);

        expect(result['metadata']['version'], 2);

        expect(result['metadata']['flags'], <String>[]);
        expect(result['metadata']['created'], 'today');
      });

      test('should handle complete override scenarios', () {
        final p = {
          'config': {
            'database': {'host': 'localhost', 'port': 5432, 'ssl': true},
            'cache': {'enabled': true, 'ttl': 3600},
          },
        };
        final n = DotMap({
          'config.database': {'url': 'postgresql://new-host:5433/db'},
          'config.cache.size': 1000,
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'config': {
            'database': {'url': 'postgresql://new-host:5433/db'},
            'cache': {'enabled': true, 'ttl': 3600, 'size': 1000},
          },
        });
      });

      test('should handle deep path overwrites', () {
        final p = {
          'a': {
            'b': {'c': 'original', 'd': 'preserved'},
            'e': 'also_preserved',
          },
        };
        final n = DotMap({'a.b.c.nested': 'new_structure'});

        final result = mergeMaps(p, n);

        expect(result, {
          'a': {
            'b': {
              'c': {'nested': 'new_structure'},
              'd': 'preserved',
            },
            'e': 'also_preserved',
          },
        });
      });

      test('should handle real-world document update scenario', () {
        final p = {
          'id': 'doc123',
          'title': 'Original Title',
          'content': {
            'text': 'Original content',
            'metadata': {
              'wordCount': 150,
              'tags': ['draft'],
            },
          },
          'timestamps': {'created': '2023-01-01', 'updated': '2023-01-15'},
          'collaborators': ['user1', 'user2'],
        };
        final n = DotMap({
          'title': 'Updated Title',
          'content.text': 'Updated content with more words',
          'content.metadata.wordCount': JitFieldValue.increment(25),
          'content.metadata.tags': JitFieldValue.arrayUnion(['reviewed']),
          'timestamps.updated': '2023-02-01',
          'collaborators': JitFieldValue.arrayUnion(['user3']),
        });

        final result = mergeMaps(p, n);

        expect(result['id'], 'doc123');
        expect(result['title'], 'Updated Title');
        expect(result['content']['text'], 'Updated content with more words');
        expect(result['content']['metadata']['wordCount'], 175);
        expect(result['content']['metadata']['tags'], ['draft', 'reviewed']);
        expect(result['timestamps']['created'], '2023-01-01');
        expect(result['timestamps']['updated'], '2023-02-01');
        expect(result['collaborators'], ['user1', 'user2', 'user3']);
      });
    });

    group('edge cases and error handling', () {
      test('should throw ArgumentError for invalid dot notation keys', () {
        final p = {'a': 1};
        final n = DotMap({'.invalid': 'value'});

        expect(() => mergeMaps(p, n), throwsA(isA<ArgumentError>()));
      });

      test('should throw ArgumentError for keys ending with dot', () {
        final p = {'a': 1};
        final n = DotMap({'invalid.': 'value'});

        expect(() => mergeMaps(p, n), throwsA(isA<ArgumentError>()));
      });

      test('should throw ArgumentError for empty keys', () {
        final p = {'a': 1};
        final n = DotMap({'': 'value'});

        expect(() => mergeMaps(p, n), throwsA(isA<ArgumentError>()));
      });

      test('should handle null values correctly', () {
        final p = {
          'a': null,
          'b': {'c': null},
        };
        final n = DotMap({'a': 'not_null', 'b.d': null});

        final result = mergeMaps(p, n);

        expect(result, {
          'a': 'not_null',
          'b': {'c': null, 'd': null},
        });
      });

      test('should handle special characters in keys', () {
        final p = {'key-with-dash': 'value1', 'key_with_underscore': 'value2'};
        final n = DotMap({'key@special': 'value3', 'nested.key-with-dash': 'nested_value'});

        final result = mergeMaps(p, n);

        expect(result, {
          'key-with-dash': 'value1',
          'key_with_underscore': 'value2',
          'key@special': 'value3',
          'nested.key-with-dash': 'nested_value',
        });
      });

      test('should handle numeric values in arrays with JIT operations', () {
        final p = {
          'numbers': [1, 2, 3],
          'mixed': ['string', 42, true],
        };
        final n = DotMap({
          'numbers': JitFieldValue.arrayUnion([4, 5]),
          'mixed': JitFieldValue.arrayRemove([42]),
        });

        final result = mergeMaps(p, n);

        expect(result, {
          'numbers': [1, 2, 3, 4, 5],
          'mixed': ['string', true],
        });
      });

      test('should handle very deep nesting', () {
        final p = {
          'level1': {
            'level2': {
              'level3': {
                'level4': {'level5': 'deep_value'},
              },
            },
          },
        };
        final n = DotMap({'level1.level2.level3.level4.level5.level6': 'deeper_value'});

        final result = mergeMaps(p, n);

        expect(result, {
          'level1': {
            'level2': {
              'level3': {
                'level4': {
                  'level5': {'level6': 'deeper_value'},
                },
              },
            },
          },
        });
      });
    });

    group('performance scenarios', () {
      test('should handle large number of keys efficiently', () {
        final p = <String, dynamic>{};
        final nData = <String, dynamic>{};

        // Create a map with many keys
        for (int i = 0; i < 1000; i++) {
          p['key_$i'] = 'value_$i';
          nData['new_key_$i'] = 'new_value_$i';
        }

        final n = DotMap(nData);

        final result = mergeMaps(p, n);

        expect(result.length, 2000);
        expect(result['key_500'], 'value_500');
        expect(result['new_key_500'], 'new_value_500');
      });

      test('should handle complex nested structure with many updates', () {
        final p = {
          'users': {
            for (int i = 0; i < 100; i++)
              'user_$i': {
                'name': 'User $i',
                'score': i * 10,
                'tags': ['tag_$i'],
              },
          },
        };

        final nData = <String, dynamic>{};
        for (int i = 0; i < 50; i++) {
          nData['users.user_$i.score'] = JitFieldValue.increment(5);
          nData['users.user_$i.tags'] = JitFieldValue.arrayUnion(['updated']);
        }

        final n = DotMap(nData);
        final result = mergeMaps(p, n);

        expect(result['users']['user_25']['score'], 255);
        expect(result['users']['user_25']['tags'], ['tag_25', 'updated']);
        expect(result['users']['user_75']['score'], 750); // Unchanged
        expect(result['users']['user_75']['tags'], ['tag_75']); // Unchanged
      });
    });

    group('persist dots', () {
      test('overwrite submap', () {
        final p = {
          'a.b.c': 99,
          'm1': {
            'x': 'keep',
            'm2': {'a': '1', 'b': '2'},
          },
        };
        final n = {
          'm1.m2': {'something': 'new'},
        };

        final result = mergeMaps(p, n);

        expect(result, {
          'a.b.c': 99,
          'm1': {
            'x': 'keep',
            'm2': {'something': 'new'},
          },
        });
      });

      test('persist non-overwritten dots from previous and next', () {
        final p = {
          'a.b.c': 99,
          'm1': {
            'm2': {'a': '1', 'b': '2'},
          },
        };
        final n = {
          'm1.m2.c': '3',
          'f.a': {'g': 4},
          'z.x': 1,
          'z.y.a': 2,
          'z.y.b': 3,
        };

        final result = mergeMaps(p, n);

        expect(result, {
          'a.b.c': 99,
          'm1': {
            'm2': {'a': '1', 'b': '2', 'c': '3'},
          },
          'f.a': {'g': 4},
          'z.x': 1,
          'z.y.a': 2,
          'z.y.b': 3,
        });
      });

      test('overwrite previous dots', () {
        final p = {'a.b.c': 99};
        final n = {'a': '3'};

        final result = mergeMaps(p, n);

        expect(result, {'a': '3'});
      });

      test('overwrite leave untouched dots in same format', () {
        final p = {
          'x.y': {'z': 3},
        };
        final n = {'a': '3'};

        final result = mergeMaps(p, n);

        expect(result, {
          'a': '3',
          'x.y': {'z': 3},
        });
      });

      test('partial 1', () {
        final p = {
          'a.b': {
            'c': 1, // Persisted
          },
        };
        final n = {
          'a.b.d': 2, // Added
        };

        final result = mergeMaps(p, n);

        expect(result, {
          'a.b': {
            'c': 1, // Persisted
            'd': 2,
          },
        });
      });

      test('partial 2', () {
        final p = {
          'a.b': [1],
        };
        final n = {
          'a.b.d': 2, // Added
        };

        final result = mergeMaps(p, n);

        expect(result, {
          'a.b': {'d': 2},
        });
      });

      test('partial 3', () {
        final p = {
          'a.b': {'c': 1},
        };
        final n = {
          'a.b.d': 2, // Added
        };

        final result = mergeMaps(p, n);

        expect(result, {
          'a.b': {'c': 1, 'd': 2},
        });
      });

      test('complex', () {
        final p = {
          'a': 1, // Reassigned value
          'b': {
            'c': 2,
            'd': 3, // Reassigned value
          },
          'e': {
            // Replaced with map
            'f': 4,
          },
          'g.h': 5, // Persisted
          'i.j': {
            // Persisted
            'k': 6,
          },
          'l.m.n': 7, // Persisted
          'o.p': 8, // Replaced
        };
        final n = {
          'a': 5,
          'b.d': 10,
          'e': {'z': 15},
          'o': 20,
          'q.r': 25, // Remain dot,
          's.t': {'u': 30}, // Added
          'v': {
            'x': 35, // Added
          },
        };

        final result = mergeMaps(p, n);

        expect(result, {
          'a': 5, // Reassigned value
          'b': {
            'c': 2,
            'd': 10, // Reassigned value
          },
          'e': {
            'z': 15, // Replaced
          },
          'g.h': 5,
          'i.j': {'k': 6},
          'l.m.n': 7,
          'o': 20, // Replaced,
          'q.r': 25, // Remain dot,
          's.t': {'u': 30}, // Added
          'v': {
            'x': 35, // Added
          },
        });
      });
    });
  });
}
