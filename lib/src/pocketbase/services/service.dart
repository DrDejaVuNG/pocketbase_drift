import 'dart:async';

import 'package:flutter/foundation.dart';
import "package:http/http.dart" as http;

import '../../../pocketbase_drift.dart';

mixin ServiceMixin<M extends Jsonable> on BaseCrudService<M> {
  String get service;

  @override
  $PocketBase get client;

  /// Private helper to read MultipartFiles into a memory buffer.
  /// This is necessary because a stream can only be read once.
  Future<List<(String field, String? filename, Uint8List bytes)>> _bufferFiles(
    List<http.MultipartFile> files,
  ) async {
    if (files.isEmpty) return [];
    final buffered = <(String, String?, Uint8List)>[];
    for (final file in files) {
      final bytes = await file.finalize().toBytes();
      buffered.add((file.field, file.filename, bytes));
    }
    return buffered;
  }

  /// Private helper to modify the request body for cache-only file uploads.
  /// It adds the original filenames to the body, looking up the schema to
  /// determine if the field is single or multi-select.
  Future<void> _prepareCacheOnlyBody(
    Map<String, dynamic> body,
    List<(String field, String? filename, Uint8List bytes)> files,
  ) async {
    if (files.isEmpty) return;

    final collection =
        await client.db.$collections(service: service).getSingle();
    for (final file in files) {
      final fieldName = file.$1;
      final filename = file.$2;
      if (filename == null) continue;

      final schemaField =
          collection.fields.firstWhere((f) => f.name == fieldName);
      final isMultiSelect = schemaField.data['maxSelect'] != 1;

      final existing = body[fieldName];
      if (existing == null) {
        body[fieldName] = isMultiSelect ? [filename] : filename;
      } else if (existing is List) {
        if (!existing.contains(filename)) existing.add(filename);
      } else if (existing is String) {
        body[fieldName] = [existing, filename];
      }
    }
  }

  /// Private helper to save buffered file blobs to the local database.
  Future<void> _cacheFilesToDb(
    String recordId,
    Map<String, dynamic> recordData,
    List<(String field, String? filename, Uint8List bytes)> bufferedFiles,
  ) async {
    if (bufferedFiles.isEmpty) return;

    for (final fileData in bufferedFiles) {
      final fieldName = fileData.$1;
      final originalFilename = fileData.$2;
      final bytes = fileData.$3;
      final dynamic filenamesInRecord = recordData[fieldName];

      if (originalFilename == null) continue;

      if (filenamesInRecord is String) {
        await _cacheFileBlob(recordId, filenamesInRecord, bytes);
      } else if (filenamesInRecord is List && filenamesInRecord.isNotEmpty) {
        // Find the server-generated filename that corresponds to the original.
        final serverFilename = filenamesInRecord.firstWhere(
          (f) {
            if (f is! String) return false;
            if (f == originalFilename) return true; // Cache-only exact match
            final dotIndex = originalFilename.lastIndexOf('.');
            if (dotIndex == -1) return false;
            final nameWithoutExt = originalFilename.substring(0, dotIndex);
            return f.startsWith('${nameWithoutExt}_');
          },
          orElse: () => '',
        );

        if (serverFilename.isNotEmpty) {
          await _cacheFileBlob(recordId, serverFilename, bytes);
        }
      }
    }
  }

  @override
  Future<M> getOne(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    return requestPolicy.fetch<M>(
      label: service,
      client: client,
      remote: () => super.getOne(
        id,
        fields: fields,
        query: query,
        expand: expand,
        headers: headers,
      ),
      getLocal: () async {
        final result = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: "id = '$id'",
            )
            .getSingleOrNull();
        if (result == null) {
          throw Exception(
            'Record ($id) not found in collection $service [cache]',
          );
        }
        return itemFactoryFunc(result);
      },
      setLocal: (value) async {
        await client.db.$create(service, value.toJson());
      },
    );
  }

  @override
  Future<List<M>> getFullList({
    int batch = 200,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final result = <M>[];

    Future<List<M>> request(int page) async {
      return getList(
        page: page,
        perPage: batch,
        filter: filter,
        sort: sort,
        fields: fields,
        expand: expand,
        query: query,
        headers: headers,
        requestPolicy: requestPolicy,
        timeout: timeout,
      ).then((list) {
        result.addAll(list.items);
        client.logger.finer(
            'Fetched page for "$service": ${list.page}/${list.totalPages} (${list.items.length} items)');
        if (list.items.length < batch ||
            list.items.isEmpty ||
            list.page == list.totalPages) {
          return result;
        }
        return request(page + 1);
      });
    }

    return request(1);
  }

  @override
  Future<M> getFirstListItem(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) {
    return requestPolicy.fetch<M>(
      label: service,
      client: client,
      remote: () {
        return getList(
          perPage: 1,
          filter: filter,
          expand: expand,
          fields: fields,
          query: query,
          headers: headers,
          requestPolicy: requestPolicy,
        ).then((result) {
          if (result.items.isEmpty) {
            throw ClientException(
              statusCode: 404,
              response: <String, dynamic>{
                "code": 404,
                "message": "The requested resource wasn't found.",
                "data": <String, dynamic>{},
              },
            );
          }
          return result.items.first;
        });
      },
      getLocal: () async {
        final item = await client.db
            .$query(
              service,
              expand: expand,
              fields: fields,
              filter: filter,
            )
            .getSingleOrNull();
        return itemFactoryFunc(item!);
      },
      setLocal: (value) async {
        await client.db.$create(
          service,
          value.toJson(),
        );
      },
    );
  }

  Future<M?> getFirstListItemOrNull(
    String filter, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    try {
      return getFirstListItem(
        filter,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
        requestPolicy: requestPolicy,
      );
    } catch (e) {
      client.logger.fine(
          'getFirstListItemOrNull for "$service" with filter "$filter" returned null',
          e);
      return null;
    }
  }

  @override
  Future<ResultList<M>> getList({
    int page = 1,
    int perPage = 30,
    bool skipTotal = false,
    String? expand,
    String? filter,
    String? sort,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return requestPolicy.fetch<ResultList<M>>(
      label: service,
      client: client,
      remote: () => super
          .getList(
            page: page,
            perPage: perPage,
            skipTotal: skipTotal,
            expand: expand,
            filter: filter,
            fields: fields,
            sort: sort,
            query: query,
            headers: headers,
          )
          .timeout(timeout),
      getLocal: () async {
        final limit = perPage;
        final offset = (page - 1) * perPage;
        final items = await client.db
            .$query(
              service,
              limit: limit,
              offset: offset,
              expand: expand,
              fields: fields,
              filter: filter,
              sort: sort,
            )
            .get();
        final results = items.map((e) => itemFactoryFunc(e)).toList();
        final count = await client.db.$count(service);
        final totalPages = (count / perPage).ceil();
        return ResultList(
          page: page,
          perPage: perPage,
          items: results,
          totalItems: count,
          totalPages: totalPages,
        );
      },
      setLocal: (value) async {
        // Use the more efficient merge operation for list fetches.
        await client.db
            .mergeLocal(service, value.items.map((e) => e.toJson()).toList());
      },
    );
  }

  Future<M?> getOneOrNull(
    String id, {
    String? expand,
    String? fields,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    try {
      final result = await getOne(
        id,
        requestPolicy: requestPolicy,
        expand: expand,
        fields: fields,
        query: query,
        headers: headers,
      );
      return result;
    } catch (e) {
      client.logger.fine('getOneOrNull for "$service/$id" returned null.', e);
    }
    return null;
  }

  Future<void> setLocal(
    List<M> items, {
    bool removeAll = true,
  }) async {
    await client.db.setLocal(
      service,
      items.map((e) => e.toJson()).toList(),
      removeAll: removeAll,
    );
  }

  Future<void> _cacheFileBlob(
      String recordId, String filename, Uint8List bytes) async {
    try {
      await client.db.setFile(recordId, filename, bytes);
      client.logger.fine('Cached file blob "$filename" for record "$recordId"');
    } catch (e) {
      client.logger.warning(
          'Error caching file blob "$filename" for record "$recordId"', e);
    }
  }

  @override
  Future<M> create({
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    final bufferedFiles = await _bufferFiles(files);
    Map<String, dynamic> recordDataForCache = Map.from(body);
    M? result;
    bool savedToNetwork = false;

    if (requestPolicy == RequestPolicy.cacheOnly) {
      await _prepareCacheOnlyBody(recordDataForCache, bufferedFiles);
    }

    if (requestPolicy.isNetwork && client.connectivity.isConnected) {
      try {
        result = await super.create(
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          files: bufferedFiles
              .map((d) =>
                  http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
              .toList(),
        );
        savedToNetwork = true;
        recordDataForCache = result.toJson();
      } on ClientException catch (e) {
        if (e.statusCode == 400 && body['id'] != null) {
          final id = body['id'] as String;
          final updateBody = Map<String, dynamic>.from(body)..remove('id');
          try {
            result = await super.update(
              id,
              body: updateBody,
              query: query,
              headers: headers,
              expand: expand,
              fields: fields,
              files: bufferedFiles
                  .map((d) =>
                      http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
                  .toList(),
            );
            savedToNetwork = true;
            recordDataForCache = result.toJson();
          } catch (updateE) {
            final msg =
                'Failed to create (then update) record $body in $service: $e, then $updateE';
            if (requestPolicy == RequestPolicy.networkOnly) {
              throw Exception(msg);
            }
            client.logger.warning(msg);
          }
        } else {
          final msg = 'Failed to create record $body in $service: $e';
          if (requestPolicy == RequestPolicy.networkOnly) throw Exception(msg);
          client.logger.warning(msg);
        }
      } catch (e) {
        final msg = 'Failed to create record $body in $service: $e';
        if (requestPolicy == RequestPolicy.networkOnly) throw Exception(msg);
        client.logger.warning(msg);
      }
    }

    if (requestPolicy.isCache) {
      final shouldNoSync = requestPolicy == RequestPolicy.cacheOnly;
      final localRecordData = await client.db.$create(
        service,
        {
          ...recordDataForCache,
          'deleted': false,
          'synced': savedToNetwork,
          'isNew': !savedToNetwork ? true : null,
          'noSync': shouldNoSync,
        },
      );

      final recordIdForFiles = localRecordData['id'] as String?;
      if (recordIdForFiles != null) {
        await _cacheFilesToDb(recordIdForFiles, localRecordData, bufferedFiles);
      }
      result = itemFactoryFunc(localRecordData);
    }

    if (result == null) {
      throw Exception(
          'Failed to create record $body in $service with policy ${requestPolicy.name}.');
    }
    return result;
  }

  @override
  Future<M> update(
    String id, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    List<http.MultipartFile> files = const [],
    Map<String, String> headers = const {},
    String? expand,
    String? fields,
  }) async {
    final bufferedFiles = await _bufferFiles(files);
    Map<String, dynamic> recordDataForCache = Map.from(body);
    M? result;
    bool savedToNetwork = false;

    if (requestPolicy == RequestPolicy.cacheOnly) {
      await _prepareCacheOnlyBody(recordDataForCache, bufferedFiles);
    }

    if (requestPolicy.isNetwork && client.connectivity.isConnected) {
      try {
        result = await super.update(
          id,
          body: body,
          query: query,
          headers: headers,
          expand: expand,
          fields: fields,
          files: bufferedFiles
              .map((d) =>
                  http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
              .toList(),
        );
        savedToNetwork = true;
        recordDataForCache = result.toJson();
      } on ClientException catch (e) {
        if (e.statusCode == 404 || e.statusCode == 400) {
          try {
            result = await super.create(
              body: {...body, 'id': id},
              query: query,
              headers: headers,
              expand: expand,
              fields: fields,
              files: bufferedFiles
                  .map((d) =>
                      http.MultipartFile.fromBytes(d.$1, d.$3, filename: d.$2))
                  .toList(),
            );
            savedToNetwork = true;
            recordDataForCache = result.toJson();
          } catch (createE) {
            final msg =
                'Failed to update (then create) record $id in $service: $e, then $createE';
            if (requestPolicy == RequestPolicy.networkOnly) {
              throw Exception(msg);
            }
            client.logger.warning(msg);
          }
        } else {
          final msg = 'Failed to update record $id in $service: $e';
          if (requestPolicy == RequestPolicy.networkOnly) throw Exception(msg);
          client.logger.warning(msg);
        }
      } catch (e) {
        final msg = 'Failed to update record $id in $service: $e';
        if (requestPolicy == RequestPolicy.networkOnly) throw Exception(msg);
        client.logger.warning(msg);
      }
    }

    if (requestPolicy.isCache) {
      final shouldNoSync = requestPolicy == RequestPolicy.cacheOnly;
      final localRecordData = await client.db.$update(
        service,
        id,
        {
          'deleted': false,
          ...recordDataForCache,
          'synced': savedToNetwork,
          'isNew': false,
          'noSync': shouldNoSync,
        },
      );
      await _cacheFilesToDb(id, localRecordData, bufferedFiles);
      result = itemFactoryFunc(localRecordData);
    }

    if (result == null) {
      throw Exception(
          'Failed to update record $id in $service with policy ${requestPolicy.name}.');
    }
    return result;
  }

  @override
  Future<void> delete(
    String id, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
    Map<String, dynamic> body = const {},
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    bool saved = false;

    if (requestPolicy.isNetwork && client.connectivity.isConnected) {
      try {
        await super.delete(
          id,
          body: body,
          query: query,
          headers: headers,
        );
        saved = true;
      } catch (e) {
        final msg = 'Failed to delete record $id in $service: $e';
        if (requestPolicy == RequestPolicy.networkOnly) {
          throw Exception(msg);
        } else {
          client.logger.warning(msg);
        }
      }
    }

    if (requestPolicy.isCache) {
      if (saved) {
        await client.db.$delete(service, id);
      } else {
        await update(
          id,
          body: {
            ...body,
            'deleted': true,
          },
          query: query,
          headers: headers,
          requestPolicy: requestPolicy,
        );
      }
    }
  }
}

class RetryProgressEvent {
  final int total;
  final int current;

  const RetryProgressEvent({
    required this.total,
    required this.current,
  });

  double get progress => current / total;
}

enum RequestPolicy {
  cacheOnly,
  networkOnly,
  cacheAndNetwork,
}

extension RequestPolicyUtils on RequestPolicy {
  bool get isNetwork =>
      this == RequestPolicy.networkOnly ||
      this == RequestPolicy.cacheAndNetwork;
  bool get isCache =>
      this == RequestPolicy.cacheOnly || this == RequestPolicy.cacheAndNetwork;

  Future<T> fetch<T>({
    required String label,
    required $PocketBase client,
    required Future<T> Function() remote,
    required Future<T> Function() getLocal,
    required Future<void> Function(T) setLocal,
    // Duration timeout = const Duration(seconds: 3),
  }) async {
    client.logger.finer('Fetching "$label" with policy "$name"');
    T? result;

    if (isNetwork) {
      // Proactive connectivity check.
      if (!client.connectivity.isConnected) {
        client.logger
            .info('Device is offline. Skipping network request for "$label".');
        if (this == RequestPolicy.networkOnly) {
          throw Exception(
              'Device is offline and RequestPolicy.networkOnly was requested.');
        }
        // Fall through to cache if possible.
      } else {
        // Device is online, proceed with network request.
        try {
          client.logger.finer('Fetching remote for "$label"...');
          result = await remote();
        } catch (e) {
          client.logger.warning('Remote fetch for "$label" failed.', e);
          if (this == RequestPolicy.networkOnly) {
            throw Exception('Failed to get $e');
          }
        }
      }
    }

    if (isCache) {
      if (result != null) {
        client.logger.finer('Got remote data for "$label", updating cache...');
        await setLocal(result);
      } else {
        client.logger
            .finer('No remote data for "$label", fetching from cache...');
        result = await getLocal();
      }
    }

    if (result == null) {
      throw Exception('Failed to get');
    }

    return result;
  }
}
