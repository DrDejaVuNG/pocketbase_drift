import 'package:pocketbase/pocketbase.dart';
import 'package:pocketbase_drift/src/database/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class $AuthStore extends AsyncAuthStore {
  $AuthStore({
    required super.save,
    super.initial,
    super.clear,
  });

  DataBase? db;

  @override
  void clear() {
    super.clear();
    db?.clearAllData();
  }

  factory $AuthStore.prefs(SharedPreferences prefs, String key) {
    return $AuthStore(
      save: (data) async => await prefs.setString(key, data),
      initial: prefs.getString(key),
    );
  }
}
