import 'dart:async';

import 'package:dio/dio.dart';
import '../storage/token_storage.dart';

class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;
  final void Function() onUnauthorized;

  /// Lock to prevent concurrent token refresh attempts.
  Completer<bool>? _refreshCompleter;

  ApiClient({
    required String baseUrl,
    required this.tokenStorage,
    required this.onUnauthorized,
  }) : dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final access = await tokenStorage.getAccessToken();
        if (access != null && access.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $access';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final code = e.response?.statusCode;

        // Только 401 и только один повтор
        if (code != 401 || e.requestOptions.extra['retried'] == true) {
          return handler.next(e);
        }

        final ok = await _refresh();
        if (!ok) {
          onUnauthorized();
          return handler.next(e);
        }

        final req = e.requestOptions;
        req.extra['retried'] = true;

        final access = await tokenStorage.getAccessToken();
        if (access != null) req.headers['Authorization'] = 'Bearer $access';

        try {
          final resp = await dio.fetch(req);
          return handler.resolve(resp);
        } catch (err) {
          return handler.next(err is DioException ? err : e);
        }
      },
    ));
  }

  Future<bool> _refresh() async {
    // If a refresh is already in progress, wait for its result.
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final refresh = await tokenStorage.getRefreshToken();
      if (refresh == null || refresh.isEmpty) {
        _refreshCompleter!.complete(false);
        return false;
      }

      final resp = await dio.post('/gw/auth/refresh', data: {
        'refresh_token': refresh,
      });

      final access = resp.data['access_token'] as String?;
      final newRefresh = resp.data['refresh_token'] as String?;
      if (access == null || newRefresh == null) {
        _refreshCompleter!.complete(false);
        return false;
      }

      await tokenStorage.saveTokens(access: access, refresh: newRefresh);
      _refreshCompleter!.complete(true);
      return true;
    } catch (_) {
      await tokenStorage.clear();
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }
}
