import 'package:flutter/foundation.dart';
import '../operations.dart';
import 'join_operations_mixin.dart';

abstract interface class OperationsStore {
  List<BatchOperation> get operations;
  set operations(List<BatchOperation> ops);
}


abstract interface class OperationsOptimizer with JoinOperationsMixin implements OperationsStore {
}

mixin BatchOptimizerMixin implements OperationsOptimizer {
  int totalOptimizations = 0;
  int optimizeOperations(BatchOperation operation) {
    var optimized = 0;

    if (operations.isEmpty) {
      operations.add(operation);
      return 0;
    }

    // A delete nullifies the previous operations
    if (operation is DeleteOperation) {
      optimized += $removePreviousOperations(operation);
      operations.add(operation);
    }

    // A set without merge is an overwrite
    if (operation is SetOperation && operation.merge == false) {
      optimized += $removePreviousOperations(operation);
      operations.add(operation);
    }

    if (operation is SetOperation || operation is UpdateOperation) {
      final ops = operations.where((op) => op.path == operation.path && op is! DeleteOperation).toList();

      // Escape early if ops is empty
      if (ops.isEmpty) {
        operations.add(operation);
      } else {
        if (ops.length != 1) {
          throw Exception("Not implemented - join all previous operations before handling next");
        }

        optimized += $joinOperations(ops.first, operation);
      }
      // Added to operations internally
    }

    totalOptimizations += optimized;

    // Log.v("[Optimizer]${operation.toString()} batch: $optimized, total: $totalOptimizations");
    return optimized;
  }

  @visibleForTesting
  int $removePreviousOperations(BatchOperation operation) {
    final match = operations.where((op) => op.path == operation.path).toList();
    operations.removeWhere((op) => match.contains(op));
    return match.length;
  }
}
