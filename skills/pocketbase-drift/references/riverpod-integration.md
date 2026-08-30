# Riverpod Integration

This guide covers provider patterns for pocketbase_drift.

## Core Providers

### Dependencies

```dart
// lib/shared/providers/core_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Override these in main.dart
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main.dart');
});

final schemaProvider = Provider<String>((ref) {
  throw UnimplementedError('Override in main.dart');
});
```

### PocketBase Client

```dart
// lib/shared/providers/pocketbase_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

final pocketbaseProvider = Provider<$PocketBase>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final schema = ref.watch(schemaProvider);
  
  final authStore = $AuthStore.prefs(prefs, 'pb_auth');
  
  final client = $PocketBase.database(
    const String.fromEnvironment('POCKETBASE_URL',
      defaultValue: 'http://127.0.0.1:8090'),
    authStore: authStore,
  )..setSchema(schema);
  ref.onDispose(client.close);
  
  return client;
});
```

### Main.dart Setup

```dart
// lib/main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final startupValues = await Future.wait([
    SharedPreferences.getInstance(),
    rootBundle.loadString('assets/pb_schema.json'),
  ]);
  
  final prefs = startupValues[0] as SharedPreferences;
  final schema = startupValues[1] as String;

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        schemaProvider.overrideWithValue(schema),
      ],
      child: const MyApp(),
    ),
  );
}
```

## Authentication Providers

```dart
// lib/shared/providers/auth_provider.dart

// Current user (nullable when not logged in)
final currentUserProvider = StreamProvider<RecordModel?>((ref) {
  final client = ref.watch(pocketbaseProvider);
  
  // Watch auth store changes
  return Stream.periodic(const Duration(seconds: 1)).map((_) {
    if (client.authStore.isValid) {
      return client.authStore.record;
    }
    return null;
  }).distinct();
});

// Simple user ID provider
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.id;
});

// Is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserIdProvider) != null;
});

// Auth controller for login/logout actions
final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref.watch(pocketbaseProvider));
});

class AuthController {
  AuthController(this._client);
  final $PocketBase _client;

  Future<RecordModel> login(String email, String password) async {
    final result = await _client.collection('users').authWithPassword(
      email,
      password,
    );
    return result.record!;
  }

  Future<RecordModel> register({
    required String email,
    required String password,
    required String name,
  }) async {
    await _client.collection('users').create(body: {
      'email': email,
      'password': password,
      'passwordConfirm': password,
      'name': name,
    });
    return login(email, password);
  }

  void logout() {
    _client.authStore.clear();
  }
}
```

## Repository Pattern

### Base Repository

```dart
// lib/shared/repositories/base_repository.dart
abstract class BaseRepository<T> {
  BaseRepository(this.client, this.collectionName);
  
  final $PocketBase client;
  final String collectionName;
  
  $RecordService get collection => client.collection(collectionName);
  
  Stream<QueryState<List<RecordModel>>> watchAll({
    String? filter,
    String? sort,
    String? expand,
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    return collection.watchRecordsState(
      filter: filter,
      sort: sort,
      expand: expand,
      requestPolicy: requestPolicy,
    );
  }
  
  Stream<RecordModel?> watchOne(String id, {String? expand}) {
    return collection.watchRecord(id, expand: expand);
  }
  
  Future<RecordModel> create(Map<String, dynamic> data) {
    return collection.create(
      body: data,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
  }
  
  Future<RecordModel> update(String id, Map<String, dynamic> data) {
    return collection.update(
      id,
      body: data,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
  }
  
  Future<void> delete(String id) {
    return collection.delete(
      id,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
  }
}
```

### Feature Repository

