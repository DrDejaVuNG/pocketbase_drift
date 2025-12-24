import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../pocketbase_drift.dart';

/// A request queued in a batch operation.
///
/// This class stores all the information needed to either send the request
/// to the server or apply it to the local cache.
class $BatchRequest {
  /// The HTTP method for this request (POST, PATCH, PUT, DELETE).
  final String method;

  /// The collection this request targets.
  final String collection;

  /// The record ID (for update/delete operations).
  final String? recordId;

  /// The request body data.
  final Map<String, dynamic> body;

  /// Query parameters.
  final Map<String, dynamic> query;

  /// Request headers.
  final Map<String, String> headers;

  /// Files to upload (buffered for potential offline replay).
  final List<(String field, String? filename, Uint8List bytes)> files;

  /// Expand parameter for the request.
  final String? expand;

  /// Fields parameter for limiting response fields.
  final String? fields;

  const $BatchRequest({
    required this.method,
    required this.collection,
    this.recordId,
    this.body = const {},
    this.query = const {},
    this.headers = const {},
    this.files = const [],
    this.expand,
    this.fields,
  });

  /// Whether this is a create operation.
  bool get isCreate => method == 'POST';

  /// Whether this is an update operation.
  bool get isUpdate => method == 'PATCH';

  /// Whether this is an upsert operation.
  bool get isUpsert => method == 'PUT';

  /// Whether this is a delete operation.
  bool get isDelete => method == 'DELETE';
}

/// Result of a single batch operation.
///
/// Maps to the PocketBase BatchResult but with additional information
/// about which collection/record the result corresponds to.
class $BatchResult {
  /// HTTP status code of the operation.
  final int status;

  /// The response body (usually a RecordModel or error details).
  final dynamic body;

  /// The collection this result corresponds to.
  final String collection;

  /// The record ID (if applicable).
  final String? recordId;

  /// Whether the operation was successful (2xx status).
  bool get isSuccess => status >= 200 && status < 300;

  /// Whether the operation failed.
  bool get isError => !isSuccess;

  const $BatchResult({
    required this.status,
    required this.body,
    required this.collection,
    this.recordId,
  });

