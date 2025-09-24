# Firestore Optimize

## Motivation

One of the scariest things about Firestore is the possibility for infinite costs. 

This package attempts to address these concerns by the following:
- **Rate Limiting**: Prevent a small bug in your code or bad actor from costing you thousands.  
- **Batching**: Reduce network throughput.
- **Merging**: Eliminate unnecessary operations, e.g. [update -> update -> delete] will be reduced to just [delete].

### **Merging**

Multiple operations on the same document are automatically merged to reduce writes and avoid Firestore 1 write per second limits. 
This is the main way you can save costs. [update -> update -> update] will be merged to a single [update] operation.

### **Dot Notation Support**

- **Nested Map Flattening**: Convert nested maps to dot notation for Firestore updates
- **Dot Map Expansion**: Convert dot notation back to nested structures
- **Conflict Detection**: Intelligent handling of path conflicts

> See test cases

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  firestore_optimize: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Quick Start

### Setup with Riverpod Provider (optional)

```dart
import 'package:firestore_optimize/firestore_optimize.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Create a provider for the optimized Firestore data source
final firestoreDataSourceProvider = Provider<FirestoreDataSource>((ref) {
  return FirestoreDataSource.defaultInstance();
});

// Use in your widgets
class UserService extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataSource = ref.read(firestoreDataSourceProvider);

    return ElevatedButton(
      onPressed: () => _updateUser(dataSource),
      child: Text('Update User'),
    );
  }

  Future<void> _updateUser(FirestoreDataSource dataSource) async {
    // Set user data with automatic optimization
    await dataSource.set(
      path: DocumentPath('users/user1'),
      data: {
        'name': 'John Doe',
        'age': 30,
        'profile': {
          'bio': 'Flutter developer',
          'createdAt': JitFieldValue.serverTimestamp(),
        },
        'settings': {
          'theme': 'dark',
          'notifications': true,
          'prefs': {
            'language': 'en',
            'timezone': 'UTC',
            'autoSave': true,
          }
        },
      },
      batch: true,  // Enable batching for optimization
      merge: true,  // Merge with existing data
    );

    // Update user data - will be merged with above operation
    // Note: update supports dot notation for nested field updates
    await dataSource.update(
      path: DocumentPath('users/user1'),
      data: {
        'age': 31,
        'profile.lastLogin': JitFieldValue.serverTimestamp(),
        'profile.loginCount': JitFieldValue.increment(1),
        'tags': JitFieldValue.arrayUnion(['active']),
        'settings.prefs': {
            'language': 'fr'
        }
      },
      batch: true,  // Automatically optimized with previous operation
    );
  }
}
```

## Core Components

### Firestore Data Source

The `FirestoreDataSource` is the main entry point for optimized Firestore operations:

> **Important**: `set()` does not support dot notation - use nested objects instead. Only `update()` supports dot notation for nested field updates.

```dart
// Setup data source (typically in a provider)
final dataSource = FirestoreDataSource.defaultInstance();

// Set document data (use nested objects, not dot notation)
await dataSource.set(
  path: DocumentPath('users/user1'),
  data: {
    'name': 'John',
    'age': 30,
    'profile': {
      'email': 'john@example.com',
      'verified': true,
    },
  },
  batch: true,   // Enable batching for optimization
  merge: true,   // Merge with existing data
  rateLimit: true, // Enable rate limiting
);

// Update document data (supports dot notation for nested updates)
await dataSource.update(
  path: DocumentPath('users/user1'),
  data: {
    'age': 31,
    'profile.lastSeen': JitFieldValue.serverTimestamp(),
    'profile.loginCount': JitFieldValue.increment(1),
    'settings.theme': 'light',  // Dot notation for nested field updates
  },
  batch: true,
  rateLimit: true,
);

// Delete document
await dataSource.delete(
  path: DocumentPath('users/user1'),
  batch: true,
  rateLimit: true,
);

// Add new document
final docRef = await dataSource.add(
  path: CollectionPath('users'),
  data: {'name': 'Jane', 'email': 'jane@example.com'},
  rateLimit: true,
);
```

### JIT Field Values

Type-safe wrappers for Firestore `FieldValue` operations:

```dart
final data = {
  'counter': JitFieldValue.increment(1),
  'tags': JitFieldValue.arrayUnion(['new-tag']),
  'oldField': JitFieldValue.delete(),
  'items': JitFieldValue.arrayRemove(['removed-item']),
  'timestamp': JitFieldValue.serverTimestamp(),
};

// Convert JIT values to actual FieldValues
final processedData = replaceAllJitFieldValues(data);
```

### Dot Notation Utilities

Work with nested data using dot notation:

```dart
// Convert nested map to dot notation
final nested = {
  'user': {
    'profile': {'name': 'John', 'age': 30},
    'settings': {'theme': 'dark'}
  }
};

final dotNotations = toDotNotation(nested);
// Results in: ['user.profile.name': 'John', 'user.profile.age': 30, 'user.settings.theme': 'dark']

// Convert dot notation back to nested structure
final dotMap = DotMap({
  'user.profile.name': 'Jane',
  'user.profile.age': 25,
  'user.settings.notifications': true,
});

final reconstructed = fromDotMap(dotMap);
// Results in nested structure
```

### Rate Limiting

Manage Firestore write throughput:

```dart
final rateLimiter = RateLimitManager(
  maxRequests: 100,
  rateLimitWindow: Duration(seconds: 60),
);

// Check and enforce rate limits
await rateLimiter.checkRateLimit(
  FirestorePath('users/user1'),
  'write',
  batched: true,
);

// Release rate limit slots
rateLimiter.release(FirestorePath('users/user1'), 5);
```

