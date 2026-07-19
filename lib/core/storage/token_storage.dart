import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  final _s = const FlutterSecureStorage();

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  // "Remember me" preference, persisted alongside the tokens. Default
  // behavior (no key set) = remember = true. When the user opts out,
  // we still keep the tokens for THIS session, but bootstrap() on the
  // next app launch will wipe them so they have to sign in again.
  static const _kRemember = 'remember_me';

  Future<void> saveTokens({
    required String access,
    required String refresh,
    bool rememberMe = true,
  }) async {
    await _s.write(key: _kAccess, value: access);
    await _s.write(key: _kRefresh, value: refresh);
    await _s.write(key: _kRemember, value: rememberMe ? '1' : '0');
  }

  Future<String?> getAccessToken() => _s.read(key: _kAccess);
  Future<String?> getRefreshToken() => _s.read(key: _kRefresh);

  Future<bool> getRememberMe() async {
    final v = await _s.read(key: _kRemember);
    // Absent = legacy install before this flag existed → keep remembered.
    return v == null || v == '1';
  }

  Future<bool> hasTokens() async {
    final a = await getAccessToken();
    final r = await getRefreshToken();
    return (a != null && a.isNotEmpty && r != null && r.isNotEmpty);
  }

  Future<void> clear() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
    await _s.delete(key: _kRemember);
  }
}
