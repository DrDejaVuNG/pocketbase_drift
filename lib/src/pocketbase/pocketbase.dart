import 'dart:async';
import 'dart:collection' show SplayTreeMap;
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

class $PocketBase extends PocketBase with WidgetsBindingObserver {
  $PocketBase(
    super.baseUrl, {
    required this.db,
    super.lang,
    super.authStore,
    super.httpClientFactory,
  }) : connectivity = ConnectivityService() {
    WidgetsBinding.instance.addObserver(this);
    _listenForConnectivityChanges();
  }

  factory $PocketBase.database(
    String baseUrl, {
    bool inMemory = false,
    String lang = "en-US",
    $AuthStore? authStore,
    DatabaseConnection? connection,
    String dbName = 'pb_drift.db',
    Client Function()? httpClientFactory,
  }) {
    final db = DataBase(
      connection ?? connect(dbName, inMemory: inMemory),
    );
    return $PocketBase(
      baseUrl,
      db: db,
      lang: lang,
      authStore: authStore?..db = db,
      httpClientFactory: httpClientFactory,
    );
  }

  final DataBase db;
  final ConnectivityService connectivity;
  final Logger logger = Logger('PocketBaseDrift.client');

  set logging(bool enable) {
    hierarchicalLoggingEnabled = true;
    logger.level = enable ? Level.ALL : Level.OFF;
  }

  StreamSubscription? _connectivitySubscription;

  // Add a completer to track sync completion
  // Initialize to an already completed state.
  Completer<void>? _syncCompleter = Completer<void>()..complete();

  // Public getter to await sync completion
  Future<void> get syncCompleted => _syncCompleter?.future ?? Future.value();

  void _listenForConnectivityChanges() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = connectivity.statusStream.listen((isConnected) {
      if (isConnected) {
        logger
            .info('Connectivity restored. Retrying all pending local changes.');
        _retrySyncForAllServices();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      logger.info('App resumed. Resetting connectivity subscription.');
      connectivity.resetSubscription();
      // After resetting, the subscription will get the current state.
      // We can also trigger a proactive sync if online.
      if (connectivity.isConnected) {
        logger.info(
            'App resumed and online. Checking for pending changes to sync.');
        _retrySyncForAllServices();
      }
    }
  }

  Future<void> _retrySyncForAllServices() async {
    // A sync is starting, create a new, un-completed completer.
    _syncCompleter = Completer<void>();

    try {
      // Query database to find services with pending records
      // This ensures we sync even if service instances haven't been created yet
      // Note: In SQLite, JSON booleans are stored as 0 (false) and 1 (true)
      final pendingServicesQuery = await db
          .customSelect("SELECT DISTINCT service FROM services WHERE "
              "json_extract(data, '\$.synced') = 0 AND "
              "(json_extract(data, '\$.noSync') IS NULL OR json_extract(data, '\$.noSync') = 0)")
          .get();

      if (pendingServicesQuery.isEmpty) {
        logger.info('No pending changes to sync.');
        _syncCompleter!.complete();
        return;
      }

      final futures = <Future<void>>[];

      // Initialize service instances and sync for each service with pending records
      for (final row in pendingServicesQuery) {
        final serviceName = row.read<String>('service');

        // Skip schema and any other system services
        if (serviceName == 'schema') continue;

        // Get or create the service instance (this populates _recordServices)
        final service = collection(serviceName);

        // Convert stream to future and collect all sync operations
        final future = service.retryLocal().last.then((_) {
          logger.fine('Sync completed for service: $serviceName');
        });
        futures.add(future);
      }

      if (futures.isEmpty) {
        logger.info('No services to sync (only system records pending).');
        _syncCompleter!.complete();
        return;
      }

      // Wait for all services to complete their sync
      await Future.wait(futures);
      logger.info('All sync operations completed successfully');

      _syncCompleter!.complete();
    } catch (e) {
      logger.severe('Error during sync operations', e);
      if (!(_syncCompleter?.isCompleted ?? true)) {
        _syncCompleter!.completeError(e);
      }
    }
  }

  /// Generates a deterministic cache key for a given request.
  /// Returns an empty string if the request method is not 'GET',
  /// signifying that the request should not be cached.
  String _generateRequestCacheKey(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic> body = const {},
  }) {
    // Only cache idempotent GET requests to avoid side effects.
    if (method.toUpperCase() != 'GET') {
      return '';
    }

    // Sort maps to ensure the key is identical regardless of parameter order.
    final sortedQuery = SplayTreeMap.from(query);
    final sortedBody = SplayTreeMap.from(body);

    // Combine all unique request components into a single string.
    return '$method::$path::${jsonEncode(sortedQuery)}::${jsonEncode(sortedBody)}';
  }

