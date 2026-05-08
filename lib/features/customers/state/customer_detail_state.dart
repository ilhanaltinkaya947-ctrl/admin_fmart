part of 'customer_detail_cubit.dart';

sealed class CustomerDetailState extends Equatable {
  @override
  List<Object?> get props => [];
}

final class CustomerDetailInitial extends CustomerDetailState {}

final class CustomerDetailLoading extends CustomerDetailState {}

final class CustomerDetailFailure extends CustomerDetailState {
  final String message;
  CustomerDetailFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

final class CustomerDetailLoaded extends CustomerDetailState {
  final CustomerInfo customer;
  final OrdersPage orders;

  CustomerDetailLoaded({required this.customer, required this.orders});

  @override
  List<Object?> get props => [customer, orders];
}
