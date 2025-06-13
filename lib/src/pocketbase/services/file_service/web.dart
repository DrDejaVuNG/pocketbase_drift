// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../../pocketbase_drift.dart';

class $FileService extends FileService {
  $FileService(this.client) : super(client);

  @override
  final $PocketBase client;

  /// Gets file data, respecting the specified [RequestPolicy].
  ///
  /// This method centralizes the cache-or-network logic for files.
  Future<Uint8List> get(
    RecordModel record,
    String filename, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Duration? expireAfter,
  }) async {
    if (requestPolicy.isCache) {
      final cached =
          await client.db.getFile(record.id, filename).getSingleOrNull();
      final now = DateTime.now();
      bool needsUpdate = cached == null;
      if (cached != null &&
          cached.expiration != null &&
          cached.expiration!.isBefore(now)) {
        client.logger.fine('Cached file expired, re-downloading: $filename');
        needsUpdate = true;
      }

      if (!needsUpdate) {
        return cached!.data;
      }
    }

    if (requestPolicy.isNetwork) {
      final bytes = await getFileBytes(record, filename);
      // Save to cache after a successful network download if policy allows
      if (requestPolicy.isCache) {
        await client.db.setFile(record.id, filename, bytes,
            expires:
                expireAfter != null ? DateTime.now().add(expireAfter) : null);
      }
      return bytes;
    }

    throw Exception(
        'Could not get file "$filename" with policy "$requestPolicy"');
  }

  /// Downloads a file using a streaming approach to improve performance for
  /// larger files compared to loading the entire file into memory at once.
  Future<Uint8List> getFileBytes(
    RecordModel record,
    String filename, {
    String? thumb,
  }) async {
    final url = getUrl(record, filename, thumb: thumb);

    final httpClient = client.httpClientFactory();
    final request = http.Request('GET', url);
    final streamedResponse = await httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      throw ClientException(
        url: url,
        response: {
          'message':
              'Failed to download file. Status code: ${streamedResponse.statusCode}'
        },
      );
    }

    return streamedResponse.stream.toBytes();
  }
}