```dart
// lib/features/posts/repositories/post_repository.dart
class PostRepository extends BaseRepository<Post> {
  PostRepository($PocketBase client) : super(client, 'posts');
  
  Stream<List<RecordModel>> watchPublished() {
    return watchAll(
      filter: "published = true",
      sort: '-created',
      expand: 'author',
    );
  }
  
  Stream<List<RecordModel>> watchByAuthor(String authorId) {
    return watchAll(
      filter: "author = '$authorId'",
      sort: '-created',
    );
  }
  
  Future<RecordModel> publish(String postId) {
    return update(postId, {'published': true});
  }
}

// Provider
final postRepositoryProvider = Provider<PostRepository>((ref) {
  return PostRepository(ref.watch(pocketbaseProvider));
});
```

## Stream Providers

```dart
// lib/features/posts/providers/post_providers.dart

// All posts
final postsProvider = StreamProvider<List<RecordModel>>((ref) {
  final repo = ref.watch(postRepositoryProvider);
  return repo.watchPublished();
});

// Posts by current user
final myPostsProvider = StreamProvider<List<RecordModel>>((ref) {
  final repo = ref.watch(postRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  
  if (userId == null) {
    return Stream.value([]);
  }
  
  return repo.watchByAuthor(userId);
});

// Single post
final postProvider = StreamProvider.family<RecordModel?, String>((ref, postId) {
  final repo = ref.watch(postRepositoryProvider);
  return repo.watchOne(postId, expand: 'author,tags');
});
```

## Action Providers

For mutations (create, update, delete):

```dart
// lib/features/posts/providers/post_actions_provider.dart

final postActionsProvider = Provider<PostActions>((ref) {
  return PostActions(ref.watch(postRepositoryProvider));
});

class PostActions {
  PostActions(this._repo);
  final PostRepository _repo;

  Future<RecordModel> create({
    required String title,
    required String content,
    required String authorId,
  }) async {
    return _repo.create({
      'title': title,
      'content': content,
      'author': authorId,
      'published': false,
    });
  }

  Future<RecordModel> update(String id, {String? title, String? content}) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (content != null) data['content'] = content;
    return _repo.update(id, data);
  }

  Future<RecordModel> publish(String id) => _repo.publish(id);
  
  Future<void> delete(String id) => _repo.delete(id);
}
```

## UI Usage

```dart
class PostListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Posts')),
      body: postsAsync.when(
        data: (posts) {
          if (posts.isEmpty) {
            return const EmptyState(message: 'No posts yet');
          }
          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) => PostCard(post: posts[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(postsProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPost(ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _createPost(WidgetRef ref) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    
    await ref.read(postActionsProvider).create(
      title: 'New Post',
      content: 'Content here',
      authorId: userId,
    );
  }
}
```

## Connectivity Provider

```dart
final connectivityProvider = StreamProvider<bool>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.connectivity.statusStream;
});

// Usage in widget
final isConnected = ref.watch(connectivityProvider).valueOrNull ?? true;

if (!isConnected) {
  return OfflineBanner();
}
```

## Pending Sync Provider

```dart
final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  final client = ref.watch(pocketbaseProvider);
  
  // Count all pending records across collections
  final result = await client.db.customSelect('''
    SELECT COUNT(*) as count FROM services 
    WHERE json_extract(data, '\$.synced') = 0
    AND (json_extract(data, '\$.noSync') IS NULL OR json_extract(data, '\$.noSync') = 0)
  ''').getSingle();
  
  return result.read<int>('count');
});

// Show sync indicator
final pendingCount = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
if (pendingCount > 0) {
  Badge(
    label: Text('$pendingCount'),
    child: Icon(Icons.cloud_upload),
  );
}
```

## Summary

| Provider Type | Use For |
|---------------|---------|
| `Provider` | Services, repositories, controllers |
| `StreamProvider` | Reactive data from `watchRecords`/`watchRecord` |
| `StreamProvider.family` | Parameterized streams (by ID, filter) |
| `FutureProvider` | One-time async operations |
| `StateNotifierProvider` | Complex state with mutations |

**Key Pattern:** Repositories wrap `$RecordService`, providers expose streams to UI.
