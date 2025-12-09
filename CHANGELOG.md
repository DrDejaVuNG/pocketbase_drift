## 0.3.3

- **Added partial update support with validation for offline scenarios** - Partial updates are now supported for offline scenarios, with validation to ensure that the update is valid before it is applied.
- **Fixed SQLite quote semantics issue** - Resolved an issue where SQLite quote semantics were not being handled correctly, which could cause errors when using double quotes inside query filters.

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