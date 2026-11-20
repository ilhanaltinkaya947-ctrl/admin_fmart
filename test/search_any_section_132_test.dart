// 1.3.2 (case 19.11, Тулпар): a manager in «Запланированные» searched 100320
// (status processing) and the list said «Заказов нет». Another iPad sat on
// status_ids=8 alone (a dashboard drill-down) with no way back: tapping the
// highlighted section did nothing and «Сбросить фильтры» kept the status.
//
// Renders (real Noto Sans, Cyrillic + ₸) are off by default:
//   STORE_SEARCH_SHOTS=1 STORE_SEARCH_SHOTS_DIR=<dir> flutter test test/search_any_section_132_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/orders_list_page.dart';
import 'package:admin_fmart/features/orders/state/orders_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

Future<OrdersCubit> _inSection(_Repo repo, OrdersTabPreset p) async {
  final c = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
  await c.refresh(storeId: _store);
  await c.applyTabPreset(p);
  return c;
}

Future<void> _search(OrdersCubit c, String q) async {
  await c.applyFilters(c.filters.copyWith(search: q));
}

void main() {
  group('pure rules', () {
    test('only a full number (6 to 9 digits) is an order number', () {
      expect(exactOrderNumber('100320'), 100320);
      expect(exactOrderNumber(' 100320 '), 100320);
      expect(exactOrderNumber('10032'), isNull);
      expect(exactOrderNumber('1003a0'), isNull);
      expect(exactOrderNumber('Сарыарка'), isNull);
      expect(exactOrderNumber('1234567890'), isNull);
    });

    test('the label names the section the order is in', () {
      expect(foundElsewhereLabel(_order(1, status: 'processing'), OrdersTabPreset.scheduled),
          'Заказ в разделе «Новые заказы»');
      expect(foundElsewhereLabel(_order(1, status: 'completed'), OrdersTabPreset.active),
          'Заказ в разделе «История заказов»');
      expect(foundElsewhereLabel(_order(1, status: 'scheduled'), OrdersTabPreset.active),
          'Заказ в разделе «Запланированные»');
      expect(foundElsewhereLabel(_order(1, status: 'pending-payment'), OrdersTabPreset.active),
          'Заказ со статусом «Ожидает оплату»');
      expect(foundElsewhereLabel(_order(1, status: 'processing'), OrdersTabPreset.active),
          'Заказ не подходит под выбранные фильтры');
    });
  });

  group('cubit', () {
    test('19.11: «Запланированные» + 100320 (processing) finds it (old server: by id)', () async {
      final repo = _Repo()..byId = _order(100320);
      final c = await _inSection(repo, OrdersTabPreset.scheduled);
      await _search(c, '100320');
      final st = c.state as OrdersLoaded;
      expect(repo.listCalls.last.statusIds, [12]);
      expect(st.items, isEmpty);
      expect(st.foundElsewhere?.id, 100320);
      expect(st.foundElsewhereLabel, 'Заказ в разделе «Новые заказы»');
      await c.close();
    });

    test('new server already returns it in the list: moved out of the rows, labelled', () async {
      final repo = _Repo()..list = [_order(100320, status: 'completed')];
      final c = await _inSection(repo, OrdersTabPreset.scheduled);
      await _search(c, '100320');
      final st = c.state as OrdersLoaded;
      expect(st.items, isEmpty);
      expect(st.foundElsewhere?.id, 100320);
      expect(st.foundElsewhereLabel, 'Заказ в разделе «История заказов»');
      expect(repo.byIdCalls, isEmpty, reason: 'the list already had it');
      await c.close();
    });

    test('an order in the shown section stays a normal row', () async {
      final repo = _Repo()..list = [_order(100320, status: 'scheduled')];
      final c = await _inSection(repo, OrdersTabPreset.scheduled);
      await _search(c, '100320');
      final st = c.state as OrdersLoaded;
      expect(st.items.map((o) => o.id), [100320]);
      expect(st.foundElsewhere, isNull);
      await c.close();
    });

    test('another store\'s order is never shown (store mismatch or 403)', () async {
      final repo = _Repo()..byId = _order(100321, store: 3);
      final c = await _inSection(repo, OrdersTabPreset.scheduled);
      await _search(c, '100321');
      expect((c.state as OrdersLoaded).foundElsewhere, isNull);
      repo.byIdThrows = true;
      await _search(c, '100322');
      final st = c.state as OrdersLoaded;
      expect(st.foundElsewhere, isNull);
      expect(st.items, isEmpty, reason: 'a 403 is not an error screen');
      await c.close();
    });

    test('partial numbers and text keep the old search (no lookup)', () async {
      final repo = _Repo()..byId = _order(100320);
      final c = await _inSection(repo, OrdersTabPreset.scheduled);
      await _search(c, '10032');
      await _search(c, 'Сарыарка');
      expect(repo.byIdCalls, isEmpty);
      expect((c.state as OrdersLoaded).foundElsewhere, isNull);
      await c.close();
    });

    test('a drilled status is visible and resettable; «Сбросить фильтры» clears it too', () async {
      final repo = _Repo();
      final c = await _inSection(repo, OrdersTabPreset.active);
      expect(c.statusFilterNarrowed, isFalse);
      await c.applyStatusByName('partially-refunded');
      expect(c.filters.statusIds, [8]);
      expect(c.statusFilterNarrowed, isTrue);
      expect(c.narrowedStatusNames, ['Частичный возврат']);
      await c.resetStatusToSection();
      expect(c.filters.statusIds.toSet(), {2, 3, 4, 5, 8});
      expect(c.statusFilterNarrowed, isFalse);

      await c.applyStatusByName('partially-refunded');
      await _search(c, 'Сарыарка');
      await c.clearFilters();
      expect(c.filters.search, '');
      expect(c.filters.statusIds.toSet(), {2, 3, 4, 5, 8},
          reason: 'used to keep [8] for ever (19.11)');
      await c.close();
    });
  });

  group('page', () {
    Future<OrdersCubit> pump(WidgetTester t, _Repo repo, {Size size = const Size(1024, 1366)}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await t.pumpWidget(RepositoryProvider<OrdersRepository>.value(
        value: repo,
        child: BlocProvider.value(
          value: c,
          child: const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: OrdersListPage(storeId: _store, storeName: 'F-Mart Тулпар'),
          ),
        ),
      ));
      return c;
    }

    testWidgets('empty section + full number → the order with where it is, not «Заказов нет»',
        (t) async {
      final repo = _Repo()..byId = _order(100320);
      final c = await pump(t, repo);
      await t.runAsync(() async {
        await c.refresh(storeId: _store);
        await c.applyTabPreset(OrdersTabPreset.scheduled);
        await _search(c, '100320');
      });
      await t.pumpAndSettle();
      expect(find.text('Заказов нет'), findsNothing);
      expect(find.text('Заказ в разделе «Новые заказы»'), findsOneWidget);
      expect(find.text('Заказ №100320 · В обработке'), findsOneWidget);
      await c.close();
    });

    testWidgets('a narrowed status shows a strip whose button puts the section back', (t) async {
      final repo = _Repo();
      final c = await pump(t, repo);
      await t.runAsync(() async {
        await c.refresh(storeId: _store);
        await c.applyTabPreset(OrdersTabPreset.active);
        await c.applyStatusByName('partially-refunded');
      });
      await t.pumpAndSettle();
      expect(find.text('Показаны только: Частичный возврат'), findsOneWidget);
      await t.runAsync(() async {
        await t.tap(find.text('Показать все статусы'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
      expect(c.filters.statusIds.toSet(), {2, 3, 4, 5, 8});
      expect(find.text('Показаны только: Частичный возврат'), findsNothing);
      await c.close();
    });
  });

  group('renders', () {
    final enabled = Platform.environment['STORE_SEARCH_SHOTS'] == '1';
    final outDir = Platform.environment['STORE_SEARCH_SHOTS_DIR'] ?? 'build/store_search_shots';

    setUpAll(() async {
      if (!enabled) return;
      final text = FontLoader('Roboto');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        final bytes = File('test/fonts/NotoSans-$w-subset.ttf').readAsBytesSync();
        text.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await text.load();
      final manifest =
          json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
      for (final entry in manifest.cast<Map<String, dynamic>>()) {
        final family = entry['family'] as String;
        if (family == 'Roboto') continue;
        final loader = FontLoader(family);
        for (final f in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(f['asset'] as String));
        }
        await loader.load();
      }
    });

    Future<void> shot(WidgetTester t, String name) async {
      await t.pump();
      final view = t.binding.renderViews.first;
      final layer = view.debugLayer! as OffsetLayer;
      await t.runAsync(() async {
        final ui.Image img = await layer.toImage(Offset.zero & view.size);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        final f = File('$outDir/$name.png');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Future<void> scene(WidgetTester t, String name, _Repo repo,
        Future<void> Function(OrdersCubit c) act) async {
      t.view.physicalSize = const Size(1024, 1366);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await t.pumpWidget(RepositoryProvider<OrdersRepository>.value(
        value: repo,
        child: BlocProvider.value(
          value: c,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2E7D32)),
            home: const OrdersListPage(storeId: _store, storeName: 'F-Mart Тулпар'),
          ),
        ),
      ));
      await t.runAsync(() async {
        await c.refresh(storeId: _store);
        await act(c);
      });
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), c.filters.search);
      await t.pump(const Duration(milliseconds: 400));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      await shot(t, name);
      await c.close();
    }

    testWidgets('1 Запланированные + 100320: found in «Новые заказы»', (t) async {
      final repo = _Repo()..byId = _order(100320);
      await scene(t, '1_scheduled_search_100320_found', repo, (c) async {
        await c.applyTabPreset(OrdersTabPreset.scheduled);
        await _search(c, '100320');
      });
    }, skip: !enabled);

    testWidgets('2 drilled status strip + found', (t) async {
      final repo = _Repo()..byId = _order(100320, status: 'completed');
      await scene(t, '2_narrowed_status_strip_found', repo, (c) async {
        await c.applyTabPreset(OrdersTabPreset.active);
        await c.applyStatusByName('partially-refunded');
        await _search(c, '100320');
      });
    }, skip: !enabled);
  });
}
