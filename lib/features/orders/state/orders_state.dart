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

  /// 1.3.2: the order whose FULL number was searched, when the list (this
  /// section, these filters) does not show it. Same store only.
  final Order? foundElsewhere;

  /// Where it is: «Заказ в разделе «Новые заказы»».
  final String? foundElsewhereLabel;

  OrdersLoaded({
    required this.items,
    required this.pagination,
    this.filters = OrderFilters.empty,
    this.foundElsewhere,
    this.foundElsewhereLabel,
  });

  @override
  List<Object?> get props =>
      [items, pagination, filters, foundElsewhere, foundElsewhereLabel];
}
