// 1.3.2 (case 19.11, Тулпар): a manager in «Запланированные» searched 100320
// (status processing) and the list said «Заказов нет». Another iPad sat on
// status_ids=8 alone (a dashboard drill-down) with no way back: tapping the
// highlighted section did nothing and «Сбросить фильтры» kept the status.
//
// Only the API that 1.3.1 already had, so this file compiles on 1.3.1 and
// fails there by assertion (the sibling file pins the new API).

import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/orders_list_page.dart';
import 'package:admin_fmart/features/orders/state/orders_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

const _store = 5;

// Prod ids (order_status, 20.11).
const _statusIds = {
  'pending-payment': 1,
  'paid': 2,
  'processing': 3,
  'ready-for-delivery': 4,
  'delivering': 5,
  'completed': 6,
  'canceled': 7,
  'partially-refunded': 8,
  'refunded': 9,
  'payment-failed': 10,
  'payment-timeout': 11,
  'scheduled': 12,
};

Map<String, dynamic> _json(int id, {String status = 'processing', int store = _store}) => {
      'id': id,
      'customer_id': 2,
      'status': status,
      'total_amount': '5480',
      'delivery_sum': '600',
      'store_id': store,
      'store_name': 'F-Mart Тулпар',
      'delivery_address': 'мкр. Тулпар, ул. Сарыарка 17, кв. 4',
      'fulfillment_type': 'delivery',
      'customer_comment': '',
      'payment_method': 'card',
      'is_promo': false,
      'created_at': '2026-11-19T08:41:00Z',
      'updated_at': '2026-11-19T08:52:00Z',
      'customer_first_name': 'Айгерим',
      'customer_phone_last4': '5678',
      'items': <dynamic>[],
    };

Order _order(int id, {String status = 'processing', int store = _store}) =>
    Order.fromJson(_json(id, status: status, store: store));

OrdersPage _page(List<Order> items) => OrdersPage(
      pagination: Pagination(
        page: 1,
        pageSize: 20,
        total: items.length,
        pages: items.isEmpty ? 0 : 1,
        hasNext: false,
        hasPrev: false,
      ),
      items: items,
    );

class _Repo implements OrdersRepository {
  /// What GET /admin/orders answers (any filters).
  List<Order> list = [];

  /// What GET /admin/orders/{id} answers; null = 404; [byIdThrows] = 403.
  Order? byId;
  bool byIdThrows = false;
  final List<int> byIdCalls = [];
  final List<({List<int>? statusIds, String? search})> listCalls = [];

  @override
  Future<OrderStatusesResponse> getOrderStatuses() async => OrderStatusesResponse(
        items: [
          for (final e in _statusIds.entries)
            OrderStatusDto(id: e.value, statusName: e.key, createdAt: DateTime(2026)),
        ],
      );

  @override
  Future<OrdersPage> getOrders({
    required int storeId,
    required int page,
    required int perPage,
    int? customerId,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<int>? statusIds,
    String? paymentMethod,
    String? search,
  }) async {
    listCalls.add((statusIds: statusIds, search: search));
    return _page(list);
  }

  @override
  Future<Order?> getOrderById({required int storeId, required int orderId}) async {
    byIdCalls.add(orderId);
    if (byIdThrows) throw Exception('403 Не ваш магазин');
    return byId?.id == orderId ? byId : null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<OrdersCubit> _pump(WidgetTester t, _Repo repo) async {
  t.view.physicalSize = const Size(1024, 1366);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final c = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
  await t.pumpWidget(RepositoryProvider<OrdersRepository>.value(
    value: repo,
    child: BlocProvider.value(
      value: c,
      child: const MaterialApp(
        home: OrdersListPage(storeId: _store, storeName: 'F-Mart Тулпар'),
      ),
    ),
  ));
  return c;
}

void main() {
  testWidgets('19.11: «Запланированные» + 100320 shows the order, not «Заказов нет»', (t) async {
    final repo = _Repo()..byId = _order(100320);
    final c = await _pump(t, repo);
    await t.runAsync(() async {
      await c.refresh(storeId: _store);
      await c.applyTabPreset(OrdersTabPreset.scheduled);
      await c.applyFilters(c.filters.copyWith(search: '100320'));
    });
    await t.pumpAndSettle();
    expect(find.text('Заказов нет'), findsNothing);
    expect(find.text('Заказ №100320 · В обработке'), findsOneWidget);
    await c.close();
  });

  testWidgets('another store\'s order found by number is NOT shown', (t) async {
    final repo = _Repo()..byId = _order(100321, store: 3);
    final c = await _pump(t, repo);
    await t.runAsync(() async {
      await c.refresh(storeId: _store);
      await c.applyTabPreset(OrdersTabPreset.scheduled);
      await c.applyFilters(c.filters.copyWith(search: '100321'));
    });
    await t.pumpAndSettle();
    expect(find.textContaining('Заказ №100321'), findsNothing);
    expect(find.text('Заказов нет'), findsOneWidget);
    await c.close();
  });

  test('«Сбросить фильтры» after a dashboard drill-down puts the section back', () async {
    final repo = _Repo();
    final c = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
    await c.refresh(storeId: _store);
    await c.applyTabPreset(OrdersTabPreset.active);
    await c.applyStatusByName('partially-refunded');
    expect(c.filters.statusIds, [8]);
    await c.applyFilters(c.filters.copyWith(search: 'Сарыарка'));
    await c.clearFilters();
    expect(c.filters.statusIds.toSet(), {2, 3, 4, 5, 8});
    await c.close();
  });
}
