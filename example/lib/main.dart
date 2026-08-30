import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/providers/pocketbase_provider.dart';
import 'shared/utils/seed_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load startup dependencies in parallel
  final startupData = await Future.wait([
    SharedPreferences.getInstance(),
    rootBundle.loadString('assets/pb_schema.json'),
  ]);

  final sharedPreferences = startupData[0] as SharedPreferences;
  final schemaJson = startupData[1] as String;

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      schemaProvider.overrideWithValue(schemaJson),
    ],
  );

  // Seed sample projects and tasks if database is newly initialized
  final client = container.read(pocketBaseProvider);
  await seedInitialDataIfEmpty(client);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TaskFlowApp(),
    ),
  );
}

class TaskFlowApp extends ConsumerWidget {
  const TaskFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'TaskFlow — PocketBase Drift Demo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
