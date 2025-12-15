import 'package:pocketbase/pocketbase.dart';
import 'package:pocketbase_drift/src/database/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class $AuthStore extends AsyncAuthStore {
  $AuthStore({
    required super.save,
    super.initial,
    super.clear,
    this.clearOnLogout = true,
  });

  DataBase? db;
  final bool clearOnLogout;

  @override
  void clear() {
    super.clear();
    if (clearOnLogout) {
      db?.clearAllData();
    }
  }

  factory $AuthStore.prefs(
    SharedPreferences prefs,
    String key, {
    bool clearOnLogout = true,
  }) {
    return $AuthStore(
      save: (data) async => await prefs.setString(key, data),
      initial: prefs.getString(key),
      clearOnLogout: clearOnLogout,
    );
  }
}
