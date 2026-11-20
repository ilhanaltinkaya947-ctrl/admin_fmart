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

/// 1.3.2 (case 19.11, Тулпар): the search text when it is a FULL order number
/// (6 to 9 digits, spaces around it ignored), else null. Order numbers start
/// at 100000, so a shorter number is a partial one and keeps the old search.
int? exactOrderNumber(String search) {
  final t = search.trim();
  if (!RegExp(r'^[0-9]{6,9}$').hasMatch(t)) return null;
  return int.parse(t);
}

/// The section (home tab) an order with [statusCode] is listed under, or null
/// when no section shows it (unpaid orders).
OrdersTabPreset? sectionForStatus(String statusCode) {
  final c = statusCode.toLowerCase().trim();
  if (_activeStatusCodes.contains(c)) return OrdersTabPreset.active;
  if (_scheduledStatusCodes.contains(c)) return OrdersTabPreset.scheduled;
  if (_closedStatusCodes.contains(c)) return OrdersTabPreset.closed;
  return null;
}

/// The section's name exactly as the side menu says it.
String sectionTitle(OrdersTabPreset p) {
  switch (p) {
    case OrdersTabPreset.active:
      return 'Новые заказы';
    case OrdersTabPreset.scheduled:
      return 'Запланированные';
    case OrdersTabPreset.closed:
      return 'История заказов';
    case OrdersTabPreset.all:
      return 'Все заказы';
  }
}

/// The line above an order found by its number outside what the list shows.
String foundElsewhereLabel(Order o, OrdersTabPreset? current) {
  final sec = sectionForStatus(o.status);
  if (sec == null) {
    return 'Заказ со статусом «${orderStatusRu(o.status, fulfillmentType: o.fulfillmentType)}»';
  }
  if (sec != current) return 'Заказ в разделе «${sectionTitle(sec)}»';
  return 'Заказ не подходит под выбранные фильтры';
}

class OrdersCubit extends Cubit<OrdersState> {
  final OrdersRepository ordersRepository;

  /// [autoRefreshEvery]: how often the loaded list re-reads page 1 quietly.
  /// null turns it off (tests).
  OrdersCubit({
    required this.ordersRepository,
    Duration? autoRefreshEvery = const Duration(seconds: 30),
  })  : _autoRefreshEvery = autoRefreshEvery,
        super(OrdersInitial());

  // The list used to change only when someone pressed refresh or pulled it
  // down. A store iPad left on «Новые» therefore never showed an order the
  // poller had already rung for (order 1095, 2026-10-09). Dart timers are
  // suspended in background on iOS, so this costs nothing while locked.
  final Duration? _autoRefreshEvery;
  Timer? _autoTimer;

  // Bumped by everything that replaces or extends the list on purpose
  // (refresh, loadMore, reset). A quiet refresh started before such a change
  // is stale when it lands and is dropped, so it can never undo a tab switch,
  // a search, or a page the operator just scrolled in.
  int _gen = 0;
  bool _quietInFlight = false;
  // A quiet refresh asked for while another load was running. That load may
  // have been sent before the new order was paid (the refresh after the push
  // dialog is), so run the quiet one again as soon as it finishes instead of
  // leaving the order to the next 30 s tick.
  bool _quietAgain = false;

  int? _storeId;
  final int _perPage = 20;
  bool _loading = false;
  OrderFilters _filters = OrderFilters.empty;
  Timer? _searchDebounce;

  Map<String, int>? _statusIdByCode;
  Future<void>? _statusFetch;

  // 1.3.2: the section the operator is in and the statuses it shows. A status
  // filter that differs from these was picked on top (the «Статус» chip or a
  // dashboard drill-down) and is shown with its own reset. Before 1.3.2 such
  // a filter survived «Сбросить фильтры», and tapping the highlighted section
  // again did nothing: an iPad stayed on status_ids=8 (19.11).
  OrdersTabPreset? _preset;
  List<int> _sectionStatusIds = const [];

  OrderFilters get filters => _filters;

  OrdersTabPreset? get currentSection => _preset;

  /// True when the list shows fewer statuses than the section it is in.
  bool get statusFilterNarrowed =>
      !_sameIds(_filters.statusIds, _sectionStatusIds);

