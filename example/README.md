# TaskFlow — PocketBase Drift Example Application

A modern, production-grade reference application demonstrating how to build **offline-first Flutter apps** backed by PocketBase using the `pocketbase_drift` client and Drift SQLite.

---

## 🌟 What This Example Demonstrates

1. **Client Initialization & Schema Caching (`setSchema`)**
   - Initializes `$PocketBase.database` with persistent `$AuthStore.prefs`.
   - Caches schema definitions from `assets/pb_schema.json` via `client.setSchema(...)` on startup for immediate offline operation.

2. **5 Request Policies in Action**
   - **`cacheAndNetwork` (Default):** Serves cached local SQLite data instantly, fetches updates from the remote PocketBase server in the background, updates SQLite, and re-emits.
   - **`cacheFirst`:** Serves local cache immediately. Only queries remote if local cache is empty.
   - **`networkFirst`:** Tries remote PocketBase server first, falling back to local SQLite cache if offline.
   - **`cacheOnly`:** Reads strictly from local SQLite, bypassing network requests entirely.
   - **`networkOnly`:** Bypasses local database completely.

3. **Reactive Streams & `QueryState<T>`**
   - Uses `watchRecordsState` and `watchRecordState` with `QueryState<T>` in Riverpod `StreamProvider`s.
   - Eliminates empty-screen flickering on startup while providing `isFetchingNetwork` and `error` indicators to UI widgets.

4. **Local-First Mutations & Sync Queue Diagnostics**
   - Creating, editing, and deleting records writes to local Drift SQLite immediately.
   - Live **Sync Diagnostics** tab inspects pending unsynced mutations and supports manual sync triggers.

5. **Relation Expansion & Full-Text Search**
   - Demonstrates local and remote relation expansion (`expand: 'project'`).
   - Local database search filtering across tasks and projects without network round-trips.

---

## 🚀 Running the Example

### 1. Instant Offline Exploration (No Backend Required)
You can run the example app immediately out-of-the-box. If no PocketBase server is connected, the app automatically seeds sample projects and tasks into local Drift SQLite:

```bash
flutter run
```

### 2. Connected with Live PocketBase Server (Optional)
To connect to a live PocketBase instance:
1. Start PocketBase:
   ```bash
   ./pocketbase serve --http=127.0.0.1:8090
   ```
2. Import `example/assets/pb_schema.json` in PocketBase Admin UI (**Settings → Import collections**).
3. Run the Flutter app:
   ```bash
   flutter run --dart-define=POCKETBASE_URL=http://127.0.0.1:8090
   ```

---

## 📂 Project Architecture

```
lib/
├── core/
│   ├── constants/        # App-wide constants and collection names
│   ├── router/           # GoRouter setup with bottom navigation tabs
│   └── theme/            # Material 3 light/dark themes
├── features/
│   ├── tasks/            # Tasks domain (models, repository, providers, UI)
│   ├── projects/         # Projects domain (relations demonstration)
│   ├── sync/             # Sync diagnostics & pending mutation inspector
│   └── search/           # Instant local SQLite search
├── shared/
│   ├── providers/        # pocketBaseProvider, sharedPreferencesProvider
│   ├── utils/            # Seed data helper for empty databases
│   └── widgets/          # EmptyState, ErrorView, FetchingIndicator, OfflineBanner
└── main.dart             # Parallel async startup & ProviderScope setup
```
