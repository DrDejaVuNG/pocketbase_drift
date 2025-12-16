## 0.3.8

### New Features

- **Nullable Cache TTL** - The `cacheTtl` parameter in `$PocketBase.database()` is now nullable. Setting it to `null` disables automatic cache cleanup, allowing data to be persisted indefinitely.
- **Support for `updatedAt`/`createdAt` fields** - Added automatic fallback support for PocketBase applications that use `updatedAt` and `createdAt` field names instead of the default `updated` and `created`. This ensures that cache TTL cleanup, version comparisons, and local data storage work correctly regardless of the timestamp naming convention used.
- **Configurable Logout Cleanup** - Added `clearOnLogout` parameter to `$AuthStore` (default: `true`). Developers can now set this to `false` to preserve local data when the user logs out, improving the experience for offline-first applications where re-fetching data might be expensive.

### Bug Fixes

- **Fixed Connectivity & Cache Issues on Re-login** - Resolved a critical issue where logging out and back in would cause connectivity to report incorrectly and cached streams to stop responding.
  - `ConnectivityService` is now a true singleton that is never disposed, matching the behavior of `connectivity_plus`'s global `Connectivity()` singleton. This prevents instability when recreating client instances.
  - Simplified database connection by removing manual isolate spawning, using Drift's built-in connection handling instead.
  - **Note for developers**: If using Riverpod, invalidate your `pocketBaseProvider` after logout to ensure all dependent providers are refreshed with the new client instance.

## 0.3.7

### Bug Fixes

- **Fixed nested expanded records not being cached** - When fetching records with nested expand, the related records are now automatically cached to their respective collection tables. This enables local expand to work correctly when those collections are later queried independently.
  - Previously, `mergeLocal` (used by `getFullList`) bypassed the caching logic, causing expanded records to be missing from the local cache.
  - The fix also applies recursively, so deeply nested expands are properly cached at all levels.

### Tests

- Added `expand_cache_test.dart` with 4 tests validating nested expanded record caching behavior.

## 0.3.6

**BREAKING CHANGE**: Local relation expansion now matches PocketBase SDK behavior.

### Breaking Changes

- **Single relations now return objects directly** - Previously, all expanded relations were wrapped in a list, requiring index access (e.g., `expand.author.0.name`). Now, single relations (`maxSelect == 1`) return the object directly, matching the official PocketBase SDK behavior:
  - **Before**: `record.get<String>('expand.author.0.name')`
  - **After**: `record.get<String>('expand.author.name')`
  - Multi relations (`maxSelect > 1`) still return lists and require index access

### Migration Guide

If you were accessing single relation expands with `.0` index, remove the index:

```dart
// Before (0.3.5 and earlier)
final authorName = post.get<String>('expand.author.0.name');
final author = post.get<RecordModel>('expand.author.0');

// After (0.3.6+)
final authorName = post.get<String>('expand.author.name');
final author = post.get<RecordModel>('expand.author');
```

Multi-relation access remains unchanged:
```dart
final firstTag = post.get<String>('expand.tags.0.name');  // Still uses index
```

## 0.3.5

### Documentation

- **Expanding Relations Guide** - Added comprehensive documentation for accessing expanded relations using the PocketBase SDK's `record.get<T>()` dot-notation path syntax (e.g., `record.get<String>('expand.author.0.name')`). Covers basic expansion, nested (multi-level) expansion, and multi-relation access patterns.

- **Advanced: Direct Database Access** - Added new documentation section explaining how to access the underlying Drift database directly via `client.db` for advanced use cases:
  - Database schema overview (tables, columns, primary keys)
  - Running raw SQL queries with `customSelect`
  - Joining data across collections
  - Reactive streams with raw SQL using `.watch()`
  - Executing raw statements with `customStatement`
  - Using the built-in `$query` method

### Tests

- Added `expand_dot_notation_test.dart` with 8 comprehensive tests validating that locally expanded relations work correctly with the PocketBase SDK's dot-notation path access API.

## 0.3.4

### New Features

- **Cache TTL & Expiration** - Added configurable time-to-live (TTL) for cached data. Old synced records and cached responses are automatically cleaned up when `runMaintenance()` is called.
  - Configurable `cacheTtl` parameter in `$PocketBase.database()` (default: 60 days)
  - New `runMaintenance()` method to clean up expired cache data
  - Returns `MaintenanceResult` with counts of deleted items
  - Only removes synced data - unsynced local changes are always preserved
  - Cleans up expired file blobs automatically

## 0.3.3

### New Features

- **Filter-aware sync for deleted records** - Added `syncLocal` method that intelligently syncs deletions from the server to local cache. When fetching data with `getFullList`, the system now detects and removes records that were deleted on the server while offline, even when using filtered queries. This ensures local cache stays in sync with server state.
  - Works with both filtered and unfiltered queries
  - Only deletes records within the filter scope
  - Preserves unsynced local changes, local-only records, and pending deletions
  - Includes safety check to prevent mass deletion on server errors

### Improvements

- **Enhanced `getFullList` behavior** - Now automatically calls `syncLocal` after fetching all pages, ensuring deleted records are cleaned up from local cache
- **Added comprehensive test coverage** - New test suite (`sync_local_test.dart`) with 7 tests covering all edge cases for filter-aware deletion
- **PocketBase-compatible ID generation** - Local IDs are now generated using PocketBase's exact format (`[a-z0-9]{15}`). This eliminates the need for ID remapping during sync, simplifying the offline-first flow:
  - Records created offline now sync with the same ID they were created with
  - Removed `shortid` dependency in favor of a built-in secure random generator
  - Exported `newId()` function for use by consuming applications

### Bug Fixes

