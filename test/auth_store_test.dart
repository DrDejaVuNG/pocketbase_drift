import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('AuthStore', () {
    late $PocketBase client;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();

      // Mock connectivity
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/connectivity'),
              (MethodCall methodCall) async => ['wifi']);
    });

    tearDown(() async {
      client.close();
      await client.db.close();
    });

    test('clear() clears database when clearOnLogout is true (default)',
        () async {
      final authStore = $AuthStore.prefs(prefs, 'pb_auth');

      client = $PocketBase.database(
        'http://example.com',
        connection: DatabaseConnection(NativeDatabase.memory()),
        authStore: authStore,
      );

      // Add some data (bypass validation for simple test)
      await client.db
          .$create('users', {'id': 'user1', 'name': 'User 1'}, validate: false);

      // Verify data exists
      var users = await client.collection('users').getFullList();
      expect(users.length, 1);

      // Clear auth (logout)
      client.authStore.clear();

      // Verify data is gone
      users = await client.collection('users').getFullList();
      expect(users.length, 0);
    });

    test('clear() preserves database when clearOnLogout is false', () async {
      final authStore = $AuthStore.prefs(
        prefs,
        'pb_auth',
        clearOnLogout: false,
      );

      client = $PocketBase.database(
        'http://example.com',
        connection: DatabaseConnection(NativeDatabase.memory()),
        authStore: authStore,
      );

      // Add some data (bypass validation for simple test)
      await client.db
          .$create('users', {'id': 'user1', 'name': 'User 1'}, validate: false);

      // Verify data exists
      var users = await client.collection('users').getFullList();
      expect(users.length, 1);

      // Clear auth (logout)
      client.authStore.clear();

      // Verify data is STILL there
      users = await client.collection('users').getFullList();
      expect(users.length, 1);
    });
  });
}
