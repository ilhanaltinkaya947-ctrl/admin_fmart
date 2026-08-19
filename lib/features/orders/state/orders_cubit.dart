import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/api/api_errors.dart';
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
  // Moved out of «Закрытые» on 2026-08-17. order-service's own state machine
  // says it plainly — "Partial refund is not terminal, the rest of the order
  // still ships" — and it allows partially-refunded to go on to processing,
  // ready-for-delivery, delivering or completed. Filing it under closed
  // contradicted the backend.
  //
  // It matters most on самовывоз. About a tenth of orders here lose a line to
  // phantom stock, so a bag waiting at the counter has often already had one
  // line refunded, and that refund moved the order off the tab managers
  // actually work from. The overdue cue would have been invisible for exactly
  // the cohort it was built for.
  //
  // Partially refunded DELIVERY orders now appear here too. That is the same
  // correction, not a side effect: one of those is still out for delivery.
  'partially-refunded',
};

const _closedStatusCodes = {
  'delivered',
  'completed',
  'canceled',
  'refunded',
  'payment-failed',
  // Abandoned-3DS orders (status id 12, «Оплата не завершена»). Without this
  // they matched no tab and were invisible to managers in the list.
  'payment-timeout',
};

// Off-hours parked orders. Single-status preset on purpose so the
// Запланированные tab shows ONLY scheduled — they're not part of the
// active picking workload yet (no items being picked) and shouldn't
// mix with Новые's "needs attention right now" semantics.
const _scheduledStatusCodes = {
  'scheduled',
};

enum OrdersTabPreset { active, closed, scheduled, all }

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
      emit(OrdersFailure(message: describeApiError(e, subject: 'заказы')));
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
    // If the status fetch failed, the map is null and a non-"all" preset
    // would silently resolve to an empty filter — which made "Новые"
    // show every order instead of nothing. Surface it instead so the
    // operator knows to pull-to-refresh rather than think the filter
    // is broken on purpose.
    if (preset != OrdersTabPreset.all && _statusIdByCode == null) {
      emit(OrdersFailure(
        message:
            'Не удалось загрузить список статусов. Потяните вниз, чтобы повторить.',
      ));
      return;
    }
    final ids = _idsForPreset(preset);
    final next = _filters.copyWith(statusIds: ids);
    if (next == _filters) return;
    await applyFilters(next);
  }

  /// Drill-down helper for the Dashboard status-row taps. Resolves the
  /// backend status code to an id via the cached map and applies it as
  /// a single-status filter. If the status fetch hasn't completed or
  /// the name is unknown, falls back to clearing the status filter so
  /// the operator lands on something useful instead of an empty list.
  Future<void> applyStatusByName(String statusName) async {
    await _ensureStatusesLoaded();
    if (_statusIdByCode == null) {
      emit(OrdersFailure(
        message:
            'Не удалось загрузить список статусов. Потяните вниз, чтобы повторить.',
      ));
      return;
    }
    final id = _statusIdByCode![statusName];
    final next = _filters.copyWith(
      statusIds: id != null ? <int>[id] : const <int>[],
    );
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
      // Leave the map null on failure so the next refresh retries
      // instead of caching an empty map forever (which used to make
      // preset filters silently match nothing).
      _statusIdByCode = null;
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
      case OrdersTabPreset.scheduled:
        codes = _scheduledStatusCodes;
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
    // Keep the active tab preset's status filter when clearing — the
    // empty-state "Сбросить фильтры" button on the Запланированные tab
    // used to wipe everything and dump the manager into an unfiltered
    // ALL-orders view (which looked like the tab was leaking). Preserve
    // the preset's status_ids and only wipe search + date range.
    final preserved = _filters.copyWith(
      search: '',
      clearDateFrom: true,
      clearDateTo: true,
    );
    if (preserved == _filters) return;
    await applyFilters(preserved);
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
