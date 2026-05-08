part of 'customers_cubit.dart';

sealed class CustomersState extends Equatable {
  @override
  List<Object?> get props => [];
}

final class CustomersInitial extends CustomersState {}

final class CustomersLoading extends CustomersState {}

final class CustomersFailure extends CustomersState {
  final String message;
  CustomersFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

final class CustomersLoaded extends CustomersState {
  final List<AdminCustomer> items;
  final Pagination pagination;

  CustomersLoaded({required this.items, required this.pagination});

  @override
  List<Object?> get props => [items, pagination];
}
