import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  final _s = const FlutterSecureStorage();

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  Future<void> saveTokens({required String access, required String refresh}) async {
    await _s.write(key: _kAccess, value: access);
    await _s.write(key: _kRefresh, value: refresh);
  }

  Future<String?> getAccessToken() => _s.read(key: _kAccess);
  Future<String?> getRefreshToken() => _s.read(key: _kRefresh);

  Future<bool> hasTokens() async {
    final a = await getAccessToken();
    final r = await getRefreshToken();
    return (a != null && a.isNotEmpty && r != null && r.isNotEmpty);
  }

  Future<void> clear() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
  }
}
