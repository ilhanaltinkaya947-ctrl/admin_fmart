import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/storage/token_storage.dart';

part 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final TokenStorage tokenStorage;

  AuthCubit({required this.tokenStorage}) : super(AuthLoading());

  Future<void> bootstrap() async {
    final has = await tokenStorage.hasTokens();
    emit(has ? Authenticated() : Unauthenticated());
  }

  Future<void> setAuthenticated() async {
    emit(Authenticated());
  }

  Future<void> logout() async {
    await tokenStorage.clear();
    emit(Unauthenticated());
  }
}
