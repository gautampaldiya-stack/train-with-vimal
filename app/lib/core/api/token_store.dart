import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the session tokens on the device.
class TokenStore {
  static const _a = 'twv.access', _r = 'twv.refresh';
  String? access, refresh;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    access = p.getString(_a);
    refresh = p.getString(_r);
  }

  Future<void> save(String access, String refresh) async {
    this.access = access;
    this.refresh = refresh;
    final p = await SharedPreferences.getInstance();
    await p.setString(_a, access);
    await p.setString(_r, refresh);
  }

  Future<void> clear() async {
    access = refresh = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_a);
    await p.remove(_r);
  }
}