- **Fixed partial update validation for offline scenarios** - Partial updates now correctly merge with existing record data before validation, allowing updates with only changed fields when using `cacheFirst` or `cacheOnly` policies
- **Fixed SQLite quote semantics in filters** - Added automatic quote normalization in filter parser to convert double quotes to single quotes for string literals, preventing SQLite from misinterpreting values as identifiers. Both `'id = "$id"'` and `"id = '$id'"` now produce correct SQL


## 0.3.2

### Bug Fixes

- **Critical: Fixed pending sync execution on app restart** - Resolved a critical issue where pending changes would not sync when the app was completely closed and reopened. The sync mechanism now queries the database to identify services with pending records instead of relying on an in-memory cache that gets cleared on app restart. This ensures that all offline changes are reliably synced when connectivity is restored, even after a complete app restart.

## 0.3.1

- Resolved pub.dev issue

## 0.3.0

**BREAKING CHANGES**: Added new `RequestPolicy` options for more explicit control over caching and network behavior.

### New Features

- **New RequestPolicy options**: Added `RequestPolicy.cacheFirst` and `RequestPolicy.networkFirst` for more explicit control over data fetching and synchronization behavior
  - `cacheFirst`: Returns cache immediately, fetches network in background to update cache
  - `networkFirst`: Tries network first, falls back to cache on failure (replaces old `cacheAndNetwork` behavior for reads)
  - `cacheAndNetwork`: Now has distinct behavior - for reads it behaves like `networkFirst`, but for writes it provides resilient offline-first synchronization with automatic retry

### Improvements

- **Refactored write operations** (create/update/delete): Split monolithic methods into smaller, policy-specific implementations for better maintainability
- **Enhanced documentation**: Comprehensive guide on choosing the right `RequestPolicy` for different scenarios
- **Better error messages**: More descriptive error messages that indicate which policy was used when operations fail

### Write Operation Behavior Changes

- **`networkFirst` (new strict mode)**: Writes to server first, updates cache on success, throws error on failure (NO cache fallback)
- **`cacheFirst` (new optimistic mode)**: Writes to cache first, attempts server sync in background
- **`cacheAndNetwork` (enhanced)**: Tries server first, falls back to cache with pending sync on failure (maintains backward compatibility for offline-first apps)

### Migration Guide

**Existing code continues to work** - the default `RequestPolicy.cacheAndNetwork` maintains backward compatibility for most use cases.

However, if you were relying on specific behavior:
- If you want strict server-first writes with no offline fallback, use `RequestPolicy.networkFirst`
- If you want instant UI feedback with background sync, use `RequestPolicy.cacheFirst`
- If you want resilient offline-first behavior (old default), continue using `RequestPolicy.cacheAndNetwork`

## 0.2.1

Exclude certain API paths from caching in `send` method

- Add a list of non-cacheable path segments to exclude specific API endpoints from being cached.
- Modify the send method to bypass cache if the request path contains any of these segments.

This prevents caching sensitive or system data like backups, settings, and logs.

## 0.2.0

Refactor file download methods to use consistent getFileData & Implement auto-generation of file token

- Change token parameter from bool to String?
- Add autoGenerateToken parameter to automatically generate tokens when needed
- Refactor file download methods to use consistent getFileData API across platforms
- Improve file service architecture to better handle token-based file downloads

## 0.1.2

* Update Documentation.

## 0.1.1

* Resolve pub.dev score issues e.g outdated plugin dependencies.

## 0.1.0

*   **Initial release.**

This is the first version of `pocketbase_drift`, a powerful offline-first client for the PocketBase backend, built on top of the reactive persistence library [Drift](https://drift.simonbinder.eu).

### Features

*   **Offline-First Architecture**: Read, create, update, and delete records even without a network connection. The client seamlessly uses the local database as the source of truth.
*   **Automatic Synchronization**: Changes made while offline are automatically queued and retried when network connectivity is restored.
*   **Reactive Data & UI**: Build reactive user interfaces with streams that automatically update when underlying data changes, whether from a server push or a local mutation.
*   **Local Caching with Drift**: All collections and records are cached in a local SQLite database, providing fast, offline access to your data.
*   **Powerful Local Querying**: Full support for local querying, mirroring the PocketBase API. This includes:
    *   **Filtering**: Complex `filter` strings are parsed into SQLite `WHERE` clauses.
    *   **Sorting**: Sort results by any field with `sort` (e.g., `-created,name`).
    *   **Field Selection**: Limit the returned fields with `fields` for improved performance.
    *   **Pagination**: `limit` and `offset` are fully supported for local data.
*   **Relation Expansion**: Support for expanding single and multi-level relations (e.g., `post.author`) directly from the local cache.
*   **Full-Text Search**: Integrated Full-Text Search (FTS5) for performing fast, local searches across all your cached record data.
*   **Authentication Persistence**: User and admin authentication state is persisted locally using `shared_preferences`, keeping users logged in across app sessions.
*   **Cross-Platform Support**: Works across all Flutter-supported platforms, including mobile (iOS, Android), web, and desktop (macOS, Windows, Linux).
*   **Basic File & Image Caching**: Includes a `PocketBaseImageProvider` that caches images in the local database for offline display.
*   **Custom API Route Caching**: Added support for offline caching of custom API routes accessed via the `send` method. This allows `GET` requests to custom endpoints to be cached and available offline, improving performance and reliability for custom integrations.
*   **Robust & Performant**: Includes optimizations for batching queries and file streaming on all platforms to handle large files efficiently.

### Improvements

*   Improved maintainability by refactoring the large `create` and `update` methods in the internal `ServiceMixin` into smaller, more manageable helper methods.
*   Improved web performance by switching from a full `http.get()` to a streaming download for file fetching, aligning it with the more memory-efficient native implementation.