import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/pocketbase_provider.dart';

class PendingRecordInfo {
  const PendingRecordInfo({
    required this.service,
    required this.id,
    required this.data,
    required this.isDeleted,
  });

  final String service;
  final String id;
  final Map<String, dynamic> data;
  final bool isDeleted;
}

/// Stream provider for pending unsynced items in SQLite.
final pendingSyncItemsProvider =
    StreamProvider.autoDispose<List<PendingRecordInfo>>((ref) {
  final client = ref.watch(pocketBaseProvider);

  // Watch the services table for unsynced or pending-deletion records
  final query = client.db.select(client.db.services);

  return query.watch().map((rows) {
    final list = <PendingRecordInfo>[];
    for (final row in rows) {
      if (row.service == 'schema') continue;
      final data = row.data;
      final isSynced = data['synced'] == true || data['synced'] == 1;
      final isDeleted = data['deleted'] == true || data['deleted'] == 1;
      final isNoSync = data['noSync'] == true || data['noSync'] == 1;

      if ((!isSynced && !isNoSync) || isDeleted) {
        list.add(PendingRecordInfo(
          service: row.service,
          id: row.id,
          data: data,
          isDeleted: isDeleted,
        ));
      }
    }
    return list;
  });
});

/// Count of pending items awaiting sync.
final pendingSyncCountProvider = Provider.autoDispose<int>((ref) {
  final items = ref.watch(pendingSyncItemsProvider).valueOrNull;
  return items?.length ?? 0;
});

/// Sync controller for triggering retry operations and cache clearing.
final syncControllerProvider = Provider<SyncController>((ref) {
  return SyncController(ref.watch(pocketBaseProvider));
});

class SyncController {
  SyncController(this._client);

  final $PocketBase _client;

  Future<void> syncNow() async {
    final services = [
      _client.collection(AppConstants.collectionProjects),
      _client.collection(AppConstants.collectionTasks),
    ];

    for (final s in services) {
      try {
        await s.retryLocal().last;
      } catch (e) {
        _client.logger.warning('Manual sync error for ${s.service}', e);
      }
    }
  }

  Future<void> clearCache() async {
    await _client.db.customStatement('DELETE FROM services;');
    await _client.db.customStatement('DELETE FROM cached_responses;');
    await _client.db.customStatement('DELETE FROM blob_files;');
  }
}
