import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketbase_drift/pocketbase_drift.dart';

import 'test_data/collections.json.dart';

/// Tests for PocketBase SDK's RecordModel.get&lt;T&gt;() dot-notation path access
/// for locally expanded relations.
///
/// The PocketBase SDK uses dot-notation to access nested fields:
/// - record.get&lt;String&gt;('expand.user.name')
/// - record.get&lt;RecordModel&gt;('expand.user')
/// - record.get&lt;List&lt;RecordModel>&gt;('expand.products')
/// - record.get&lt;int&gt;('expand.items.0.quantity')
///
/// These tests verify that local expansion in pocketbase_drift produces
/// data structures compatible with this API.

void main() {
  final connection = DatabaseConnection(NativeDatabase.memory());
  final db = DataBase(connection);
  final collections = [...offlineCollections]
      .map((e) => CollectionModel.fromJson(jsonDecode(jsonEncode(e))))
      .toList();

  const todo = 'todo';
  const ultimate = 'ultimate';
  const users = 'users';

  setUpAll(() async {
    await db.setSchema(collections.map((e) => e.toJson()).toList());
    await db.deleteAll(todo);
    await db.deleteAll(ultimate);
    await db.deleteAll(users);
  });

  tearDown(() async {
    await db.deleteAll(todo);
    await db.deleteAll(ultimate);
    await db.deleteAll(users);
  });

  group('RecordModel.get() dot-notation access for local expand', () {
    test('basic expand - access field via expand.<relation>.0.<field>',
        () async {
      // Setup: Create a related record and a main record
      final relatedItem = await db.$create(todo, {'name': 'Test Todo Item'});
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Main Record',
        'relation_single': relatedItem['id'],
      });

      // Query with expansion
      final result = await db
          .$query(ultimate,
              expand: 'relation_single', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);

      // Convert to RecordModel (simulating what the service layer does)
      final record = RecordModel.fromJson(result!);

      // Test: Access using the PocketBase SDK dot-notation API
      // Since expand returns a List, we access via index
      expect(
        record.get<String>('expand.relation_single.0.name'),
        'Test Todo Item',
        reason: 'Should access nested field via dot-notation path',
      );

      // Test: Access the expanded record itself
      final expandedRecord =
          record.get<RecordModel>('expand.relation_single.0');
      expect(expandedRecord, isNotNull);
      expect(expandedRecord.get<String>('name'), 'Test Todo Item');

      // Test: Access the list of expanded records
      final expandedList =
          record.get<List<RecordModel>>('expand.relation_single');
      expect(expandedList.length, 1);
      expect(expandedList.first.get<String>('name'), 'Test Todo Item');
    });

    test('nested expand - access deeply nested field', () async {
      // Setup: user -> todo -> ultimate (3 levels)
      final user = await db.$create(users, {'name': 'John Doe'});
      final todoItem = await db.$create(todo, {
        'name': 'Todo with User',
        'user': user['id'],
      });
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Ultimate with Nested',
        'relation_single': todoItem['id'],
      });

      // Query with nested expansion
      final result = await db
          .$query(ultimate,
              expand: 'relation_single.user',
              filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Access first-level expanded field
      expect(
        record.get<String>('expand.relation_single.0.name'),
        'Todo with User',
      );

      // Test: Access second-level (nested) expanded field
      expect(
        record.get<String>('expand.relation_single.0.expand.user.0.name'),
        'John Doe',
        reason: 'Should access deeply nested field via dot-notation',
      );

      // Test: Get the nested RecordModel directly
      final nestedUser =
          record.get<RecordModel>('expand.relation_single.0.expand.user.0');
      expect(nestedUser, isNotNull);
      expect(nestedUser.get<String>('name'), 'John Doe');
    });

    test('multi-relation expand - access multiple items', () async {
      // Setup: multiple related records
      final related1 = await db.$create(todo, {'name': 'First Todo'});
      final related2 = await db.$create(todo, {'name': 'Second Todo'});
      final related3 = await db.$create(todo, {'name': 'Third Todo'});

      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Multi Relation Test',
        'relation_multi': [related1['id'], related2['id'], related3['id']],
      });

      // Query with expansion
      final result = await db
          .$query(ultimate,
              expand: 'relation_multi', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Access each item by index using dot-notation
      final expandedList =
          record.get<List<RecordModel>>('expand.relation_multi');
      expect(expandedList.length, 3);

      // Access by index
      expect(record.get<String>('expand.relation_multi.0.name'), isNotEmpty);
      expect(record.get<String>('expand.relation_multi.1.name'), isNotEmpty);
      expect(record.get<String>('expand.relation_multi.2.name'), isNotEmpty);

      // Verify all names are present
      final names = expandedList.map((r) => r.get<String>('name')).toList();
      expect(names, containsAll(['First Todo', 'Second Todo', 'Third Todo']));
    });

    test('empty expand - returns empty list with default values', () async {
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'No Relations',
        'relation_multi': [],
      });

      final result = await db
          .$query(ultimate,
              expand: 'relation_multi', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Accessing non-existent index with default value
      expect(
        record.get<String>('expand.relation_multi.0.name', 'N/A'),
        'N/A',
        reason: 'Should return default value for non-existent path',
      );

      // Test: Get the empty list
      final expandedList =
          record.get<List<RecordModel>>('expand.relation_multi');
      expect(expandedList, isEmpty);
    });

    test('null relation - expand returns empty', () async {
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Null Relation',
        'relation_single': null,
      });

      final result = await db
          .$query(ultimate,
              expand: 'relation_single', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Accessing with default value
      expect(
        record.get<String>('expand.relation_single.0.name', 'default'),
        'default',
      );
    });

    test('mixed data types in expanded record', () async {
      // The 'ultimate' collection has various field types
      final todoItem = await db.$create(todo, {'name': 'Type Test'});
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'Type Test Main',
        'number': 42.5,
        'bool': true,
        'email': 'test@example.com',
        'relation_single': todoItem['id'],
      });

      final result = await db
          .$query(ultimate,
              expand: 'relation_single', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Access various types on the main record
      expect(record.get<String>('plain_text'), 'Type Test Main');
      expect(record.get<double>('number'), 42.5);
      expect(record.get<bool>('bool'), true);
      expect(record.get<String>('email'), 'test@example.com');

      // Test: Access expanded record
      expect(record.get<String>('expand.relation_single.0.name'), 'Type Test');
    });

    test('accessing record id via expand path', () async {
      final relatedItem = await db.$create(todo, {'name': 'ID Test'});
      final mainItem = await db.$create(ultimate, {
        'plain_text': 'ID Access Test',
        'relation_single': relatedItem['id'],
      });

      final result = await db
          .$query(ultimate,
              expand: 'relation_single', filter: "id = '${mainItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Test: Access id of expanded record
      expect(
        record.get<String>('expand.relation_single.0.id'),
        relatedItem['id'],
      );
    });
  });

  group('Direct field access vs expand path equivalence', () {
    test('same data accessible via different paths', () async {
      final user = await db.$create(users, {'name': 'Path Test User'});
      final todoItem = await db.$create(todo, {
        'name': 'Path Test Todo',
        'user': user['id'],
      });

      // Get the todo with user expanded
      final result = await db
          .$query(todo, expand: 'user', filter: "id = '${todoItem['id']}'")
          .getSingleOrNull();

      expect(result, isNotNull);
      final record = RecordModel.fromJson(result!);

      // Access user ID directly from the relation field
      expect(record.get<String>('user'), user['id']);

      // Access user name via expand path
      expect(record.get<String>('expand.user.0.name'), 'Path Test User');

      // Access user ID via expand path (should match direct access)
      expect(
        record.get<String>('expand.user.0.id'),
        record.get<String>('user'),
      );
    });
  });
}
