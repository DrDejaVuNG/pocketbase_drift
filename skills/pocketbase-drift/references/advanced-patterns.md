# Advanced Patterns

This guide covers advanced patterns for pocketbase_drift including auth flows, optimistic updates, pagination, and troubleshooting.

## Model Factory Patterns

### Complete Model with RecordModel Helpers

```dart
class Post {
  const Post({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    this.author,
    this.tags = const [],
    required this.published,
    required this.created,
    required this.updated,
  });
  
  final String id;
  final String title;
  final String content;
  final String authorId;
  final User? author;
  final List<String> tags;
  final bool published;
  final DateTime created;
  final DateTime updated;
  
  factory Post.fromRecord(RecordModel record) {
    // Use dot notation for expanded relations (record.expand is deprecated)
    final expandedAuthor = record.get<RecordModel>('expand.author');
    
    return Post(
      id: record.id,
      title: record.getStringValue('title'),
      content: record.getStringValue('content'),
      authorId: record.getStringValue('authorId'),
      author: expandedAuthor != null ? User.fromRecord(expandedAuthor) : null,
      tags: record.getListValue<String>('tags'),
      published: record.getBoolValue('published'),
      created: DateTime.parse(record.get('created')),
      updated: DateTime.parse(record.get('updated')),
    );
  }
  
  Map<String, dynamic> toMap() => {
    'title': title,
    'content': content,
    'authorId': authorId,
    'tags': tags,
    'published': published,
  };
  
  Post copyWith({
    String? title,
    String? content,
    List<String>? tags,
    bool? published,
  }) {
    return Post(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorId: authorId,
      author: author,
      tags: tags ?? this.tags,
      published: published ?? this.published,
      created: created,
      updated: updated,
    );
  }
}
```

## Advanced Auth Flow

### Token Refresh Logic

```dart
class AuthRepository {
  AuthRepository(this._client);
  final $PocketBase _client;

  User? get currentUser {
    final record = _client.authStore.record;
    if (record == null) return null;
    return User.fromMap(record.toJson());
  }

  bool get isAuthenticated => _client.authStore.isValid;

  DateTime? _getTokenExpiration() {
    final token = _client.authStore.token;
    if (token.isEmpty) return null;

    try {
      // JWT format: header.payload.signature
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // Decode payload (base64)
      final payload = parts[1];
      final normalized = base64.normalize(payload);
      final decoded = utf8.decode(base64.decode(normalized));
      final json = jsonDecode(decoded);

      // Extract exp (Unix timestamp in seconds)
      final exp = json['exp'] as int?;
      if (exp == null) return null;

      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (e) {
      return null; // Decode error, assume needs refresh
    }
  }

  bool shouldRefreshToken() {
    if (!_client.authStore.isValid) return false;

    final expiresAt = _getTokenExpiration();
    if (expiresAt == null) return true; // Can't decode, refresh to be safe

    final now = DateTime.now();
    const threshold = Duration(days: 1);
    return expiresAt.difference(now) <= threshold;
  }

  Future<void> refreshToken() async {
    await _client.collection('users').authRefresh();
  }
}
```

### Auth State Notifier with Auto-Refresh

```dart
class AuthStateNotifier extends StateNotifier<AsyncValue<User?>> {
  AuthStateNotifier(this._authRepository) : super(const AsyncValue.data(null)) {
    _init();
  }

  final AuthRepository _authRepository;

  void _init() {
    final user = _authRepository.currentUser;
    state = AsyncValue.data(user);
    _refreshTokenIfNeeded();
  }

  Future<void> _refreshTokenIfNeeded() async {
    if (!_authRepository.shouldRefreshToken()) return;

    try {
      await _authRepository.refreshToken();
    } catch (e) {
      // Token refresh failed, logout user
      logout();
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final user = await _authRepository.login(email, password);
      state = AsyncValue.data(user);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void logout() {
    _authRepository.logout();
    state = const AsyncValue.data(null);
  }
}
```

## Optimistic Updates

UI updates immediately, reverts on error:

```dart
class LikeNotifier extends StateNotifier<Post> {
  LikeNotifier(this._repository, super.post);
  
  final PostRepository _repository;

  Future<void> toggleLike() async {
    final previousState = state;
    
    // Optimistically update UI
    state = state.copyWith(isLiked: !state.isLiked);
    
    try {
      await _repository.update(state.id, {'liked': state.isLiked});
    } catch (e) {
      // Revert on error
      state = previousState;
      rethrow;
    }
  }
}
```

## Infinite Scroll

```dart
class PostListState {
  const PostListState({
    this.posts = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });
  
  final List<Post> posts;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  
  PostListState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return PostListState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class PostListNotifier extends StateNotifier<PostListState> {
  PostListNotifier(this._repository) : super(const PostListState()) {
    loadMore(); // Initial load
  }
  
  final PostRepository _repository;
  int _currentPage = 0;
  static const _pageSize = 20;

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final newPosts = await _repository.getPage(
        page: _currentPage + 1,
        perPage: _pageSize,
      );
      
      if (newPosts.isEmpty || newPosts.length < _pageSize) {
        state = state.copyWith(
          posts: [...state.posts, ...newPosts],
          hasMore: false,
          isLoading: false,
        );
      } else {
        _currentPage++;
        state = state.copyWith(
          posts: [...state.posts, ...newPosts],
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false, 
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    _currentPage = 0;
    state = const PostListState();
    await loadMore();
  }
}

final postListProvider = StateNotifierProvider<PostListNotifier, PostListState>((ref) {
  return PostListNotifier(ref.watch(postRepositoryProvider));
});
```

### Infinite Scroll UI

```dart
class PostListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postListProvider);
    
    return RefreshIndicator(
      onRefresh: () => ref.read(postListProvider.notifier).refresh(),
      child: ListView.builder(
        itemCount: state.posts.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.posts.length) {
            // Load more trigger
            if (!state.isLoading) {
              ref.read(postListProvider.notifier).loadMore();
            }
            return const Center(child: CircularProgressIndicator());
          }
          return PostCard(post: state.posts[index]);
        },
      ),
    );
  }
}
```

## Pull-to-Refresh

```dart
class PostListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    
    return RefreshIndicator(
      onRefresh: () async {
        // Force network refresh
        final repository = ref.read(postRepositoryProvider);
        await repository.getAll(
          requestPolicy: RequestPolicy.networkOnly,
        );
        // Rebuild stream with new data
        ref.invalidate(postsProvider);
      },
      child: postsAsync.when(
        data: (posts) => ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) => PostCard(post: posts[index]),
        ),
        loading: () => const LoadingView(),
        error: (e, s) => ErrorView(error: e),
      ),
    );
  }
}
```

## Troubleshooting

### Changes Not Syncing

```dart
// Check connectivity
if (!client.connectivity.isConnected) {
  print('Device is offline');
}

// Check pending items
final pending = await client.collection('posts').pending().get();
print('Pending: ${pending.length}');

// Manually trigger sync
await client.collection('posts').retryLocal().last;
```

### Schema Validation Errors

```dart
// Ensure schema is cached
await client.cacheSchema(schemaJson);

// Check collections exist
final collections = await client.db.$collections().get();
print('Collections: ${collections.map((c) => c.name).toList()}');
```

### File Not Found in Cache

```dart
// Force network fetch for missing files
final bytes = await client.files.getFileData(
  recordId: id,
  recordCollectionName: 'posts',
  filename: filename,
  requestPolicy: RequestPolicy.networkOnly,
);
```

## Security Considerations

### Data Sanitization

```dart
class PostRepository {
  Future<Post> create(Map<String, dynamic> data) async {
    // Sanitize user input before saving
    final sanitized = {
      'title': _sanitize(data['title'] as String? ?? ''),
      'content': _sanitize(data['content'] as String? ?? ''),
      // Don't allow users to set server-controlled fields
    };
    
    final record = await _client.collection('posts').create(
      body: sanitized,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );
    
    return Post.fromRecord(record);
  }
  
  String _sanitize(String input) {
    return input
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .trim();
  }
}
```

