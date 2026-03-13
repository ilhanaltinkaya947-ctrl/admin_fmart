import '../../../core/api/api_client.dart';
import '../../../core/storage/token_storage.dart';

class AuthRepository {
  final ApiClient api;
  final TokenStorage tokenStorage;

  AuthRepository({required this.api, required this.tokenStorage});

  Future<void> login({
    required String phone,
    required String password,
    required String onesignalUserId,
  }) async {
    final resp = await api.dio.post('/gw/auth/login', data: {
      'phone': phone,
      'password': password,
      'onesignal_user_id': onesignalUserId,
    });

    final access = resp.data['access_token'] as String;
    final refresh = resp.data['refresh_token'] as String;
    await tokenStorage
        .saveTokens(access: access, refresh: refresh)
        .timeout(const Duration(seconds: 3));

  }
}
