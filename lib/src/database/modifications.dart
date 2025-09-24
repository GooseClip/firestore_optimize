import 'jit_field_value.dart';

class Modification {
  const Modification(this.fieldPath, this.oldValue, this.newValue);

  final String fieldPath;
  final dynamic oldValue;
  final dynamic newValue;

  MapEntry<String, dynamic> get delta => MapEntry(fieldPath, newValue);

  @override
  String toString() {
    return 'Modification{path: $fieldPath, oldValue: $oldValue, newValue: $newValue}';
  }
}

List<Modification> computeModifications(
  Map<String, dynamic> p,
  Map<String, dynamic> n, {
  required bool overwriteLists,
}) {
  // Result list to hold paths of differences
  List<Modification> differences = [];

  // Recursive comparison function
  void compare(dynamic obj1, dynamic obj2, String path) {
    if (obj1 is Map<String, dynamic> && obj2 is Map<String, dynamic>) {
      // Compare maps
      Set<String> keys = {...obj1.keys, ...obj2.keys};
      for (String key in keys) {
        String currentPath = path.isEmpty ? key : '$path.$key';
        compare(obj1[key], obj2[key], currentPath);
      }
    } else if (obj1 is List || obj2 is List) {
      // Empty lists are set as null
      final original = obj1 is List ? obj1 : [];
      final updated = obj2 is List ? obj2 : [];

      final added = updated.where((e) => !original.contains(e)).toList();
      final removed = original.where((e) => !updated.contains(e)).toList();
      if (overwriteLists) {
        if (added.isNotEmpty || removed.isNotEmpty) {
          differences.add(Modification(path, original, updated));
        }
        return;
      }

      if (removed.isNotEmpty) {
        differences.add(Modification(path, original, JitFieldValue.arrayRemove(removed)));
      }
      if (added.isNotEmpty) {
        differences.add(Modification(path, original, JitFieldValue.arrayUnion(added)));
      }
    } else if (obj1 != obj2) {
      if ((obj1 is double || obj1 is int) && (obj2 is double || obj2 is int)) {
        if (obj1.toStringAsFixed(3) == obj2.toStringAsFixed(3)) {
          return;
        }
      }
      // Add mismatch to the result
      differences.add(Modification(path, obj1, obj2));
    }
  }

  // Start the comparison
  compare(p, n, '');

  return differences;
}
