# Setup

This guide covers installing and configuring pocketbase_drift.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  pocketbase_drift: ^0.4.4  # Use latest version

## Initialize the Client

Replace standard PocketBase client with `$PocketBase.database`:

```dart
import 'package:pocketbase_drift/pocketbase_drift.dart';

// Simple initialization
final client = $PocketBase.database('http://127.0.0.1:8090');

// With options
final client = $PocketBase.database(
  'http://127.0.0.1:8090',
  dbName: 'my_app.db',           // Custom database filename
  inMemory: false,                // Use persistent storage
  cacheTtl: Duration(days: 60),   // Cache expiration
);
```

## Cache the Schema

To enable offline record functionality, cache your schema:

### 1. Export Schema from PocketBase

Go to PocketBase Admin UI → Settings → Export collections → Download `pb_schema.json`

### 2. Add to Assets

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/pb_schema.json
```

### 3. Cache on Startup

```dart
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load schema
  final schema = await rootBundle.loadString('assets/pb_schema.json');
  
  // Initialize client and cache schema
  final client = $PocketBase.database('http://127.0.0.1:8090')
    ..setSchema(schema);
  runApp(MyApp(client: client));
}
```

## Authentication Store

Use `$AuthStore` for persistent authentication:

```dart
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  
  // Create persistent auth store
  final authStore = $AuthStore.prefs(prefs, 'pb_auth');
  
  // Initialize client with auth store
  final client = $PocketBase.database(
    'http://127.0.0.1:8090',
    authStore: authStore,
  );
  
  // Load schema
  final schema = await rootBundle.loadString('assets/pb_schema.json');
  client.setSchema(schema);
  runApp(MyApp(client: client));
}
```

## Web Setup

For web platform, you need Drift's WASM files:

### 1. Download Required Files

- `sqlite3.wasm` from [sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases)
- `drift_worker.js` from [drift releases](https://github.com/simolus3/drift/releases)

### 2. Add to Web Directory

```
web/
├── drift_worker.js
├── sqlite3.wasm
└── index.html
```

### 3. Verify

The app will automatically use the web-compatible database on web platform.

## Riverpod Integration

Set up providers for dependency injection:

```dart
// lib/shared/providers/pocketbase_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SharedPreferences provider (override in main)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main.dart');
});

// Schema provider (override in main)
final schemaProvider = Provider<String>((ref) {
  throw UnimplementedError('Override in main.dart');
});

// PocketBase client provider
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

### Main.dart with Riverpod

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load dependencies in parallel
  final startupValues = await Future.wait([
    SharedPreferences.getInstance(),
    rootBundle.loadString('assets/pb_schema.json'),
  ]);
  
  final sharedPreferences = startupValues[0] as SharedPreferences;
  final schemaJson = startupValues[1] as String;

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        schemaProvider.overrideWithValue(schemaJson),
      ],
      child: const MyApp(),
    ),
  );
}
```

## Enable Logging

For debugging, enable the client logger:

```dart
final client = $PocketBase.database('http://127.0.0.1:8090');
client.logging = true; // Enables detailed logging

// Log levels include:
// - INFO: Sync events, connectivity changes
// - FINE: Individual operations
// - WARNING: Recoverable errors
// - SEVERE: Critical errors
```

## Configuration Summary

| Option | Default | Description |
|--------|---------|-------------|
| `baseUrl` | Required | PocketBase server URL |
| `dbName` | `'pb_drift.db'` | SQLite database filename |
| `inMemory` | `false` | Use in-memory database (for tests) |
| `cacheTtl` | `60 days` | Cache expiration for maintenance |
| `authStore` | Auto-created | Custom auth store for persistence |
| `httpClientFactory` | Default | Custom HTTP client factory |
