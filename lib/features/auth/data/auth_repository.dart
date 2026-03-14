import 'dart:async';

import 'package:flutter/foundation.dart';

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

    final access = resp.data['access_token'] as String?;
    final refresh = resp.data['refresh_token'] as String?;
    if (access == null || refresh == null) {
      throw Exception('Invalid login response: missing tokens');
    }
    try {
      await tokenStorage
          .saveTokens(access: access, refresh: refresh)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      debugPrint('[Auth] Token save timed out — retrying without timeout');
      await tokenStorage.saveTokens(access: access, refresh: refresh);
    }

  }
}
