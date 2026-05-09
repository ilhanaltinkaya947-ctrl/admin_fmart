import 'package:equatable/equatable.dart';

class OrderFilters extends Equatable {
  final String search;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<int> statusIds;

  const OrderFilters({
    this.search = '',
    this.dateFrom,
    this.dateTo,
    this.statusIds = const [],
  });

  bool get isEmpty =>
      search.isEmpty && dateFrom == null && dateTo == null && statusIds.isEmpty;

  int get activeCount {
    var n = 0;
    if (search.isNotEmpty) n++;
    if (dateFrom != null || dateTo != null) n++;
    if (statusIds.isNotEmpty) n++;
    return n;
  }

  OrderFilters copyWith({
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<int>? statusIds,
    bool clearDateFrom = false,
    bool clearDateTo = false,
  }) {
    return OrderFilters(
      search: search ?? this.search,
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      statusIds: statusIds ?? this.statusIds,
    );
  }

  static const empty = OrderFilters();

  @override
  List<Object?> get props => [search, dateFrom, dateTo, statusIds];
}
