import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

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
    try {
      final user = await authRepository.me();
      emit(Authenticated(user: user));
    } catch (_) {
      await tokenStorage.clear();
      emit(Unauthenticated());
    }
  }

  Future<void> setAuthenticated() async {
    try {
      final user = await authRepository.me();
      emit(Authenticated(user: user));
    } catch (_) {
      await tokenStorage.clear();
      emit(Unauthenticated());
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
    await tokenStorage.clear();
    emit(Unauthenticated());
  }
}
