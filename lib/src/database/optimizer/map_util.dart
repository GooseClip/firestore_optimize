import '../dot_util.dart';
import '../jit_field_value.dart';

/*
  Merge maps merges two maps in the same way Firestore does. 
  If a map is using dot notation it will act as a merge, otherwise it will overwrite. 
  The goal is to persist merges if provided in previous or next when not interacting with each other. 
*/
Map<String, dynamic> mergeMaps(Map<String, dynamic> p0, Map<String, dynamic> n0) {
  final n1 = toDotMap(n0);

  for (var key in p0.keys) {
    if (key.isEmpty || key.startsWith('.') || key.endsWith('.')) {
      throw ArgumentError('Invalid key: $key - previous');
    }
  }

  for (var key in n0.keys) {
    if (key.isEmpty || key.startsWith('.') || key.endsWith('.')) {
      throw ArgumentError('Invalid key: $key - next');
    }
  }

  var result = <String, dynamic>{};

  final mergedValues = <DotKey, dynamic>{};

  void mergeValues(dynamic obj1, DotKey path) {
    // final hit =;
    final nextValue = n1[path];

    if (obj1 is Map) {
      // Incoming is overwriting this path
      if (n1.containsKey(path)) {
        return;
      }

      if (obj1.isEmpty && path.isNotEmpty) {
        mergedValues[path] = obj1;
        return;
      }

      Set<String> keys = {...obj1.keys.map((e) => e.toString())};
      for (String key in keys) {
        String currentPath = path.isEmpty ? key : '$path.$key';
        mergeValues(obj1[key], DotKey(currentPath));
      }
    } else if (obj1 is List) {
      // If the path is not in the new map, we can just add the array
      if (!n1.containsKey(path)) {
        mergedValues[path] = obj1;
        return;
      }

      final arr = obj1.map((e) => e as dynamic).toList();

      if (nextValue is JitDelete) {
        return;
      }

      if (nextValue is JitArrayRemove) {
        mergedValues[path] = arr.where((e) => !nextValue.elements.contains(e));
        return;
      }

      if (nextValue is JitArrayUnion) {
        mergedValues[path] = [...arr, ...nextValue.elements];
        return;
      }

      mergedValues[path] = nextValue;
    } else {
      // If there is not an exact hit and not an overwrite, add the value
      if (!n1.containsKey(path)) {
        mergedValues[path] = obj1;
        return;
      }

      if (nextValue is JitDelete) {
        return;
      }

      if (nextValue is JitArrayRemove) {
        // Join the removes
        if (obj1 is JitArrayRemove) {
          // Add unique
          mergedValues[path] = JitArrayRemove({...obj1.elements, ...nextValue.elements}.toList());
          return;
        }

        mergedValues[path] = [];
        return;
      }

      if (nextValue is JitArrayUnion) {
        // Join the unions
        if (obj1 is JitArrayUnion) {
          // Add irregardless of uniqueness
          mergedValues[path] = JitArrayUnion([...obj1.elements, ...nextValue.elements]);
          return;
        }

        mergedValues[path] = [...nextValue.elements];
        return;
      }

      if (nextValue is JitIncrement) {
        if (obj1 is JitIncrement) {
          mergedValues[path] = JitIncrement(obj1.value + nextValue.value);
          return;
        }

        if (obj1 is num) {
          mergedValues[path] = obj1 + nextValue.value;
          return;
        }

        // Overwrite
        mergedValues[path] = nextValue.value;
        return;
      }

      // Add the incoming value
      mergedValues[path] = nextValue;
    }
  }

  // Start the merge
  mergeValues(p0, DotKey(''));
  // a.b.c : 1
  // x.y : { z : 1 }

  final notProcessedMergedValues = <DotKey, dynamic>{};
  // Apply the merge values.
  // Note that previous dot paths that next contains key for will be dropped by mergeValues
  for (var kv in mergedValues.entries) {
    if (kv.key.contains(".")) {
      final k = DotKey(kv.key);
      final parts = k.parts;
      var handled = false;

      for (var i = 0; i < parts.length; i++) {
        final p = parts.take(i + 1).join(".");

        // Next is going to overwrite this dot value.
        // e.g. previous a.b.c.d = 5;
        //      next     a.b = [];
        if (n1.keys.contains(p)) {
          notProcessedMergedValues[kv.key] = kv.value;
          // result[p] = kv.value; // Apply
          handled = true;
          break;
        }

        // Previous was a dot map so maintain structure

        if (p0.containsKey(p)) {
          // Handles cases like:
          // x.y.z: 1
          if (i == parts.length - 1) {
            result[k] = kv.value;
            handled = true;
            break;
          }

          // Handles cases like:
          // x.y: {z: 1}
          result[p] ??= <String, dynamic>{};
          setNestedValue(result[p]! as Map<String, dynamic>, DotKey(k.replaceFirst("$p.", "")), kv.value);
          handled = true;
          break;
        }
      }

      if (handled) {
        continue;
      }

      // TODO is this still needed
      // Previous was a dot map so apply directly
      if (p0.containsKey(kv.key.key)) {
        result[kv.key] = kv.value;
        continue;
      }
    }

    // Other apply as a non-dot map
    setNestedValue(result, kv.key, kv.value);
  }

  // Apply next which are dots.
  // 1. If matching an existing map, apply.
  // 2. Otherwise keep as dot path
  final nextDots = n0.entries.where((kv) => kv.key.contains("."));
  for (var kv in nextDots) {
    final k = DotKey(kv.key);
    final parts = k.parts;

    if (mergedValues.containsKey(k) && !notProcessedMergedValues.containsKey(k)) {
      // Already handled
      continue;
    }

    // We overwrote the values type, so this dot change is absolute
    var handled = false;
    for (var i = 0; i < parts.length; i++) {
      final p = parts.take(i + 1).join(".");

      if (result.containsKey(p)) {
        if (i == 0) {
          setNestedValue(result, k, kv.value, overwrite: true);
        } else {
          if (result[p] is! Map) {
            result[p] = <String, dynamic>{};
          }
          setNestedValue(
            result[p] as Map<String, dynamic>,
            DotKey(k.replaceFirst("$p.", "")),
            kv.value,
            overwrite: true,
          );
        }
        handled = true;
        break;
      }
    }

    if (handled) {
      continue;
    }

    result[k.key] = kv.value;
  }

  // Apply non-merged values
  final nextWithoutDots = Map.fromEntries(n0.entries.where((kv) => !kv.key.contains(".")));
  for (var kv in nextWithoutDots.entries) {
    // Overwrite maps
    if (kv.value is Map) {
      result[kv.key] = kv.value;

      for (final rk in [...result.keys]) {
        if (rk.startsWith("${kv.key}.")) {
          // Remove any dots applied that are overwritten
          result.remove(rk);
        }
      }
      continue;
    }

    if (mergedValues.containsKey(kv.key)) {
      // Already handled
      continue;
    }
    result[kv.key] = kv.value;
  }

  return result;
}
