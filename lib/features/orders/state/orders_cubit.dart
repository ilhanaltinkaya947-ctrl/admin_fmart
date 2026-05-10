import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../data/orders_repository.dart';
import '../models/order_filters.dart';
import '../models/order_models.dart';

part 'orders_state.dart';

/// Status code groupings used by the home tabs.
const _activeStatusCodes = {
  'paid',
  'processing',
  'ready-for-delivery',
  'delivering',
};

const _closedStatusCodes = {
  'delivered',
  'completed',
  'canceled',
  'refunded',
  'partially-refunded',
  'payment-failed',
};

enum OrdersTabPreset { active, closed, all }

class OrdersCubit extends Cubit<OrdersState> {
  final OrdersRepository ordersRepository;

  OrdersCubit({required this.ordersRepository}) : super(OrdersInitial());

  int? _storeId;
  final int _perPage = 20;
  bool _loading = false;
  OrderFilters _filters = OrderFilters.empty;
  Timer? _searchDebounce;

  Map<String, int>? _statusIdByCode;
  Future<void>? _statusFetch;

  OrderFilters get filters => _filters;

  /// Wipe in-memory state — used by AuthCubit logout listener so the
  /// next admin signing in on this device doesn't briefly see the
  /// previous user's orders.
  void reset() {
    _searchDebounce?.cancel();
    _storeId = null;
    _filters = OrderFilters.empty;
    _loading = false;
    _statusIdByCode = null;
    _statusFetch = null;
    emit(OrdersInitial());
  }

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

  /// Switch the orders list to a tab preset. Fetches statuses lazily on
  /// first call so we can map status codes to ids the backend expects.
  Future<void> applyTabPreset(OrdersTabPreset preset) async {
    await _ensureStatusesLoaded();
    final ids = _idsForPreset(preset);
    final next = _filters.copyWith(statusIds: ids);
    if (next == _filters) return;
    await applyFilters(next);
  }

  Future<void> _ensureStatusesLoaded() async {
    if (_statusIdByCode != null) return;
    if (_statusFetch != null) {
      await _statusFetch;
      return;
    }
    _statusFetch = _fetchStatuses();
    try {
      await _statusFetch;
    } finally {
      _statusFetch = null;
    }
  }

  Future<void> _fetchStatuses() async {
    try {
      final res = await ordersRepository.getOrderStatuses();
      _statusIdByCode = {for (final s in res.items) s.statusName: s.id};
    } catch (_) {
      _statusIdByCode = const {};
    }
  }

  List<int> _idsForPreset(OrdersTabPreset preset) {
    final map = _statusIdByCode ?? const <String, int>{};
    Iterable<String> codes;
    switch (preset) {
      case OrdersTabPreset.active:
        codes = _activeStatusCodes;
        break;
      case OrdersTabPreset.closed:
        codes = _closedStatusCodes;
        break;
      case OrdersTabPreset.all:
        return const [];
    }
    return codes.map((c) => map[c]).whereType<int>().toList();
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