  /// Russian names of the statuses of a narrowed filter, for the reset strip.
  List<String> get narrowedStatusNames {
    if (!statusFilterNarrowed) return const [];
    final byId = {
      for (final e in (_statusIdByCode ?? const <String, int>{}).entries)
        e.value: e.key,
    };
    return [
      for (final id in _filters.statusIds)
        byId[id] != null ? orderStatusRu(byId[id]!) : 'статус $id',
    ];
  }

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sa = a.toSet();
    return b.every(sa.contains) && sa.length == b.toSet().length;
  }

  /// Wipe in-memory state — used by AuthCubit logout listener so the
  /// next admin signing in on this device doesn't briefly see the
  /// previous user's orders.
  void reset() {
    _gen++;
    _quietAgain = false;
    _refreshAgain = false;
    _autoTimer?.cancel();
    _autoTimer = null;
    _searchDebounce?.cancel();
    _storeId = null;
    _filters = OrderFilters.empty;
    _loading = false;
    _statusIdByCode = null;
    _statusFetch = null;
    _preset = null;
    _sectionStatusIds = const [];
    emit(OrdersInitial());
  }

  Future<void> ensureLoaded({required int storeId}) async {
    if (_storeId == storeId && state is OrdersLoaded) return;
    await refresh(storeId: storeId);
  }

  Future<void> refresh({required int storeId}) async {
    if (_loading) {
      // A new search or section while a load runs: load again when it ends,
      // instead of showing the old answer under the new filters.
      _refreshAgain = true;
      return;
    }
    _loading = true;
    _gen++;

    emit(OrdersLoading());
    try {
      _storeId = storeId;
      _armAutoRefresh();
      final asked = _filters;
      final data = await _fetchPage(storeId: storeId, page: 1);
      final found = await _resolveExactNumber(data.items, storeId, asked);
      emit(OrdersLoaded(
        items: found.items,
        pagination: data.pagination,
        filters: asked,
        foundElsewhere: found.order,
        foundElsewhereLabel: found.label,
      ));
    } catch (e) {
      emit(OrdersFailure(message: describeApiError(e, subject: 'заказы')));
    } finally {
      _loading = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        final id = _storeId;
        if (id != null) unawaited(refresh(storeId: id));
      } else {
        _runQuietAgain();
      }
    }
  }

  bool _refreshAgain = false;

  /// 1.3.2: a full order number finds the order whatever section or status
  /// filter is selected (case 19.11: «Запланированные» + 100320 → «Заказов
  /// нет»). order-service 20.11+ already puts it in the list; older servers do
  /// not, so the order is read by its number (GET /admin/orders/{id}, scoped
  /// to the manager's stores by the server). Shown only when it belongs to
  /// THIS store. An order that is in the list but outside this section is
  /// moved out of the rows into the found block, so it carries its label.
  Future<({List<Order> items, Order? order, String? label})> _resolveExactNumber(
    List<Order> items,
    int storeId,
    OrderFilters asked,
  ) async {
    final n = exactOrderNumber(asked.search);
    if (n == null) return (items: items, order: null, label: null);
    Order? hit;
    for (final o in items) {
      if (o.id == n) hit = o;
    }
    if (hit != null) {
      if (_inShownSection(hit, asked)) {
        return (items: items, order: null, label: null);
      }
      return (
        items: [for (final o in items) if (o.id != n) o],
        order: hit,
        label: foundElsewhereLabel(hit, _preset),
      );
    }
    Order? o;
    try {
      o = await ordersRepository.getOrderById(storeId: storeId, orderId: n);
    } catch (_) {
      o = null; // 403 another store, network: the list answer stands
    }
    if (o == null || o.storeId != storeId) {
      return (items: items, order: null, label: null);
    }
    return (items: items, order: o, label: foundElsewhereLabel(o, _preset));
  }

  bool _inShownSection(Order o, OrderFilters asked) {
    if (asked.statusIds.isEmpty) return true;
    final id = _statusIdByCode?[o.status.toLowerCase().trim()];
    return id != null && asked.statusIds.contains(id);
  }

  void _runQuietAgain() {
    if (!_quietAgain) return;
    _quietAgain = false;
    final id = _storeId;
    // After a failed load the operator sees the error and its retry button;
    // the 30 s tick retries too. Do not flash a spinner on top of it.
    if (id == null || state is OrdersFailure) return;
    unawaited(refreshQuietly(storeId: id));
  }

  void _armAutoRefresh() {
    final every = _autoRefreshEvery;
    if (every == null || _autoTimer != null) return;
    _autoTimer = Timer.periodic(every, (_) {
      final id = _storeId;
      if (id != null) refreshQuietly(storeId: id);
    });
  }

  /// Re-read page 1 without a spinner and without touching filters.
  ///
  /// Used by the 30 s timer and by the new-order poller. Never shows an
  /// error: on failure the operator keeps the list they had. A list that
  /// failed to load is retried with a normal [refresh] so it can recover.
  Future<void> refreshQuietly({required int storeId}) async {
    if (_storeId != storeId) return; // showing another store, or logged out
    final st = state;
    if (_loading || _quietInFlight || st is OrdersLoading) {
      _quietAgain = true;
      return;
    }
    // A failed list stays as the operator sees it, with its retry button.
    // A full refresh from here would flash a spinner every 30 s, and after a
    // failed status fetch it would load EVERY status under «Новые».
    if (st is! OrdersLoaded) return;

    final gen = _gen;
    _quietInFlight = true;
    try {
      final asked = _filters;
      final data = await _fetchPage(storeId: storeId, page: 1);
      final found = await _resolveExactNumber(data.items, storeId, asked);
      final cur = state;
      if (_storeId != storeId) return;
      if (gen != _gen || _loading) {
        // Stale (a scroll, tab switch or status edit happened meanwhile).
        // Fetch again rather than wait for the 30 s tick: this may be the
        // poller's one refresh for a new paid order.
        _quietAgain = true;
        return;
      }
      if (cur is! OrdersLoaded) return;

      if (asked != _filters) {
        _quietAgain = true;
        return;
      }
      if (cur.pagination.page <= 1) {
        emit(OrdersLoaded(
          items: found.items,
          pagination: data.pagination,
          filters: _filters,
          foundElsewhere: found.order,
          foundElsewhereLabel: found.label,
        ));
        return;
      }
      // The operator scrolled further. Put the fresh first page on top and
      // keep what they already loaded below it, so nothing jumps away.
      final fresh = {for (final o in found.items) o.id};
      final hidden = found.order?.id;
      emit(OrdersLoaded(
        items: [
          ...found.items,
          ...cur.items.where((o) => !fresh.contains(o.id) && o.id != hidden),
        ],
        pagination: cur.pagination,
        filters: _filters,
        foundElsewhere: found.order,
        foundElsewhereLabel: found.label,
      ));
    } catch (_) {
      // Quiet by design: the next tick or a manual refresh tries again.
    } finally {
      _quietInFlight = false;
      _runQuietAgain();
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
    _preset = preset;
    _sectionStatusIds = ids;
    final next = _filters.copyWith(statusIds: ids);
    if (next == _filters) return;
    await applyFilters(next);
  }

  /// Back to every status of the current section (the reset strip and a
  /// second tap on the highlighted section). Search and dates stay.
  Future<void> resetStatusToSection() async {
    if (!statusFilterNarrowed) return;
    await applyFilters(_filters.copyWith(statusIds: _sectionStatusIds));
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
    // The drill-down opens «Новые заказы» (home_shell) with one status on
    // top: the section is «Новые заказы», the one status is a narrowed
    // filter with its own reset.
    _preset = OrdersTabPreset.active;
    _sectionStatusIds = _idsForPreset(OrdersTabPreset.active);
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
    //
    // 1.3.2: «preserve the preset» now means the SECTION's statuses, not
    // whatever status filter is on. A status picked on top (the chip, a
    // dashboard drill-down) is cleared too, or it stays stuck (19.11).
    final preserved = _filters.copyWith(
      search: '',
      clearDateFrom: true,
      clearDateTo: true,
      statusIds: _sectionStatusIds,
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
    _gen++;
    try {
      final nextPage = st.pagination.page + 1;
      final data = await _fetchPage(storeId: _storeId!, page: nextPage);

      final hidden = st.foundElsewhere?.id;
      emit(OrdersLoaded(
        items: [...st.items, ...data.items.where((o) => o.id != hidden)],
        pagination: data.pagination,
        filters: _filters,
        foundElsewhere: st.foundElsewhere,
        foundElsewhereLabel: st.foundElsewhereLabel,
      ));
    } catch (_) {
      // молча, чтобы не ломать UX
    } finally {
      _loading = false;
      _runQuietAgain();
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

    if (st.foundElsewhere?.id == updated.id) {
      _gen++;
      emit(OrdersLoaded(
        items: st.items,
        pagination: st.pagination,
        filters: st.filters,
        foundElsewhere: updated,
        foundElsewhereLabel: foundElsewhereLabel(updated, _preset),
      ));
      return;
    }

    final idx = st.items.indexWhere((o) => o.id == updated.id);
    if (idx == -1) return;

    _gen++; // a quiet refresh fetched before this edit must not undo it
    final newList = [...st.items];
    newList[idx] = updated;
    emit(OrdersLoaded(
      items: newList,
      pagination: st.pagination,
      filters: st.filters,
      foundElsewhere: st.foundElsewhere,
      foundElsewhereLabel: st.foundElsewhereLabel,
    ));
  }

  @override
  Future<void> close() {
    _autoTimer?.cancel();
    _searchDebounce?.cancel();
    return super.close();
  }
}
