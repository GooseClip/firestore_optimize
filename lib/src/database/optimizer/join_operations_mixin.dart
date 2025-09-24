import '../operations.dart';
import '../dot_util.dart';
import 'batch_optimizer_mixin.dart';
import 'map_util.dart';

mixin JoinOperationsMixin implements OperationsStore {
  /*
  Uncertainties:
  - If we create set with merge false, does firestore support dot notation?
  - Set with merge true is the same as dot notation
  */

  int $joinOperations(BatchOperation previous, BatchOperation incoming) {
    if (incoming is DeleteOperation) {
      throw Exception("Invalid use of join operations");
    }

    if (previous is DeleteOperation) {
      // Cannot update on deleted object
      if (incoming is UpdateOperation) {
        // Cannot update - deleted
        return 0;
      }

      if (incoming is SetOperation) {
        // Overwrite
        if (incoming.merge == false) {
          operations.remove(previous);
          operations.add(incoming);
          return 1;
        }

        // Possible this is an undesired outcome if the set is trying a partial update
        if (isDot(incoming.data)) {
          throw Exception("Set operation cannot use dot notation");
        }
        operations.remove(previous);
        operations.add(incoming);
        return 1;
      }

      throw Exception("Unexpected operation (${incoming.runtimeType}) applied to DeleteOperation");
    }

    if (previous is SetOperation) {
      if (incoming is SetOperation) {
        return $applySetonSet(previous, incoming);
      }
      if (incoming is UpdateOperation) {
        return $applyUpdateOnSet(previous, incoming);
      }

      throw Exception("Unexpected operation (${incoming.runtimeType}) applied to SetOperation");
    }

    if (previous is UpdateOperation) {
      if (incoming is SetOperation) {
        return $applySetonUpdate(previous, incoming);
      }
      if (incoming is UpdateOperation) {
        return $applyUpdateOnUpdate(previous, incoming);
      }

      throw Exception("Unexpected operation (${incoming.runtimeType}) applied to UpdateOperation");
    }

    throw Exception("Unexpected previous operation (${previous.runtimeType})");
  }

  /* 
   * NOTES
   *
   * If we fail to join, we should definitely not remove the operation, 
   * and possibly reject future joins from that point on.
   * 
  */

 // DONE
  int $applySetonSet(SetOperation previous, SetOperation incoming) {
    final overwrite = previous.overwrite || incoming.overwrite;

    final next = SetOperation(path: previous.path, data: {}, merge: !overwrite);

    // Fully overwrite all previous data
    if (incoming.overwrite) {
      next.data = {...incoming.data};
      operations.remove(previous);
      operations.add(next);
      return 1;
    }

    if (incoming.merge) {
      next.data = mergeMaps(previous.data, toDotMap(incoming.data)); // Set with merge is the same Update with dot notation
    } else {
      next.data = mergeMaps(previous.data, incoming.data);
    }

    operations.remove(previous);
    operations.add(next);
    return 1;
  }

 // DONE
  int $applyUpdateOnSet(SetOperation previous, UpdateOperation incoming) {
    final overwrite = previous.overwrite;

    final next = SetOperation(path: previous.path, data: {}, merge: !overwrite);
    next.data = mergeMaps(previous.data, incoming.data);

    operations.remove(previous);
    operations.add(next);
    return 1;
  }

// DONE
  int $applySetonUpdate(UpdateOperation previous, SetOperation incoming) {
    final overwrite = incoming.overwrite;

    final next = SetOperation(path: previous.path, data: {}, merge: !overwrite);

    // Fully overwrite all previous data
    if (incoming.overwrite) {
      next.data = {...incoming.data};
      operations.remove(previous);
      operations.add(next);
      return 1;
    }

    // TODO double check this if the update didn't want a merge, then we might loose the behaviour

    if (incoming.merge) {
      next.data = mergeMaps(previous.data, toDotMap(incoming.data)); // Set with merge is the same Update with dot notation
    } else {
      next.data = mergeMaps(previous.data, incoming.data);
    }

    operations.remove(previous);
    operations.add(next);
    return 1;
  }

  int $applyUpdateOnUpdate(UpdateOperation previous, UpdateOperation incoming) {
    final next = UpdateOperation(path: previous.path, data: {});

    next.data = mergeMaps(previous.data, incoming.data);
    next.merge = isDot(next.data);
    operations.remove(previous);
    operations.add(next);
    return 1;
  }
}