## Testing Helpers

### In-Memory Client for Tests

```dart
class TestHelpers {
  static $PocketBase createTestClient() {
    return $PocketBase.database(
      'http://test.pocketbase.io',
      inMemory: true, // No persistence
    );
  }
  
  static Future<void> seedTestData(
    $PocketBase client,
    String collection,
    List<Map<String, dynamic>> data,
  ) async {
    for (final item in data) {
      await client.db.$create(collection, {
        ...item,
        'synced': true,
      });
    }
  }
  
  static Future<void> clearTestData($PocketBase client) async {
    await client.db.clearAllData();
  }
}

// Usage in tests
void main() {
  late $PocketBase testClient;
  late PostRepository repository;

  setUp(() async {
    testClient = TestHelpers.createTestClient();
    repository = PostRepository(testClient);
  });

  tearDown(() async {
    await TestHelpers.clearTestData(testClient);
  });

  test('getAll returns seeded posts', () async {
    await TestHelpers.seedTestData(testClient, 'posts', [
      {'id': '1', 'title': 'Test Post'},
      {'id': '2', 'title': 'Another Post'},
    ]);
    
    final posts = await repository.getAll(
      requestPolicy: RequestPolicy.cacheOnly,
    );
    
    expect(posts, hasLength(2));
    expect(posts.first.title, 'Test Post');
  });
}
```

## Complete Todo App Example

```dart
// models/todo.dart
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.completed,
    required this.created,
    required this.updated,
  });
  
  final String id;
  final String title;
  final bool completed;
  final DateTime created;
  final DateTime updated;
  
  factory Todo.fromRecord(RecordModel record) {
    return Todo(
      id: record.id,
      title: record.getStringValue('title'),
      completed: record.getBoolValue('completed'),
      created: DateTime.parse(record.get('created')),
      updated: DateTime.parse(record.get('updated')),
    );
  }
  
  Map<String, dynamic> toMap() => {
    'title': title,
    'completed': completed,
  };
}

// repositories/todo_repository.dart
final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(ref.watch(pocketbaseProvider));
});

class TodoRepository {
  TodoRepository(this._client);
  final $PocketBase _client;
  
  Stream<List<Todo>> watchAll() {
    return _client.collection('todos')
      .watchRecords(sort: '-created')
      .map((records) => records.map(Todo.fromRecord).toList());
  }
  
  Future<Todo> create(String title) async {
    final record = await _client.collection('todos').create(
      body: {'title': title, 'completed': false},
    );
    return Todo.fromRecord(record);
  }
  
  Future<Todo> toggleCompleted(String id, bool completed) async {
    final record = await _client.collection('todos').update(
      id,
      body: {'completed': completed},
    );
    return Todo.fromRecord(record);
  }
  
  Future<void> delete(String id) async {
    await _client.collection('todos').delete(id);
  }
}

// providers/todo_providers.dart
final todosProvider = StreamProvider<List<Todo>>((ref) {
  return ref.watch(todoRepositoryProvider).watchAll();
});

// screens/todo_list_screen.dart
class TodoListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosAsync = ref.watch(todosProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      body: todosAsync.when(
        data: (todos) => ListView.builder(
          itemCount: todos.length,
          itemBuilder: (context, index) => TodoTile(todo: todos[index]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTodo(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
  
  void _addTodo(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Todo'),
        content: TextField(
          autofocus: true,
          onSubmitted: (value) {
            ref.read(todoRepositoryProvider).create(value);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

class TodoTile extends ConsumerWidget {
  const TodoTile({super.key, required this.todo});
  final Todo todo;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(
        todo.title,
        style: TextStyle(
          decoration: todo.completed ? TextDecoration.lineThrough : null,
        ),
      ),
      leading: Checkbox(
        value: todo.completed,
        onChanged: (value) {
          ref.read(todoRepositoryProvider).toggleCompleted(
            todo.id,
            value ?? false,
          );
        },
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete),
        onPressed: () {
          ref.read(todoRepositoryProvider).delete(todo.id);
        },
      ),
    );
  }
}
```
