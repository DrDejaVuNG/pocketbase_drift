# Files

This guide covers file handling, caching, and the PocketBaseImageProvider.

## Overview

pocketbase_drift automatically caches files for offline access:
- Files are stored as blobs in the local SQLite database
- Cached files are available when offline
- File caching works with create, update, and fetch operations

## Uploading Files

### Create with File

```dart
import 'package:http/http.dart' as http;

// From bytes
Future<RecordModel> createPostWithImage(Uint8List imageBytes) async {
  final file = http.MultipartFile.fromBytes(
    'image', // Field name in PocketBase schema
    imageBytes,
    filename: 'photo.jpg',
  );

  return client.collection('posts').create(
    body: {'title': 'Post with Image'},
    files: [file],
    requestPolicy: RequestPolicy.cacheAndNetwork,
  );
}
```

### From File Picker

```dart
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

Future<void> pickAndUpload() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  if (result == null) return;

  final file = result.files.first;
  final bytes = file.bytes!;

  final multipartFile = http.MultipartFile.fromBytes(
    'image',
    bytes,
    filename: file.name,
  );

  await client.collection('posts').create(
    body: {'title': 'Uploaded Image'},
    files: [multipartFile],
    requestPolicy: RequestPolicy.cacheAndNetwork,
  );
}
```

### Multiple Files

```dart
final files = [
  http.MultipartFile.fromBytes('images', bytes1, filename: 'image1.jpg'),
  http.MultipartFile.fromBytes('images', bytes2, filename: 'image2.jpg'),
];

await client.collection('gallery').create(
  body: {'title': 'Gallery'},
  files: files,
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

## Update with File

```dart
await client.collection('posts').update(
  postId,
  body: {'title': 'Updated Post'},
  files: [newImageFile],
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

## PocketBaseImageProvider

Display cached images with automatic offline support:

```dart
import 'package:pocketbase_drift/pocketbase_drift.dart';

Image(
  image: PocketBaseImageProvider(
    client: client,
    recordId: record.id,
    recordCollectionName: record.collectionName,
    filename: record.get<String>('image')!,
  ),
  width: 200,
  height: 150,
  fit: BoxFit.cover,
)
```

### With Placeholder and Error Handling

```dart
Image(
  image: PocketBaseImageProvider(
    client: client,
    recordId: post.id,
    recordCollectionName: post.collectionName,
    filename: post.get<String>('cover_image')!,
  ),
  width: double.infinity,
  height: 200,
  fit: BoxFit.cover,
  loadingBuilder: (context, child, loadingProgress) {
    if (loadingProgress == null) return child;
    return Center(
      child: CircularProgressIndicator(
        value: loadingProgress.expectedTotalBytes != null
          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
          : null,
      ),
    );
  },
  errorBuilder: (context, error, stackTrace) {
    return Container(
      color: Colors.grey[300],
      child: const Icon(Icons.broken_image),
    );
  },
)
```

### With Thumbnail

For performance, use thumbnail parameter:

```dart
Image(
  image: PocketBaseImageProvider(
    client: client,
    recordId: record.id,
    recordCollectionName: record.collectionName,
    filename: record.get<String>('image')!,
    thumb: '200x200', // Request thumbnail from server
  ),
)
```

## Get File Bytes Directly

```dart
final bytes = await client.files.getFileBytes(
  recordId: postRecord.id,
  recordCollectionName: postRecord.collectionName,
  fileName: postRecord.get<String>('document')!,
  requestPolicy: RequestPolicy.cacheAndNetwork,
);

// Use bytes (e.g., save to file, display PDF, etc.)
```

## Get File URL

For direct URL access (network only):

```dart
final url = client.files.getUrl(
  record,
  record.get<String>('image')!,
);
// Returns: https://your-pb.com/api/files/collection/recordId/filename.jpg
```

## Reusable Image Widget

Create a wrapper for consistent usage:

```dart
class PbImage extends StatelessWidget {
  const PbImage({
    super.key,
    required this.record,
    required this.field,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.thumb,
  });

  final RecordModel record;
  final String field;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? thumb;

  @override
  Widget build(BuildContext context) {
    final filename = record.get<String>(field);
    if (filename == null || filename.isEmpty) {
      return _placeholder();
    }

    final client = ProviderScope.containerOf(context).read(pocketbaseProvider);

    return Image(
      image: PocketBaseImageProvider(
        client: client,
        recordId: record.id,
        recordCollectionName: record.collectionName,
        filename: filename,
        thumb: thumb,
      ),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Icon(Icons.image_not_supported),
    );
  }
}

// Usage
PbImage(
  record: post,
  field: 'cover_image',
  width: double.infinity,
  height: 200,
  thumb: '400x0', // Width 400, auto height
)
```

## Offline File Behavior

### Create with Files (Offline)

When creating a record with files while offline:
1. Files are cached locally with original filenames
2. Record is created with `synced: false, isNew: true`
3. When online, record syncs with files
4. Server may rename files (adds unique suffix)
5. Cache updates with server filenames

### Cached File Retrieval

```dart
// This works offline if the file was previously fetched
final bytes = await client.files.getFileBytes(
  recordId: recordId,
  recordCollectionName: 'posts',
  fileName: 'image.jpg',
  requestPolicy: RequestPolicy.cacheFirst, // Try cache first
);
```

## Multi-File Fields

For fields that allow multiple files:

```dart
// Get list of filenames
final images = record.get<List<String>>('images') ?? [];

// Display all images
for (final filename in images) {
  Image(
    image: PocketBaseImageProvider(
      client: client,
      recordId: record.id,
      recordCollectionName: record.collectionName,
      filename: filename,
    ),
  );
}
```

## File Deletion

Removing files during update:

```dart
// Remove specific file (PocketBase syntax)
await client.collection('posts').update(
  postId,
  body: {
    'images-': ['old_image.jpg'], // Remove this file
  },
);

// Replace file
await client.collection('posts').update(
  postId,
  files: [newImageFile], // Replaces if single-file field
);
```

## File Cache Cleanup

File blobs are cleaned up during maintenance:

```dart
final result = await client.runMaintenance();
print('Cleaned ${result.deletedFiles} expired file blobs');
```