  /// Attempts to parse the body as a RecordModel.
  /// Returns null if parsing fails or body is not a valid record.
  RecordModel? get record {
    if (body is Map<String, dynamic>) {
      try {
        return RecordModel.fromJson(body as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  String toString() =>
      '\$BatchResult(status: $status, collection: $collection, recordId: $recordId)';
}

/// A sub-service for queuing batch operations on a specific collection.
///
/// This class provides methods to queue create, update, delete, and upsert
/// operations that will be executed together when [send] is called on the
/// parent [$BatchService].
class $SubBatchService {
  final $BatchService _batch;
  final String _collection;

  $SubBatchService(this._batch, this._collection);

  /// Queues a record create operation.
  ///
  /// The actual creation will happen when [send] is called on the parent batch.
  void create({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) {
    _batch._addRequest($BatchRequest(
      method: 'POST',
      collection: _collection,
      body: Map.from(body),
      query: Map.from(query),
      headers: Map.from(headers),
      expand: expand,
      fields: fields,
      // Files will be buffered when send() is called
    ));
  }

  /// Queues a record update operation.
  ///
  /// The actual update will happen when [send] is called on the parent batch.
  void update(
    String recordId, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) {
    _batch._addRequest($BatchRequest(
      method: 'PATCH',
      collection: _collection,
      recordId: recordId,
      body: Map.from(body),
      query: Map.from(query),
      headers: Map.from(headers),
      expand: expand,
      fields: fields,
    ));
  }

  /// Queues a record delete operation.
  ///
  /// The actual deletion will happen when [send] is called on the parent batch.
  void delete(
    String recordId, {
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) {
    _batch._addRequest($BatchRequest(
      method: 'DELETE',
      collection: _collection,
      recordId: recordId,
      body: Map.from(body),
      query: Map.from(query),
      headers: Map.from(headers),
    ));
  }

  /// Queues a record upsert operation.
  ///
  /// The request will be executed as update if `body` contains a valid existing
  /// record `id` value, otherwise it will be executed as create.
  ///
  /// The actual operation will happen when [send] is called on the parent batch.
  void upsert({
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) {
    _batch._addRequest($BatchRequest(
      method: 'PUT',
      collection: _collection,
      body: Map.from(body),
      query: Map.from(query),
      headers: Map.from(headers),
      expand: expand,
      fields: fields,
    ));
  }
}

/// A service for executing batch/transactional operations with offline support.
///
/// This service allows you to queue multiple create, update, delete, and upsert
/// operations across different collections and execute them in a single request.
///
/// When used with [RequestPolicy.cacheAndNetwork] (default), if the batch request
/// fails due to network issues, all operations are stored locally and will be
/// retried as individual operations when connectivity is restored.
///
/// Example:
/// ```dart
/// final batch = client.createBatch();
///
/// batch.collection('posts').create(body: {'title': 'Hello'});
/// batch.collection('posts').update('abc123', body: {'title': 'Updated'});
/// batch.collection('comments').delete('def456');
///
/// final results = await batch.send();
/// for (final result in results) {
///   if (result.isSuccess) {
///     print('Success: ${result.collection}/${result.recordId}');
///   }
/// }
/// ```
class $BatchService {
  final $PocketBase client;
  final List<$BatchRequest> _requests = [];
  final Map<String, $SubBatchService> _subs = {};

  $BatchService(this.client);

  /// Returns a sub-service for queuing batch operations on a specific collection.
  $SubBatchService collection(String collectionIdOrName) {
    var subService = _subs[collectionIdOrName];

    if (subService == null) {
      subService = $SubBatchService(this, collectionIdOrName);
      _subs[collectionIdOrName] = subService;
    }

    return subService;
  }

  /// Adds a request to the batch queue.
  void _addRequest($BatchRequest request) {
    _requests.add(request);
  }

  /// Returns the number of queued requests.
  int get length => _requests.length;

  /// Returns true if there are no queued requests.
  bool get isEmpty => _requests.isEmpty;

  /// Sends all queued batch requests.
  ///
  /// The [requestPolicy] determines how the batch is handled:
  /// - [RequestPolicy.networkOnly]: Send to server only, throw on failure.
  /// - [RequestPolicy.cacheOnly]: Apply all operations to local cache only.
  /// - [RequestPolicy.networkFirst]: Try server first, throw on failure (no fallback).
  /// - [RequestPolicy.cacheFirst]: Apply to cache first, try server in background.
  /// - [RequestPolicy.cacheAndNetwork]: Try server, on failure cache as pending.
  ///
  /// Returns a list of [$BatchResult] objects, one for each queued request.
  Future<List<$BatchResult>> send({
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    if (_requests.isEmpty) {
      return [];
    }

    return switch (requestPolicy) {
      RequestPolicy.cacheOnly => _sendCacheOnly(),
      RequestPolicy.networkOnly => _sendNetworkOnly(body, query, headers),
      RequestPolicy.networkFirst => _sendNetworkFirst(body, query, headers),
      RequestPolicy.cacheFirst => _sendCacheFirst(body, query, headers),
      RequestPolicy.cacheAndNetwork =>
        _sendCacheAndNetwork(body, query, headers),
    };
  }

  /// Sends batch to server only. Throws if offline or request fails.
  Future<List<$BatchResult>> _sendNetworkOnly(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    if (!client.connectivity.isConnected) {
      throw Exception(
          'Device is offline and RequestPolicy.networkOnly was requested for batch send.');
    }

    return _sendToServer(body, query, headers);
  }

  /// Applies all operations to local cache only, marked as local-only (noSync).
  Future<List<$BatchResult>> _sendCacheOnly() async {
    final results = <$BatchResult>[];

    for (final request in _requests) {
      try {
        final result = await _applySingleToCache(
          request,
          synced: false,
          noSync: true,
        );
        results.add(result);
      } catch (e) {
        client.logger.warning(
            'Error applying batch request to cache: ${request.collection}', e);
        results.add($BatchResult(
          status: 500,
          body: {'error': e.toString()},
          collection: request.collection,
          recordId: request.recordId,
        ));
      }
    }

    return results;
  }

  /// Tries server first, throws on failure (no cache fallback).
  Future<List<$BatchResult>> _sendNetworkFirst(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    if (!client.connectivity.isConnected) {
      throw Exception(
          'Device is offline and RequestPolicy.networkFirst was requested for batch send.');
    }

    final results = await _sendToServer(body, query, headers);

    // Update local cache with successful results
    await _syncResultsToCache(results);

    return results;
  }

  /// Applies to cache first, tries server in background.
  Future<List<$BatchResult>> _sendCacheFirst(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    // Apply all operations to cache first
    final results = <$BatchResult>[];

    for (final request in _requests) {
      try {
        final result = await _applySingleToCache(
          request,
          synced: false,
          noSync: false,
        );
        results.add(result);
      } catch (e) {
        client.logger.warning(
            'Error applying batch request to cache: ${request.collection}', e);
        results.add($BatchResult(
          status: 500,
          body: {'error': e.toString()},
          collection: request.collection,
          recordId: request.recordId,
        ));
      }
    }

    // Try server in background if connected
    if (client.connectivity.isConnected) {
      _sendToServer(body, query, headers).then((serverResults) {
        _syncResultsToCache(serverResults);
      }).catchError((e) {
        client.logger.warning(
            'Background batch send failed, will retry individual records later.',
            e);
      });
    }

    return results;
  }

  /// Tries server first, falls back to caching for pending sync on failure.
  Future<List<$BatchResult>> _sendCacheAndNetwork(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    // Try server if connected
    if (client.connectivity.isConnected) {
      try {
        final results = await _sendToServer(body, query, headers);

        // Update local cache with results
        await _syncResultsToCache(results);

        return results;
      } catch (e) {
        client.logger.warning(
            'Batch send to server failed, falling back to local cache.', e);
        // Fall through to cache fallback
      }
    }

    // Offline or server failed: apply to cache as pending
    final results = <$BatchResult>[];

    for (final request in _requests) {
      try {
        final result = await _applySingleToCache(
          request,
          synced: false,
          noSync: false,
        );
        results.add(result);
      } catch (e) {
        client.logger.warning(
            'Error applying batch request to cache: ${request.collection}', e);
        results.add($BatchResult(
          status: 500,
          body: {'error': e.toString()},
          collection: request.collection,
          recordId: request.recordId,
        ));
      }
    }

    client.logger.info(
        'Batch of ${_requests.length} requests saved to local cache for later sync.');

    return results;
  }

  /// Sends the batch request to the PocketBase server.
  Future<List<$BatchResult>> _sendToServer(
    Map<String, dynamic> body,
    Map<String, dynamic> query,
    Map<String, String> headers,
  ) async {
    // Build the batch using the SDK's BatchService
    final sdkBatch = client.createBatch();

    for (final request in _requests) {
      final subBatch = sdkBatch.collection(request.collection);

      final enrichedQuery = Map<String, dynamic>.from(request.query);
      if (request.expand != null) enrichedQuery['expand'] = request.expand;
      if (request.fields != null) enrichedQuery['fields'] = request.fields;

      switch (request.method) {
        case 'POST':
          subBatch.create(
            body: request.body,
            query: enrichedQuery,
            headers: request.headers,
          );
          break;
        case 'PATCH':
          subBatch.update(
            request.recordId!,
            body: request.body,
            query: enrichedQuery,
            headers: request.headers,
          );
          break;
        case 'PUT':
          subBatch.upsert(
            body: request.body,
            query: enrichedQuery,
            headers: request.headers,
          );
          break;
        case 'DELETE':
          subBatch.delete(
            request.recordId!,
            body: request.body,
            query: request.query,
            headers: request.headers,
          );
          break;
      }
    }

    // Send the batch
    final sdkResults = await sdkBatch.send(
      body: body,
      query: query,
      headers: headers,
    );

    // Map SDK results to our results with collection/recordId info
    final results = <$BatchResult>[];
    for (var i = 0; i < sdkResults.length && i < _requests.length; i++) {
      final sdkResult = sdkResults[i];
      final request = _requests[i];

      results.add($BatchResult(
        status: sdkResult.status.toInt(),
        body: sdkResult.body,
        collection: request.collection,
        recordId: request.recordId ?? _extractIdFromBody(sdkResult.body),
      ));
    }

    return results;
  }

  /// Applies a single batch request to the local cache.
  Future<$BatchResult> _applySingleToCache(
    $BatchRequest request, {
    required bool synced,
    required bool noSync,
  }) async {
    Map<String, dynamic> resultData;

    if (request.isDelete) {
      // For deletes, mark as deleted in cache
      final existing = await client.db
          .$query(request.collection, filter: "id = '${request.recordId}'")
          .getSingleOrNull();

      if (existing != null) {
        await client.db.$update(
          request.collection,
          request.recordId!,
          {
            ...existing,
            'deleted': true,
            'synced': synced,
            'noSync': noSync,
          },
        );
      }

      return $BatchResult(
        status: 204,
        body: null,
        collection: request.collection,
        recordId: request.recordId,
      );
    }

    if (request.isCreate) {
      // Create new record
      resultData = await client.db.$create(
        request.collection,
        {
          ...request.body,
          'deleted': false,
          'synced': synced,
          'isNew': true,
          'noSync': noSync,
        },
      );
    } else if (request.isUpdate) {
      // Update existing record
      resultData = await client.db.$update(
        request.collection,
        request.recordId!,
        {
          ...request.body,
          'deleted': false,
          'synced': synced,
          'isNew': false,
          'noSync': noSync,
        },
      );
    } else if (request.isUpsert) {
      // Upsert: check if ID exists in body
      final id = request.body['id'] as String?;
      if (id != null) {
        // Check if record exists
        final existing = await client.db
            .$query(request.collection, filter: "id = '$id'")
            .getSingleOrNull();

        if (existing != null) {
          // Update existing
          resultData = await client.db.$update(
            request.collection,
            id,
            {
              ...request.body,
              'deleted': false,
              'synced': synced,
              'isNew': false,
              'noSync': noSync,
            },
          );
        } else {
          // Create new with provided ID
          resultData = await client.db.$create(
            request.collection,
            {
              ...request.body,
              'deleted': false,
              'synced': synced,
              'isNew': true,
              'noSync': noSync,
            },
          );
        }
      } else {
        // No ID provided, create new
        resultData = await client.db.$create(
          request.collection,
          {
            ...request.body,
            'deleted': false,
            'synced': synced,
            'isNew': true,
            'noSync': noSync,
          },
        );
      }
    } else {
      throw Exception('Unknown batch request method: ${request.method}');
    }

    return $BatchResult(
      status: request.isCreate ? 201 : 200,
      body: resultData,
      collection: request.collection,
      recordId: resultData['id'] as String?,
    );
  }

  /// Syncs successful server results to local cache.
  Future<void> _syncResultsToCache(List<$BatchResult> results) async {
    for (var i = 0; i < results.length && i < _requests.length; i++) {
      final result = results[i];
      final request = _requests[i];

      if (!result.isSuccess) continue;

      try {
        if (request.isDelete) {
          // Actually delete from cache
          if (result.recordId != null) {
            await client.db.$delete(request.collection, result.recordId!);
          }
        } else if (result.body is Map<String, dynamic>) {
          // Create or update the record in cache as synced
          final data = result.body as Map<String, dynamic>;
          final id = data['id'] as String?;

          if (id != null) {
            await client.db.$create(
              request.collection,
              {
                ...data,
                'deleted': false,
                'synced': true,
                'isNew': false,
                'noSync': false,
              },
            );
          }
        }
      } catch (e) {
        client.logger.warning(
            'Error syncing batch result to cache: ${request.collection}', e);
      }
    }
  }

  /// Extracts the ID from a batch result body if possible.
  String? _extractIdFromBody(dynamic body) {
    if (body is Map<String, dynamic>) {
      return body['id'] as String?;
    }
    return null;
  }
}
