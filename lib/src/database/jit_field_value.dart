import 'package:cloud_firestore/cloud_firestore.dart';

sealed class JitFieldValue {
  FieldValue replace();

  static JitArrayUnion arrayUnion(List<dynamic> elements) => JitArrayUnion(elements);

  static JitArrayRemove arrayRemove(List<dynamic> elements) => JitArrayRemove(elements);

  static JitDelete delete() => JitDelete();

  static JitIncrement increment(num value) => JitIncrement(value);

  static JitServerTimestamp serverTimestamp() => JitServerTimestamp();
}

// Maps may be in the format:
// a.b.c: value
// a.b: { c: value }
// a: { b: { c: value } }
Map<String, dynamic> replaceAllJitFieldValues(Map<String, dynamic> m, {bool dropDeletes = false}) {
  Map<String, dynamic> result = {};
  
  for (var entry in m.entries) {
    String key = entry.key;
    dynamic value = entry.value;
    
    // If the value is a JitFieldValue, replace it
    if (value is JitFieldValue) {
      // If it's a JitDelete and dropDeletes is true, skip this key entirely
      if (value is JitDelete && dropDeletes) {
        continue;
      }
      result[key] = value.replace();
    }
    // If the value is a Map, recursively process it
    else if (value is Map<String, dynamic>) {
      result[key] = replaceAllJitFieldValues(value, dropDeletes: dropDeletes);
    }
    // If the value is a List, process each element
    else if (value is List) {
      result[key] = _replaceJitFieldValuesInList(value, dropDeletes: dropDeletes);
    }
    // Otherwise, keep the value as is
    else {
      result[key] = value;
    }
  }
  
  return result;
}

List<dynamic> _replaceJitFieldValuesInList(List<dynamic> list, {bool dropDeletes = false}) {
  List<dynamic> result = [];
  
  for (var item in list) {
    if (item is JitFieldValue) {
      // If it's a JitDelete and dropDeletes is true, skip this item entirely
      if (item is JitDelete && dropDeletes) {
        continue;
      }
      result.add(item.replace());
    } else if (item is Map<String, dynamic>) {
      result.add(replaceAllJitFieldValues(item, dropDeletes: dropDeletes));
    } else if (item is List) {
      result.add(_replaceJitFieldValuesInList(item, dropDeletes: dropDeletes));
    } else {
      result.add(item);
    }
  }
  
  return result;
}

sealed class JitArray extends JitFieldValue {
  JitArray(this.elements);
  List<dynamic> elements;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! JitArray) return false;
    
    if (elements.length != other.elements.length) return false;
    for (var i = 0; i < elements.length; i++) {
      if (elements[i] != other.elements[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(elements);
}

class JitArrayUnion extends JitArray {
  JitArrayUnion(super.elements);

  @override
  FieldValue replace() => FieldValue.arrayUnion(elements);
}

class JitArrayRemove extends JitArray {
  JitArrayRemove(super.elements);

  @override
  FieldValue replace() => FieldValue.arrayRemove(elements);
}

class JitDelete extends JitFieldValue {
  @override
  FieldValue replace() => FieldValue.delete();
}

class JitIncrement extends JitFieldValue {
  JitIncrement(this.value);
  final num value;

  @override
  FieldValue replace() => FieldValue.increment(value);
}

class JitServerTimestamp extends JitFieldValue {
  @override
  FieldValue replace() => FieldValue.serverTimestamp();
}