import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

AuthStore $AuthStore(SharedPreferences prefs, String key) {
  return AsyncAuthStore(
    save: (data) async => await prefs.setString(key, data),
    initial: prefs.getString(key),
  );
}