  /// A list of path segments that should never be cached by [send].
  static const _nonCacheablePathSegments = [
    'api/backups',
    'api/batch',
    'api/collections',
    'api/crons',
    'api/health',
    'api/files',
    'api/logs',
    'api/realtime',
    'api/settings',
  ];

  /// Sends a single HTTP request with offline caching capabilities.
  ///
  /// This method extends the base `send` method to provide offline caching
  /// based on the provided [RequestPolicy]. Caching is enabled only for
  /// "GET" requests. For other methods, or if files are being uploaded,
  /// this method calls the original network-only implementation.
  @override
  Future<T> send<T extends dynamic>(
    String path, {
    String method = "GET",
    Map<String, String> headers = const {},
    Map<String, dynamic> query = const {},
    Map<String, dynamic> body = const {},
    List<http.MultipartFile> files = const [],
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    final cacheKey = _generateRequestCacheKey(
      path,
      method: method,
      query: query,
      body: body,
    );

    // Bypass cache if the key is empty (not a GET request), files are present,
    // or the path contains a non-cacheable segment.
    final shouldBypassCache = _nonCacheablePathSegments.any(path.contains);
    if (cacheKey.isEmpty || files.isNotEmpty || shouldBypassCache) {
      return super.send<T>(
        path,
        method: method,
        headers: headers,
        query: query,
        body: body,
        files: files,
      );
    }

    return requestPolicy.fetch<T>(
      label: 'send-$cacheKey',
      client: this,
      remote: () => super.send<T>(
        path,
        method: method,
        headers: headers,
        query: query,
        body: body,
        files: files,
      ),
      getLocal: () async {
        final cachedJson = await db.getCachedResponse(cacheKey);
        if (cachedJson == null) {
          throw Exception(
              'Response for request ($cacheKey) not found in cache.');
        }
        return jsonDecode(cachedJson) as T;
      },
      setLocal: (value) async {
        final jsonString = jsonEncode(value);
        await db.cacheResponse(cacheKey, jsonString);
      },
    );
  }

  Future<void> cacheSchema(String jsonSchema) async {
    try {
      final schema = (jsonDecode(jsonSchema) as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();

      // Populate the local drift database with the schema.
      await db.setSchema(schema);
    } catch (e) {
      logger.severe('Error caching schema', e);
    }
  }

  final _recordServices = <String, $RecordService>{};

  @override
  $RecordService collection(String collectionIdOrName) {
    var service = _recordServices[collectionIdOrName];

    if (service == null) {
      service = $RecordService(this, collectionIdOrName);
      _recordServices[collectionIdOrName] = service;
    }

    return service;
  }

  /// Get a collection by id or name and fetch
  /// the scheme to set it locally for use in
  /// validation and relations
  Future<$RecordService> $collection(
    String collectionIdOrName, {
    RequestPolicy requestPolicy = RequestPolicy.cacheAndNetwork,
  }) async {
    await collections.getFirstListItem(
      'id = "$collectionIdOrName" || name = "$collectionIdOrName"',
      requestPolicy: requestPolicy,
    );

    var service = _recordServices[collectionIdOrName];

    if (service == null) {
      service = $RecordService(this, collectionIdOrName);
      _recordServices[collectionIdOrName] = service;
    }

    return service;
  }

  Selectable<Service> search(String query, {String? service}) {
    return db.search(query, service: service);
  }

  @override
  $CollectionService get collections => $CollectionService(this);

  @override
  $FileService get files => $FileService(this);

  // Clean up resources
  @override
  void close() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    connectivity.dispose();
    super.close();
  }

  // @override
  // $AdminsService get admins => $AdminsService(this);

  // @override
  // $RealtimeService get realtime => $RealtimeService(this);

  // @override
  // $SettingsService get settings => $SettingsService(this);

  // @override
  // $LogService get logs => $LogService(this);

  // @override
  // $HealthService get health => $HealthService(this);

  // @override
  // $BackupService get backups => $BackupService(this);
}
