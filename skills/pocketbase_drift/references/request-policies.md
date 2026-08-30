# Request Policies

This guide covers the 5 RequestPolicy options and when to use each.

## Overview

`RequestPolicy` controls how data flows between local cache and remote server:

```dart
enum RequestPolicy {
  cacheAndNetwork, // Default - balanced offline-first
  cacheFirst,      // Optimistic - instant UI
  cacheOnly,       // Local only - never syncs
  networkFirst,    // Fresh data - strict consistency
  networkOnly,     // Server only - no caching
}
```

## For Read Operations (GET)

### cacheAndNetwork (Default)

**Balanced offline-first behavior.**

- For one-time fetches: Tries network first, falls back to cache
- For streams (`watchRecords`): Emits cache immediately, then updates with network data

```dart
// Default behavior
final posts = await client.collection('posts').getFullList();

// Explicit
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

**Use when:** General-purpose offline-first apps.

### cacheFirst

**Prioritizes instant UI response.**

- Returns cached data immediately
- Fetches from network in background to update cache for next time

```dart
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.cacheFirst,
);
```

**Use when:** UI responsiveness is critical and slightly stale data is acceptable.

### cacheOnly

**Only reads from local cache, never contacts server.**

```dart
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.cacheOnly,
);
```

**Use when:** Working exclusively with locally available data.

### networkFirst

**Prioritizes fresh data from server.**

- Tries to fetch from remote server first
- On success, updates cache and returns fresh data
- On failure (offline), falls back to cached data

```dart
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.networkFirst,
);
```

**Use when:** Need freshest data possible, but can accept stale if network fails.

### networkOnly

**Only reads from server, never uses cache.**

- Throws exception if network unavailable

```dart
final posts = await client.collection('posts').getFullList(
  requestPolicy: RequestPolicy.networkOnly,
);
```

**Use when:** Absolutely need fresh data and can't accept stale data.

---

## For Write Operations (CREATE/UPDATE/DELETE)

### cacheAndNetwork (Default)

**Resilient offline-first.**

- Tries to write to server first
- On success, updates local cache
- On failure, writes to cache and marks as "pending sync" for automatic retry

```dart
await client.collection('posts').create(
  body: {'title': 'My Post'},
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

**Use when:** General-purpose offline-first apps that need to work offline.

### cacheFirst

**Optimistic updates with background sync.**

- Writes to cache first, returns success immediately
- Attempts server sync in background
- If background sync fails, marked as "pending sync" for later retry

```dart
await client.collection('posts').create(
  body: {'title': 'My Post'},
  requestPolicy: RequestPolicy.cacheFirst,
);
```

**Use when:** Instant UI feedback is critical (note-taking, drafts).

### cacheOnly

**Local-only, never syncs.**

- Writes to cache only
- Records marked as `noSync: true` - will NEVER sync to server

```dart
await client.collection('user_preferences').create(
  body: {'theme': 'dark'},
  requestPolicy: RequestPolicy.cacheOnly,
);
```

**Use when:** Local-only data (user preferences, temp data, offline-only features).

### networkFirst

**Server is source of truth (strict consistency).**

- Writes to server first
- On success, updates local cache
- On failure, **throws error** (no cache fallback)

```dart
await client.collection('orders').create(
  body: {'product_id': '123', 'quantity': 1},
  requestPolicy: RequestPolicy.networkFirst,
);
```

**Use when:** Data integrity is critical (financial transactions, inventory).

### networkOnly

**Server only, never touches cache.**

- Writes directly to server
- Throws exception if network unavailable or server fails

```dart
await client.collection('analytics').create(
  body: {'event': 'page_view'},
  requestPolicy: RequestPolicy.networkOnly,
);
```

**Use when:** Need immediate server confirmation, no local state needed.

---

## Choosing the Right Policy

| Scenario | Read Policy | Write Policy |
|----------|-------------|--------------|
| **Real-time collaborative app** | `networkFirst` | `networkFirst` |
| **Offline-first mobile app** | `cacheAndNetwork` | `cacheAndNetwork` |
| **Instant feedback UI** (notes, drafts) | `cacheFirst` | `cacheFirst` |
| **Financial transactions** | `networkOnly` | `networkFirst` |
| **Analytics/telemetry** | N/A | `networkOnly` |
| **Local-only settings** | `cacheOnly` | `cacheOnly` |
| **News feed** (freshness matters) | `networkFirst` | N/A |
| **Offline form submission** | N/A | `cacheAndNetwork` |

---

## Behavior Summary

### Read Policies

| Policy | Online | Offline |
|--------|--------|---------|
| `cacheAndNetwork` | Network → Cache update | Cache fallback |
| `cacheFirst` | Cache → Background refresh | Cache only |
| `cacheOnly` | Cache only | Cache only |
| `networkFirst` | Network → Cache update | Cache fallback |
| `networkOnly` | Network only | **Throws error** |

### Write Policies

| Policy | Online | Offline |
|--------|--------|---------|
| `cacheAndNetwork` | Network → Cache | Cache + pending sync |
| `cacheFirst` | Cache → Background sync | Cache + pending sync |
| `cacheOnly` | Cache only (noSync) | Cache only (noSync) |
| `networkFirst` | Network → Cache | **Throws error** |
| `networkOnly` | Network only | **Throws error** |

---

## Example: Mixed Policies in App

```dart
class PostRepository {
  PostRepository(this._client);
  final $PocketBase _client;

  // Posts should be fresh but work offline
  Future<List<RecordModel>> getPosts() => _client.collection('posts').getFullList(
    requestPolicy: RequestPolicy.cacheAndNetwork,
  );

  // Creating posts works offline, syncs later
  Future<RecordModel> createPost(Map<String, dynamic> data) => 
    _client.collection('posts').create(
      body: data,
      requestPolicy: RequestPolicy.cacheAndNetwork,
    );

  // User preferences are local-only
  Future<RecordModel> savePreferences(Map<String, dynamic> prefs) =>
    _client.collection('user_preferences').create(
      body: prefs,
      requestPolicy: RequestPolicy.cacheOnly,
    );

  // Orders require server confirmation
  Future<RecordModel> createOrder(Map<String, dynamic> order) =>
    _client.collection('orders').create(
      body: order,
      requestPolicy: RequestPolicy.networkFirst,
    );
}
```
