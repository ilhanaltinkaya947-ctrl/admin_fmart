part of 'orders_cubit.dart';

sealed class OrdersState extends Equatable {
  @override
  List<Object?> get props => [];
}

final class OrdersInitial extends OrdersState {}

final class OrdersLoading extends OrdersState {}

final class OrdersFailure extends OrdersState {
  final String message;
  OrdersFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

final class OrdersLoaded extends OrdersState {
  final List<Order> items;
  final Pagination pagination;
  final OrderFilters filters;

  OrdersLoaded({
    required this.items,
    required this.pagination,
    this.filters = OrderFilters.empty,
  });

  @override
  List<Object?> get props => [items, pagination, filters];
}
