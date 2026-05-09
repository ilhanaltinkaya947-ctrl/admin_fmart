import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../data/orders_repository.dart';
import '../models/order_filters.dart';
import '../models/order_models.dart';

part 'orders_state.dart';

class OrdersCubit extends Cubit<OrdersState> {
  final OrdersRepository ordersRepository;

  OrdersCubit({required this.ordersRepository}) : super(OrdersInitial());

  int? _storeId;
  final int _perPage = 20;
  bool _loading = false;
  OrderFilters _filters = OrderFilters.empty;
  Timer? _searchDebounce;

  OrderFilters get filters => _filters;

  Future<void> ensureLoaded({required int storeId}) async {
    if (_storeId == storeId && state is OrdersLoaded) return;
    await refresh(storeId: storeId);
  }

  Future<void> refresh({required int storeId}) async {
    if (_loading) return;
    _loading = true;

    emit(OrdersLoading());
    try {
      _storeId = storeId;
      final data = await _fetchPage(storeId: storeId, page: 1);
      emit(OrdersLoaded(
        items: data.items,
        pagination: data.pagination,
        filters: _filters,
      ));
    } catch (e) {
      emit(OrdersFailure(message: 'Не удалось загрузить заказы'));
    } finally {
      _loading = false;
    }
  }

  Future<void> applyFilters(OrderFilters next) async {
    _filters = next;
    if (_storeId != null) {
      await refresh(storeId: _storeId!);
    }
  }

  void setSearchQuery(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final next = _filters.copyWith(search: q);
      if (next == _filters) return;
      applyFilters(next);
    });
  }

  Future<void> clearFilters() async {
    _searchDebounce?.cancel();
    if (_filters.isEmpty) return;
    await applyFilters(OrderFilters.empty);
  }

  Future<void> loadMore() async {
    final st = state;
    if (st is! OrdersLoaded) return;
    if (!st.pagination.hasNext) return;
    if (_storeId == null) return;
    if (_loading) return;

    _loading = true;
    try {
      final nextPage = st.pagination.page + 1;
      final data = await _fetchPage(storeId: _storeId!, page: nextPage);

      emit(OrdersLoaded(
        items: [...st.items, ...data.items],
        pagination: data.pagination,
        filters: _filters,
      ));
    } catch (_) {
      // молча, чтобы не ломать UX
    } finally {
      _loading = false;
    }
  }

  Future<OrdersPage> _fetchPage({required int storeId, required int page}) {
    return ordersRepository.getOrders(
      storeId: storeId,
      page: page,
      perPage: _perPage,
      dateFrom: _filters.dateFrom,
      dateTo: _filters.dateTo,
      statusIds: _filters.statusIds.isEmpty ? null : _filters.statusIds,
      search: _filters.search.isEmpty ? null : _filters.search,
    );
  }

  void updateOrderInList(Order updated) {
    final st = state;
    if (st is! OrdersLoaded) return;

    final idx = st.items.indexWhere((o) => o.id == updated.id);
    if (idx == -1) return;

    final newList = [...st.items];
    newList[idx] = updated;
    emit(OrdersLoaded(
      items: newList,
      pagination: st.pagination,
      filters: st.filters,
    ));
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }
}
