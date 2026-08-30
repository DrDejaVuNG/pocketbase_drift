# Reactive Streams

This guide covers reactive data streams with watchRecords and watchRecord.

## Overview

Streams emit when data changes from **any** source:
- Local cache updates
- Network fetches
- Realtime subscriptions (WebSocket)
- Background sync operations

## Watch Multiple Records (with QueryState)

Use `watchRecordsState` to receive a `QueryState<List<RecordModel>>` that exposes the data, `isFetchingNetwork` status (to eliminate startup loading flicker), and any `error`:

```dart
// Watch all posts with background fetch status
Stream<QueryState<List<RecordModel>>> stream = client.collection('posts').watchRecordsState();

// Or simple data stream
Stream<List<RecordModel>> stream = client.collection('posts').watchRecords();
// With filtering
Stream<List<RecordModel>> stream = client.collection('posts').watchRecords(
  filter: "author = '${userId}'",
  sort: '-created',
  limit: 20,
  expand: 'author',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Listen to stream
stream.listen((posts) {
  print('Received ${posts.length} posts');
  for (final post in posts) {
    print(post.get<String>('title'));
  }
});
```

## Watch Single Record

```dart
// Watch specific record
Stream<RecordModel?> stream = client.collection('posts').watchRecord(
  'RECORD_ID',
  expand: 'author,tags',
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Listen to changes
stream.listen((post) {
  if (post != null) {
    print('Post updated: ${post.get<String>('title')}');
  } else {
    print('Post was deleted');
  }
});
```

## How watchRecords Works

When `watchRecords` is called:

1. **Initial Cache Emit** - If cache has data, emits immediately
2. **Network Fetch** - Fetches from server (based on RequestPolicy)
3. **Cache Update** - Updates local cache with server data
4. **Realtime Subscribe** - Opens WebSocket subscription
5. **Ongoing Updates** - Emits whenever data changes (local or server)

```
┌─────────────────────────────────────────────────────────┐
│                    watchRecords()                       │
├─────────────────────────────────────────────────────────┤
│ 1. Emit cached data immediately                         │
│ 2. Fetch from network (if policy allows)                │
│ 3. Subscribe to realtime updates                        │
│ 4. Emit on any change:                                  │
│    - Local create/update/delete                         │
│    - Network sync                                       │
│    - Realtime event                                     │
└─────────────────────────────────────────────────────────┘
```

## Using with Riverpod

### StreamProvider (Recommended)

```dart
// All posts
final postsProvider = StreamProvider<List<RecordModel>>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecords(
    sort: '-created',
    expand: 'author',
  );
});

// Filtered by user
final userPostsProvider = StreamProvider.family<List<RecordModel>, String>((ref, userId) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecords(
    filter: "author = '$userId'",
    sort: '-created',
  );
});

// Single post
final postProvider = StreamProvider.family<RecordModel?, String>((ref, postId) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecord(
    postId,
    expand: 'author,tags',
  );
});
```

### UI Usage

```dart
class PostListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(postsProvider);
    
    return postsAsync.when(
      data: (posts) => ListView.builder(
        itemCount: posts.length,
        itemBuilder: (context, index) => PostCard(post: posts[index]),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorView(
        message: error.toString(),
        onRetry: () => ref.invalidate(postsProvider),
      ),
    );
  }
}
```

## Realtime Updates

Streams automatically subscribe to PocketBase realtime events:

```dart
// When another user creates a post, your stream emits with the new post
// When the server updates a post, your stream emits with updated data
// When a post is deleted on server, your stream emits without that post
```

### Manual Subscription

For more control over realtime events:

```dart
final unsubscribe = await client.collection('posts').subscribe(
  '*', // '*' for all records, or specific record ID
  (event) {
    print('Action: ${event.action}'); // create, update, delete
    print('Record: ${event.record}');
  },
);

// Later, unsubscribe
await unsubscribe();
```

## Request Policy for Streams

The policy affects initial behavior:

| Policy | Initial Behavior | Realtime |
|--------|------------------|----------|
| `cacheAndNetwork` | Emit cache, then network | Yes |
| `cacheFirst` | Emit cache, background sync | Yes |
| `cacheOnly` | Emit cache only | No |
| `networkFirst` | Try network, fallback cache | Yes |
| `networkOnly` | Network only | Yes |

```dart
// Cache-first for instant UI
final stream = client.collection('posts').watchRecords(
  requestPolicy: RequestPolicy.cacheFirst,
);

// Network-first for critical data
final stream = client.collection('orders').watchRecords(
  requestPolicy: RequestPolicy.networkFirst,
);
```

## Handling Empty Streams

Streams can emit empty lists:

```dart
final postsProvider = StreamProvider<List<RecordModel>>((ref) {
  final client = ref.watch(pocketbaseProvider);
  return client.collection('posts').watchRecords();
});

// In UI
postsAsync.when(
  data: (posts) {
    if (posts.isEmpty) {
      return EmptyState(
        message: 'No posts yet',
        onAction: () => AppRouter.pushCreatePost(context),
      );
    }
    return ListView.builder(...);
  },
  loading: () => ...,
  error: (e, s) => ...,
);
```

## Optimistic Updates

Changes made locally emit to streams immediately:

```dart
// In provider/repository
await client.collection('posts').create(
  body: {'title': 'New Post'},
  requestPolicy: RequestPolicy.cacheFirst, // Writes to cache first
);
// Stream immediately emits with new post, even before server confirms

// UI updates instantly because stream watches local cache
```

## Multiple Streams

You can have multiple streams watching the same collection with different filters:

```dart
// All published posts
final publishedPostsProvider = StreamProvider((ref) {
  return client.collection('posts').watchRecords(filter: "published = true");
});

// My drafts
final myDraftsProvider = StreamProvider((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return client.collection('posts').watchRecords(
    filter: "author = '$userId' && published = false",
  );
});

// Both streams update independently based on their filters
```
