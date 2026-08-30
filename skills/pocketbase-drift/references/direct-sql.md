# Direct SQL

This guide covers accessing the Drift database directly for custom queries.

## Database Access

Access the underlying Drift database via `client.db`:

```dart
final db = client.db;
```

## Database Schema

All PocketBase records are stored in a generic `services` table:

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT | Record ID (PocketBase ID) |
| `service` | TEXT | Collection name (e.g., "posts", "users") |
| `data` | TEXT | JSON-encoded record data |
| `created` | TEXT | ISO 8601 timestamp |
| `updated` | TEXT | ISO 8601 timestamp |

**Primary Key**: `(id, service)`

Additional tables:
- `blob_files` - Cached file/image blobs
- `cached_responses` - Cached API responses for custom routes

## Custom Select Queries

### Simple Query

```dart
final results = await client.db.customSelect(
  "SELECT * FROM services WHERE service = 'posts'",
).get();

for (final row in results) {
  final id = row.read<String>('id');
  final dataJson = row.read<String>('data');
  print('Post $id: $dataJson');
}
```

### Query with JSON Extraction

SQLite's `json_extract` function accesses JSON fields:

```dart
final posts = await client.db.customSelect('''
  SELECT 
    id,
    json_extract(data, '\$.title') as title,
    json_extract(data, '\$.author') as author,
    created
  FROM services 
  WHERE service = 'posts'
    AND json_extract(data, '\$.published') = 1
  ORDER BY created DESC
  LIMIT 10
''').get();

for (final row in posts) {
  final title = row.read<String>('title');
  final author = row.read<String>('author');
  print('$title by $author');
}
```

## Joining Data Across Collections

Since all collections share the same table, use self-joins:

```dart
final results = await client.db.customSelect('''
  SELECT 
    p.id as post_id,
    json_extract(p.data, '\$.title') as post_title,
    json_extract(u.data, '\$.name') as author_name,
    json_extract(u.data, '\$.email') as author_email
  FROM services p
  JOIN services u 
    ON json_extract(p.data, '\$.author') = u.id 
    AND u.service = 'users'
  WHERE p.service = 'posts'
  ORDER BY p.created DESC
''').get();

for (final row in results) {
  final title = row.read<String>('post_title');
  final author = row.read<String>('author_name');
  print('$title by $author');
}
```

## Reactive Streams

Use `.watch()` instead of `.get()` for reactive updates:

```dart
final stream = client.db.customSelect(
  "SELECT * FROM services WHERE service = 'posts'",
  readsFrom: {client.db.services}, // Required for reactivity
).watch();

stream.listen((rows) {
  print('Posts updated: ${rows.length} items');
});
```

## Execute Statements

For INSERT, UPDATE, DELETE operations:

```dart
// Delete all temp data
await client.db.customStatement(
  "DELETE FROM services WHERE service = 'temp_data'",
);

// Update field
await client.db.customStatement('''
  UPDATE services 
  SET data = json_set(data, '\$.viewed', true)
  WHERE service = 'posts' AND id = ?
''', ['POST_ID']);
```

## Built-in Query Builder

For PocketBase-style queries without raw SQL:

```dart
// Uses PocketBase filter syntax internally
final posts = await client.db.$query(
  'posts',
  filter: "published = true && author != ''",
  sort: '-created',
  limit: 10,
).get();

// With expansion
final posts = await client.db.$query(
  'posts',
  filter: "published = true",
  expand: 'author',
  sort: '-created',
).get();
```

## Aggregations

```dart
// Count records
final countResult = await client.db.customSelect(
  "SELECT COUNT(*) as count FROM services WHERE service = 'posts'",
).getSingle();
final count = countResult.read<int>('count');

// Sum values
final sumResult = await client.db.customSelect('''
  SELECT SUM(json_extract(data, '\$.price')) as total
  FROM services 
  WHERE service = 'products'
''').getSingle();
final total = sumResult.read<double>('total');

// Group by
final grouped = await client.db.customSelect('''
  SELECT 
    json_extract(data, '\$.category') as category,
    COUNT(*) as count
  FROM services
  WHERE service = 'products'
  GROUP BY json_extract(data, '\$.category')
''').get();
```

## Full-Text Search Table

FTS5 search uses a separate virtual table:

```dart
// Search using FTS5
final results = await client.db.customSelect('''
  SELECT s.* 
  FROM services s
  JOIN services_fts fts ON s.rowid = fts.rowid
  WHERE services_fts MATCH 'flutter'
    AND s.service = 'posts'
''').get();
```

## Transactions

```dart
await client.db.transaction(() async {
  await client.db.customStatement(
    "UPDATE services SET data = json_set(data, '\$.status', 'processing') WHERE id = ?",
    [orderId],
  );
  
  await client.db.customStatement(
    "INSERT INTO services (id, service, data) VALUES (?, 'logs', ?)",
    [newId(), '{"action": "order_processed"}'],
  );
});
```

## Inspecting Tables

```dart
// List all services (collections) in cache
final services = await client.db.customSelect(
  "SELECT DISTINCT service FROM services",
).get();

for (final row in services) {
  print('Collection: ${row.read<String>('service')}');
}

// Count records per collection
final counts = await client.db.customSelect('''
  SELECT service, COUNT(*) as count
  FROM services
  GROUP BY service
''').get();
```

## Example: Dashboard Stats

```dart
Future<DashboardStats> getDashboardStats() async {
  final results = await client.db.customSelect('''
    SELECT
      (SELECT COUNT(*) FROM services WHERE service = 'posts') as post_count,
      (SELECT COUNT(*) FROM services WHERE service = 'users') as user_count,
      (SELECT COUNT(*) FROM services WHERE service = 'posts' 
       AND json_extract(data, '\$.published') = 1) as published_count,
      (SELECT COUNT(*) FROM services 
       WHERE json_extract(data, '\$.synced') = 0) as pending_sync_count
  ''').getSingle();

  return DashboardStats(
    postCount: results.read<int>('post_count'),
    userCount: results.read<int>('user_count'),
    publishedCount: results.read<int>('published_count'),
    pendingSyncCount: results.read<int>('pending_sync_count'),
  );
}
```

## Performance Tips

### Use Indexes

The `services` table is indexed on `(id, service)`. For frequent JSON queries, consider:

```dart
// This is fast (uses index)
await client.db.$query('posts', filter: "id = 'abc123'").get();

// This is slower (scans table)
await client.db.customSelect('''
  SELECT * FROM services 
  WHERE json_extract(data, '\$.author') = 'user123'
''').get();
```

### Limit Results

```dart
// Always limit when possible
final recent = await client.db.customSelect('''
  SELECT * FROM services 
  WHERE service = 'posts'
  ORDER BY created DESC
  LIMIT 20
''').get();
```

### Use Parameters

```dart
// ✅ Safe from SQL injection
await client.db.customSelect(
  "SELECT * FROM services WHERE service = ? AND id = ?",
  variables: [Variable('posts'), Variable(postId)],
).get();

// ❌ Vulnerable to injection
await client.db.customSelect(
  "SELECT * FROM services WHERE id = '$postId'", // DON'T DO THIS
).get();
```