## Advanced Usage

### Operation Optimization

The package automatically optimizes operations:

```dart
final dataSource = ref.read(firestoreDataSourceProvider);

// These operations will be merged automatically
await dataSource.set(
  path: DocumentPath('documents/doc1'),
  data: {
    'field1': 'value1',
    'metadata': {
      'createdAt': JitFieldValue.serverTimestamp(),
    },
  },
  batch: true,
  merge: true,
);

await dataSource.update(
  path: DocumentPath('documents/doc1'),
  data: {
    'field2': 'value2',
    'metadata.lastUpdated': JitFieldValue.serverTimestamp(),
  },
  batch: true,
);

await dataSource.set(
  path: DocumentPath('documents/doc1'),
  data: {
    'field3': 'value3',
    'status': {
      'active': true,
      'version': 2,
    },
  },
  batch: true,
  merge: true,
);

// Results in a single optimized operation instead of three separate ones
// Saves ~66% on write operations and costs!
```

### Real-World Example with Riverpod

Here's a complete example of using the package in a Flutter app:

```dart
// providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firestore_optimize/firestore_optimize.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final firestoreDataSourceProvider = Provider<FirestoreDataSource>((ref) {
  return FirestoreDataSource.defaultInstance();
});

// user_service.dart
class UserService {
  UserService(this.dataSource);
  final FirestoreDataSource dataSource;

  Future<void> updateUserProfile({
    required String userId,
    required String name,
    required int age,
    required Map<String, dynamic> preferences,
  }) async {
    // All these operations will be automatically optimized and batched
    await dataSource.set(
      path: DocumentPath('users/$userId'),
      data: {
        'name': name,
        'age': age,
        'updatedAt': JitFieldValue.serverTimestamp(),
        'profile': {
          'lastModified': JitFieldValue.serverTimestamp(),
        },
        'stats': {
          'profileUpdates': 0,
        },
      },
      batch: true,
      merge: true,
    );

    // Use dot notation for nested field updates in update
    await dataSource.update(
      path: DocumentPath('users/$userId'),
      data: {
        'preferences.theme': preferences['theme'],
        'preferences.notifications': preferences['notifications'],
        'profile.lastModified': JitFieldValue.serverTimestamp(),
        'stats.profileUpdates': JitFieldValue.increment(1),
      },
      batch: true,
    );
  }
}

// In your widget
class UserProfileWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataSource = ref.read(firestoreDataSourceProvider);
    final userService = UserService(dataSource);

    return ElevatedButton(
      onPressed: () => userService.updateUserProfile(
        userId: 'user123',
        name: 'John Doe',
        age: 30,
        preferences: {'theme': 'dark', 'notifications': true},
      ),
      child: Text('Update Profile'),
    );
  }
}
```

### Handling Complex Updates

```dart
final dataSource = ref.read(firestoreDataSourceProvider);

// Complex nested updates with dot notation (only works with update)
final updates = {
  'user.profile.name': 'Updated Name',
  'user.settings.notifications': true,
  'user.metadata.lastLogin': JitFieldValue.serverTimestamp(),
  'user.stats.loginCount': JitFieldValue.increment(1),
  'user.tags': JitFieldValue.arrayUnion(['active']),
};

await dataSource.update(  // ✅ update supports dot notation
  path: DocumentPath('users/user123'),
  data: updates,
  batch: true,  // Automatically optimized with other operations
  rateLimit: true,  // Respects rate limits
);

// For set, use nested objects instead:
await dataSource.set(  // ❌ set does NOT support dot notation
  path: DocumentPath('users/user123'),
  data: {
    'user': {
      'profile': {'name': 'Updated Name'},
      'settings': {'notifications': true},
      'metadata': {'lastLogin': JitFieldValue.serverTimestamp()},
      'stats': {'loginCount': JitFieldValue.increment(1)},
    },
    'tags': JitFieldValue.arrayUnion(['active']),
  },
  batch: true,
  merge: true,
);
```

## Performance Benefits

- **Reduced Write Operations**: Operation merging can reduce writes by 50-80%
- **Lower Costs**: Fewer operations mean lower Firestore billing
- **Better Performance**: Batched operations are faster than individual writes
- **Rate Limit Protection**: Automatic throttling prevents quota exhaustion
- **Conflict Resolution**: Smart handling of conflicting operations

## Testing

The package includes comprehensive tests covering all functionality:

```bash
flutter test
```

Test coverage includes:

- Operation optimization and merging
- Dot notation conversion and conflict handling
- Rate limiting and queuing
- JIT field value processing
- Batch operation management

## API Reference

### Core Classes

- **`OperationsManager`**: Main interface for batched operations
- **`FirestoreDataSource`**: High-level data source with optimization
- **`RateLimitManager`**: Rate limiting and request queuing
- **`JitFieldValue`**: Type-safe field value operations

### Operation Types

- **`SetOperation`**: Document set operations with merge support
- **`UpdateOperation`**: Document update operations
- **`DeleteOperation`**: Document deletion operations
- **`BatchOperation`**: Base class for all operations

### Utility Types

- **`DocumentPath`**: Type-safe document path handling
- **`CollectionPath`**: Type-safe collection path handling
- **`FirestorePath`**: Base path type
- **`DotMap`**: Map with dot notation support
- **`DotNotation`**: Dot notation representation

### Error & Failure Types

- **`OperationFailure`**: Abstract base class for all operation failures.
- **`BatchFailure`**: Represents a failure of a single `BatchOperation` during a failover commit. Contains the original `operation`.
- **`MergeFailure`**: Represents a failure during the merging of pending operations. Contains the list of `operations` being merged.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes.
