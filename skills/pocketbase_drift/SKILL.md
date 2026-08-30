---
name: pocketbase-drift
description: Offline-first data architecture using pocketbase_drift with Drift SQLite and Riverpod in Flutter. Covers caching request policies, reactive streams, sync engines, relations, files, and FTS5 search.
license: MIT
---

# PocketBase Drift Sync Playbook

Architecture guide and operational playbook for building **offline-first Flutter apps** backed by PocketBase using the `pocketbase_drift` client and Drift SQLite.

## Core Philosophy & Strategy

1. **Local-First Reads:** The UI always queries and listens to local Drift streams (`watchRecords`) for instant rendering and offline availability.
2. **5 Request Policies:**
   - `cacheFirst`: Serve local cache immediately; fetch remote only if missing.
   - `networkFirst`: Try remote first; fallback to local cache if network fails.
   - `cacheAndNetwork`: Yield local cache immediately, fetch remote in background, update cache, and re-emit.
   - `cacheOnly`: Offline-only query.
   - `networkOnly`: Bypass local database cache completely.
3. **Pending Mutation Queue:** Offline mutations (`create`, `update`, `delete`) write locally with a pending status and sync to the server when connectivity resumes.
4. **Riverpod Stream Providers:** Expose reactive queries as `StreamProvider.autoDispose` for automatic lifecycle management and clean UI binding.

## Reference Index

Detailed implementation guides are located in `references/`:

| Guide | Scope & Focus |
|---|---|
| `references/setup.md` | Dependency installation, Drift database setup, schema caching. |
| `references/request-policies.md` | Detailed breakdown and selection guide for the 5 request policies. |
| `references/crud-operations.md` | Offline-safe record creation, updates, deletes, and bulk operations. |
| `references/reactive-streams.md` | `watchRecords` and `watchRecord` stream query patterns. |
| `references/riverpod-integration.md` | Wrapping PocketBase Drift operations in Riverpod providers. |
| `references/sync.md` | Sync queue mechanics, background sync, conflict resolution, retry engine. |
| `references/relations.md` | Relation expansion (`expand`), nested relation caching, and foreign keys. |
| `references/files.md` | Handling file uploads, caching images with `PocketBaseImageProvider`. |
| `references/search.md` | Full-text search (FTS5) queries and local indexing. |
| `references/direct-sql.md` | Raw SQL queries, joins, and custom Drift DAOs. |
| `references/maintenance.md` | Cache TTL management, database pruning, and diagnostic checks. |
| `references/advanced-patterns.md` | Complex multi-collection transactions and custom sync hooks. |
