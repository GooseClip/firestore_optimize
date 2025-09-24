
extension type DotKey(String key) implements String {
  factory DotKey.nonDot(String k) {
    if (k.contains(".")) {
      throw ArgumentError("Cannot provide a dot key when using nonDot factory");
    }
    return DotKey(k);
  }

  Iterable<String> get parts => split('.');
}

extension type DotMap(Map<String, dynamic> data) implements Map<String, dynamic> {
  Iterable<DotKey> get dotKeys => [...keys.map((e) => DotKey(e))];
}

extension type DotMapEntry(MapEntry<String, dynamic> entry) implements MapEntry<String, dynamic> {
  DotKey get key => DotKey(entry.key);
  dynamic get value => entry.value;
}

extension XIterableDotMapEntry on Iterable<DotMapEntry> {
  DotMap get dotMap => DotMap(Map.fromEntries(this));
}

class DotNotation {
  DotNotation(this.fieldPath, this.value, {this.wasDot = false});
  final String fieldPath;
  final dynamic value;
  final bool wasDot;

  @override
  String toString() {
    return 'DotNotation{fieldPath: $fieldPath, value: $value}';
  }
}

/// Converts a nested Map to dot notation representation.
List<DotNotation> toDotNotation(Map<String, dynamic> d) {
  if (d.isEmpty) return [];

  List<DotNotation> dots = [];
  final data = {...d};

  // Recursive comparison function
  void traverse(dynamic obj1, String path) {
    if (obj1 is Map) {
      // If the map is empty, treat it as a leaf value
      if (obj1.isEmpty) {
        dots.add(DotNotation(path, obj1));
        return;
      }

      // Compare maps
      Set<String> keys = {...obj1.keys.map((e) => e.toString())};
      for (String key in keys) {
        String currentPath = path.isEmpty ? key : '$path.$key';
        traverse(obj1[key], currentPath);
      }
    } else if (obj1 is List) {
      dots.add(DotNotation(path, obj1));
    } else {
      dots.add(DotNotation(path, obj1));
    }
  }

  // Handle already existing dot notations
  for (var k in [...data.keys]) {
    if (k.contains(".")) {
      dots.add(DotNotation(k, data[k], wasDot: true));
      data.remove(k);
    }
  }

  // Start the comparison
  if (data.isNotEmpty) {
    traverse(data, '');
  }

  return dots;
}

Iterable<DotMapEntry> toDotNotationMapEntries(Map<String, dynamic> data) {
  return toDotNotation(data).map((e) => DotMapEntry(MapEntry(e.fieldPath, e.value)));
}

DotMap toDotMap(Map<String, dynamic> data) {
  if (isDot(data)) {
    return DotMap(data);
  }
  return toDotNotationMapEntries(data).dotMap;
}

/// Converts dot notation keys back to nested Map structure.
/// Handles potential conflicts by giving precedence to more specific paths.
Map<String, dynamic> fromDotMap(DotMap data) {
  if (!isDot(data)) {
    return data;
  }

  final result = <String, dynamic>{};

  // Separate dot notation keys from non-dot keys, filtering out invalid keys
  final dotKeys = <DotKey>[];
  final nonDotKeys = <String>[];

  for (DotKey key in data.dotKeys) {
    // Skip empty keys or keys that would create invalid paths
    if (key.isEmpty) continue;

    if (key.contains('.')) {
      // Check for invalid dot notation (consecutive dots, leading/trailing dots)
      final parts = key.split('.');
      if (parts.any((part) => part.isEmpty)) {
        continue; // Skip invalid dot notation
      }
      dotKeys.add(key);
    } else {
      nonDotKeys.add(key);
    }
  }

  // Process non-dot keys first (simple assignment)
  for (var key in nonDotKeys) {
    result[key] = data[key];
  }

  // Sort dot keys by specificity (shorter paths first) to handle conflicts properly
  dotKeys.sort((a, b) => a.split('.').length.compareTo(b.split('.').length));

  for (var key in dotKeys) {
    setNestedValue(result, key, data[key]);
  }

  return result;
}

