import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

DatabaseConnection connect(
  String dbName, {
  bool logStatements = false,
  bool inMemory = false,
}) {
  if (inMemory) {
    return DatabaseConnection(NativeDatabase.memory());
  }

  return DatabaseConnection.delayed(Future.sync(() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, dbName);

    return DatabaseConnection(NativeDatabase(
      File(dbPath),
      logStatements: logStatements,
    ));
  }));
}
