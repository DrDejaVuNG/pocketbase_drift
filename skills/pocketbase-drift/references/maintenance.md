# Maintenance

This guide covers cache cleanup, TTL configuration, and database maintenance.

## Cache TTL

By default, cached data expires after 60 days. Configure on initialization:

```dart
final client = $PocketBase.database(
  'https://example.pocketbase.io',
  cacheTtl: Duration(days: 30), // Custom TTL
);
```

## Running Maintenance

Call `runMaintenance()` to clean up expired data:

```dart
// Run with configured TTL
final result = await client.runMaintenance();
print('Cleaned up ${result.totalDeleted} expired items');

// Run with one-time custom TTL
await client.runMaintenance(ttl: Duration(days: 7));
```

## MaintenanceResult

The result provides counts of what was cleaned:

```dart
final result = await client.runMaintenance();

print('Deleted records: ${result.deletedRecords}');
print('Deleted responses: ${result.deletedResponses}');
print('Deleted files: ${result.deletedFiles}');
print('Total deleted: ${result.totalDeleted}');
```

| Property | Description |
|----------|-------------|
| `deletedRecords` | Expired synced records removed |
| `deletedResponses` | Expired cached API responses removed |
| `deletedFiles` | Expired file blobs removed |
| `totalDeleted` | Sum of all deletions |

## What Gets Cleaned

Maintenance **ONLY** deletes:
- Synced records older than TTL (`synced: true` + `updated` < cutoff)
- Cached API responses older than TTL
- Orphaned file blobs

Maintenance **NEVER** deletes:
- Unsynced local changes (`synced: false`)
- Local-only records (`noSync: true`)
- Pending deletions (`deleted: true, synced: false`)

**You will never lose unsynced data during maintenance.**

## When to Run Maintenance

### On App Startup

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final client = $PocketBase.database('https://example.com');
  
  // Run maintenance in background after app starts
  Future.microtask(() async {
    final result = await client.runMaintenance();
    if (result.totalDeleted > 0) {
      Logger.info('Cleaned ${result.totalDeleted} expired cache items');
    }
  });

  runApp(MyApp(client: client));
}
```

### Periodically

```dart
// Run weekly or when user triggers
class SettingsScreen extends ConsumerWidget {
  Future<void> _clearOldCache(WidgetRef ref) async {
    final client = ref.read(pocketbaseProvider);
    final result = await client.runMaintenance(ttl: Duration(days: 7));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cleaned ${result.totalDeleted} items')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        ListTile(
          title: const Text('Clear Old Cache'),
          subtitle: const Text('Remove data older than 7 days'),
          trailing: const Icon(Icons.cleaning_services),
          onTap: () => _clearOldCache(ref),
        ),
      ],
    );
  }
}
```

## Manual Cache Clearing

### Clear All Data

```dart
// Clear absolutely everything (use with caution!)
await client.db.clearAllData();
```

**Warning**: This deletes ALL cached data including unsynced changes.

### Clear Specific Collection

```dart
// Delete all cached records in a collection
await client.db.customStatement(
  "DELETE FROM services WHERE service = ?",
  ['temp_data'],
);
```

### Clear Old Records Manually

```dart
// Delete synced posts older than 30 days
final cutoff = DateTime.now().subtract(Duration(days: 30)).toIso8601String();

await client.db.customStatement('''
  DELETE FROM services 
  WHERE service = 'posts'
    AND json_extract(data, '\$.synced') = 1
    AND updated < ?
''', [cutoff]);
```

## Database Size

Check cache size:

```dart
// Count records per collection
final counts = await client.db.customSelect('''
  SELECT service, COUNT(*) as count
  FROM services
  GROUP BY service
''').get();

for (final row in counts) {
  print('${row.read<String>('service')}: ${row.read<int>('count')} records');
}

// Count file blobs
final fileCount = await client.db.customSelect(
  "SELECT COUNT(*) as count FROM blob_files",
).getSingle();
print('Cached files: ${fileCount.read<int>('count')}');
```

## Cache Strategies by Data Type

### Frequently Updated Data

Use shorter TTL or more aggressive maintenance:

```dart
// Clear feed items weekly
await client.runMaintenance(ttl: Duration(days: 7));
```

### Critical Data

Keep longer, ensure synced before cleaning:

```dart
// Ensure sync is complete before maintenance
await client.syncCompleted;
await client.runMaintenance();
```

### Large Files

Monitor file cache specifically:

```dart
// Clear old files
await client.db.customStatement('''
  DELETE FROM blob_files 
  WHERE created < datetime('now', '-30 days')
''');
```

## Riverpod Provider for Maintenance

```dart
// Maintenance provider
final maintenanceResultProvider = FutureProvider<MaintenanceResult?>((ref) async {
  final client = ref.watch(pocketbaseProvider);
  
  // Only run once per app session
  final ran = ref.state.valueOrNull != null;
  if (ran) return ref.state.valueOrNull;
  
  return client.runMaintenance();
});

// Use in startup widget
class AppStartup extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trigger maintenance on startup
    ref.watch(maintenanceResultProvider);
    
    return const MyApp();
  }
}
```

## Best Practices

1. **Run maintenance on startup** - Clean old data when app launches
2. **Don't run too frequently** - Once per session is usually enough
3. **Use appropriate TTL** - Balance between freshness and storage
4. **Monitor cache growth** - For apps with lots of data, track size over time
5. **Inform users** - Let users manually clear cache if needed
6. **Ensure sync first** - For critical cleanup, wait for sync completion