/// Converts dot notation keys back to nested Map structure.
/// Handles potential conflicts by giving precedence to more specific paths.
Map<String, dynamic> fromDotMapWithPersist(Map<String, DotNotation> data) {
  final result = <String, dynamic>{};

  // Separate dot notation keys from non-dot keys, filtering out invalid keys
  final dotKeys = <DotKey>[];
  final persistedDotKeys = <DotKey>[];
  final nonDotKeys = <String>[];

  for (var key in data.keys) {
    // Skip empty keys or keys that would create invalid paths
    if (key.isEmpty) continue;

    if (key.contains('.')) {
      // Check for invalid dot notation (consecutive dots, leading/trailing dots)
      final parts = key.split('.');
      if (parts.any((part) => part.isEmpty)) {
        continue; // Skip invalid dot notation
      }

      // Persit keys which were already dot keys
      if (data[key]!.wasDot) {
        persistedDotKeys.add(DotKey(key));
        continue;
      }

      dotKeys.add(DotKey(key));
    } else {
      nonDotKeys.add(key);
    }
  }

  // Process non-dot keys
  for (var key in nonDotKeys) {
    result[key] = data[key]!.value;
  }

  // Process persisted dot keys
  for (var key in persistedDotKeys) {
    result[key] = data[key]!.value;
  }

  // Sort dot keys by specificity (shorter paths first) to handle conflicts properly
  dotKeys.sort((a, b) => a.split('.').length.compareTo(b.split('.').length));

  for (var key in dotKeys) {
    setNestedValue(result, key, data[key]!.value);
  }

  return result;
}

/// Helper function to set a value at a nested path within a map
void setNestedValue(Map<String, dynamic> targetMap, DotKey dotKey, dynamic value, {bool overwrite = false}) {
  final parts = dotKey.parts.toList();

  // Navigate to the parent of the target location
  Map<String, dynamic> pointer = targetMap;

  // Only iterate through parts except the last one
  for (var i = 0; i < parts.length - 1; i++) {
    final pathSegment = parts[i];

    // Check if pathSegment exists and is not a Map - this indicates a conflict
    if (pointer.containsKey(pathSegment) && pointer[pathSegment] is! Map<String, dynamic>) {
      if (!overwrite) {
        throw _pathConflict(dotKey.key, pathSegment, pointer[pathSegment]);
      }
      pointer.remove(pathSegment);
    }

    // Create nested map if it doesn't exist, then navigate to it
    pointer[pathSegment] ??= <String, dynamic>{};
    pointer = pointer[pathSegment] as Map<String, dynamic>;
  }

  final String finalKey = parts.last;

  // Check for conflict at the final key as well
  if (pointer.containsKey(finalKey) && pointer[finalKey] is! Map<String, dynamic> && value is Map<String, dynamic>) {
    if (!overwrite) {
      throw _finalKeyConflict(dotKey.key, finalKey, pointer[finalKey], value);
    }
    pointer.remove(finalKey);
  }

  if (pointer.containsKey(finalKey) && pointer[finalKey] is Map<String, dynamic> && value is Map<String, dynamic>) {
    // Merge the maps
    final existingMap = pointer[finalKey] as Map<String, dynamic>;
    final newMap = Map<String, dynamic>.from(existingMap);
    newMap.addAll(value);
    pointer[finalKey] = newMap;
  } else {
    // Set the value (either new key or compatible type)
    pointer[finalKey] = value;
  }
}

ArgumentError _pathConflict(String dotPath, String pathSegment, dynamic existingValue) {
  return ArgumentError('Path conflict detected: Cannot create nested path "$dotPath" because '
      '"$pathSegment" already exists as a non-Map value (${existingValue.runtimeType}). '
      'Conflicting value: $existingValue');
}

ArgumentError _finalKeyConflict(String dotPath, String finalKey, dynamic existingValue, dynamic attemptedValue) {
  return ArgumentError('Path conflict detected: Cannot set Map value for "$dotPath" because '
      '"$finalKey" already exists as a non-Map value (${existingValue.runtimeType}). '
      'Existing value: $existingValue, Attempted value: $attemptedValue');
}

bool isDot(Map<String, dynamic> data) {
  for (var k in data.keys) {
    if (k.contains(".")) return true;
  }

  return false;
}
