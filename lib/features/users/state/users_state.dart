part of 'users_cubit.dart';

sealed class UsersState extends Equatable {
  @override
  List<Object?> get props => [];
}

final class UsersInitial extends UsersState {}

final class UsersLoading extends UsersState {}

final class UsersFailure extends UsersState {
  final String message;
  UsersFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

final class UsersLoaded extends UsersState {
  final List<AdminUser> items;
  final Pagination pagination;

  UsersLoaded({required this.items, required this.pagination});

  @override
  List<Object?> get props => [items, pagination];
}
