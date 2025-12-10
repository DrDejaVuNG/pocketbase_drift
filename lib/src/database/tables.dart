import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:pocketbase/pocketbase.dart';

@DataClassName('Service')
class Services extends Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get data => text().map(const JsonMapper())();
  TextColumn get service => text()();
  TextColumn get created => text().nullable()();
  TextColumn get updated => text().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {id, service};
}

@DataClassName('BlobFile')
class BlobFiles extends Table with AutoIncrementingPrimaryKey {
  TextColumn get recordId => text().references(Services, #id)();
  TextColumn get filename => text()();
  BlobColumn get data => blob()();
  DateTimeColumn get expiration => dateTime().nullable()();
  TextColumn get created => text().nullable()();
  TextColumn get updated => text().nullable()();
}

@DataClassName('CachedResponse')
class CachedResponses extends Table {
  /// A unique hash of the request details (method, path, query, body)
  /// that will serve as the primary key.
  TextColumn get requestKey => text()();

  /// The raw JSON-encoded response data as a string.
  TextColumn get responseData => text()();

  /// The timestamp of when this cache entry was created. Useful for
  /// future implementations of Time-To-Live (TTL) caching.
  DateTimeColumn get cachedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column<Object>>? get primaryKey => {requestKey};
}

mixin AutoIncrementingPrimaryKey on Table {
  IntColumn get id => integer().autoIncrement()();
}

class JsonMapper extends TypeConverter<Map<String, dynamic>, String> {
  const JsonMapper();

  @override
  Map<String, dynamic> fromSql(String fromDb) => jsonDecode(fromDb);

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);
}

class StringListMapper extends TypeConverter<List<String>, String> {
  const StringListMapper();

  @override
  List<String> fromSql(String fromDb) => jsonDecode(fromDb).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

class SchemaFieldListMapper
    extends TypeConverter<List<CollectionField>, String> {
  const SchemaFieldListMapper();

  @override
  List<CollectionField> fromSql(String fromDb) => (jsonDecode(fromDb) as List)
      .map((e) => CollectionField.fromJson(e))
      .toList();

  @override
  String toSql(List<CollectionField> value) =>
      jsonEncode(value.map((e) => e.toJson()).toList());
}

/// Characters allowed in PocketBase IDs (lowercase alphanumeric only)
const _pbIdChars = 'abcdefghijklmnopqrstuvwxyz0123456789';
final _secureRandom = Random.secure();

/// Generates a random 15-character alphanumeric string compatible with PocketBase.
///
/// PocketBase IDs must match the pattern `^[a-z0-9]+$` and be exactly 15 characters.
/// This allows local IDs to be accepted by the server during sync, eliminating
/// the need for ID remapping after server creation.
String newId() {
  return String.fromCharCodes(
    Iterable.generate(
      15,
      (_) => _pbIdChars.codeUnitAt(_secureRandom.nextInt(_pbIdChars.length)),
    ),
  );
}
