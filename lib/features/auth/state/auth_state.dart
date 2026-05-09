part of 'auth_cubit.dart';

sealed class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

final class AuthLoading extends AuthState {}

final class Unauthenticated extends AuthState {}

final class Authenticated extends AuthState {
  final CurrentUser user;
  Authenticated({required this.user});

  @override
  List<Object?> get props => [user];
}
