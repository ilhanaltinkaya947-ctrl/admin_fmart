import 'package:bloc/bloc.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/storage/token_storage.dart';
import '../data/auth_repository.dart';
import '../models/current_user.dart';

part 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final TokenStorage tokenStorage;
  final AuthRepository authRepository;

  AuthCubit({
    required this.tokenStorage,
    required this.authRepository,
  }) : super(AuthLoading());

  Future<void> bootstrap() async {
    final has = await tokenStorage.hasTokens();
    if (!has) {
      emit(Unauthenticated());
      return;
    }
    // Honor the user's "Remember me" choice: if they unchecked it on the
    // previous login, wipe tokens on next launch so they have to sign in
    // again. Shared/loaner iPads use this.
    final remember = await tokenStorage.getRememberMe();
    if (!remember) {
      await tokenStorage.clear();
      emit(Unauthenticated());
      return;
    }
    try {
      final user = await authRepository.me();
      _bindOneSignalExternalUserId(user.id);
      emit(Authenticated(user: user));
    } catch (e) {
      // Only nuke saved tokens when it's a *real* auth failure (401
      // after refresh exhausted, or 403). Transient network / server
      // errors must NOT clear tokens — that defeated "Запомнить меня"
      // the first time the iPad had flaky wifi at app launch and forced
      // a re-login despite a valid refresh token still on disk.
      if (_isAuthFailure(e)) {
        await tokenStorage.clear();
      }
      emit(Unauthenticated());
    }
  }

  Future<void> setAuthenticated() async {
    try {
      final user = await authRepository.me();
      _bindOneSignalExternalUserId(user.id);
      emit(Authenticated(user: user));
    } catch (e) {
      if (_isAuthFailure(e)) {
        await tokenStorage.clear();
      }
      emit(Unauthenticated());
    }
  }

  /// Bind the device's OneSignal subscription to this user's backend id
  /// so the server-side push targets a stable external_user_id rather
  /// than the per-install player_id (which rotates on reinstall and
  /// silently breaks pushes to that user). Best-effort: if the SDK
  /// throws we log to Sentry and move on — auth shouldn't fail because
  /// push tagging hiccuped.
  void _bindOneSignalExternalUserId(int userId) {
    // Fire-and-forget so a slow/failed push binding never blocks login.
    // OneSignal.login returns a Future<void>, so an async rejection would
    // bypass a plain sync try/catch and vanish into PlatformDispatcher —
    // attach .catchError so the failure is still captured in Sentry.
    void report(Object e, StackTrace? st) {
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'onesignal',
        level: SentryLevel.warning,
        message: 'OneSignal.login($userId) failed: $e',
      ));
      Sentry.captureException(e, stackTrace: st);
    }

    try {
      OneSignal.login(userId.toString())
          .catchError((Object e, StackTrace st) => report(e, st));
    } catch (e, st) {
      report(e, st);
    }
  }

  /// Re-assert the OneSignal external_id binding for the currently signed-in
  /// user. `bootstrap()` already re-binds on a COLD start, but a manager who
  /// enables notifications (or whose bind silently failed) while the app is
  /// merely BACKGROUNDED returns via a resume — no bootstrap runs — and would
  /// otherwise stay unsubscribed until a full kill+relaunch. Called on app
  /// resume. Idempotent and best-effort: no-op unless authenticated.
  void reassertPushBinding() {
    final s = state;
    if (s is Authenticated) {
      _bindOneSignalExternalUserId(s.user.id);
    }
  }

  Future<void> logout() async {
    // Revoke the refresh token server-side first (best-effort) — without
    // this the refresh token stayed valid until natural expiry, a real
    // security gap on shared/lost staff iPads. Local clear + state change
    // happen regardless of whether the network call succeeds.
    try {
      final refresh = await tokenStorage.getRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        await authRepository.logout(refresh);
      }
    } catch (_) {
      // best-effort — proceed with local logout regardless
    }
    // Detach the OneSignal subscription from this user. Without it,
    // pushes targeted by external_user_id would keep arriving on this
    // iPad after the next admin signs in — wrong recipient, real PII
    // leak.
    try {
      OneSignal.logout();
    } catch (e, st) {
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'onesignal',
        level: SentryLevel.warning,
        message: 'OneSignal.logout failed: $e',
      ));
      Sentry.captureException(e, stackTrace: st);
    }
    await tokenStorage.clear();
    emit(Unauthenticated());
  }

  bool _isAuthFailure(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      return code == 401 || code == 403;
    }
    return false;
  }
}
