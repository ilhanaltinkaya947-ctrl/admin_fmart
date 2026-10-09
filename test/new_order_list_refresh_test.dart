import 'dart:async';

import 'package:admin_fmart/core/services/new_order_dialog_guard.dart';
import 'package:admin_fmart/core/services/order_watcher.dart';
import 'package:admin_fmart/core/services/sound_service.dart';
import 'package:admin_fmart/core/storage/prefs_storage.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/models/order_filters.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/state/orders_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Order 1095, 2026-10-09: the store iPad rang, but the order was not in the
/// list until staff pulled it down. Three causes, one test group each:
///   * the poller marked an order "alarmed" BEFORE checking whether a dialog
///     was already open, so the push dialog swallowed the poll's alarm;
///   * the poller never refreshed the list;
///   * the list never refreshed by itself.
/// The push is sent at order creation, a few seconds before payment, so the
/// refresh after the push dialog read the paid list too early.

Map<String, dynamic> _orderJson(int id, {String status = 'paid'}) => {
      'id': id,
      'customer_id': 2,
      'status': status,
      'total_amount': '1000',
      'delivery_sum': '0',
      'store_id': 3,
      'store_name': 'F-Mart Фиркан Сити',
      'delivery_address': 'просп. Тауке хана 330',
      'fulfillment_type': 'delivery',
      'customer_comment': '',
      'payment_method': 'card',
      'is_promo': false,
      'created_at': '2026-10-09T11:01:57Z',
      'updated_at': '2026-10-09T11:02:01Z',
      'items': <dynamic>[],
    };

Order _order(int id, {String status = 'paid'}) =>
    Order.fromJson(_orderJson(id, status: status));

OrdersPage _page(List<int> ids, {int page = 1, bool hasNext = false}) =>
    OrdersPage(
      pagination: Pagination(
        page: page,
        pageSize: 20,
        total: ids.length,
        pages: 1,
        hasNext: hasNext,
        hasPrev: page > 1,
      ),
      items: [for (final id in ids) _order(id)],
    );

NewOrdersResponse _paid(List<int> ids) => NewOrdersResponse(
      hasNew: ids.isNotEmpty,
      storeId: 3,
      sinceUsed: '2026-10-09T10:27:18Z',
      count: ids.length,
      orders: [
        for (final id in ids)
          NewOrderItem(id: id, status: 'paid', storeId: 3),
      ],
    );

class _Prefs implements PrefsStorage {
  @override
  Future<int?> getSelectedStoreId() async => 3;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Sound implements SoundService {
  int rings = 0;

  @override
  Future<void> ring() async => rings++;

  @override
  Future<void> stop() async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The poll answers in order from [polls]; the last one repeats.
/// getOrders answers from [pages] (or [pageCompleters] when a test needs to
/// hold a request open).
class _Repo implements OrdersRepository {
  _Repo({this.polls = const [], this.pages = const []});

  List<NewOrdersResponse> polls;
  List<OrdersPage> pages;
  final List<Completer<OrdersPage>> pageCompleters = [];
  int pollCalls = 0;
  final List<({int page, List<int>? statusIds})> orderCalls = [];
  bool failOrders = false;

  @override
  Future<NewOrdersResponse> getNewOrders({
    required int storeId,
    DateTime? since,
    int minutes = 10,
    int limit = 20,
    List<String>? statuses,
    String tz = 'Asia/Almaty',
  }) async {
    final i = pollCalls < polls.length ? pollCalls : polls.length - 1;
    pollCalls++;
    return polls[i];
  }

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
    orderCalls.add((page: page, statusIds: statusIds));
    if (pageCompleters.isNotEmpty) return pageCompleters.removeAt(0).future;
    if (failOrders) throw Exception('network');
    final i = orderCalls.length - 1 < pages.length
        ? orderCalls.length - 1
        : pages.length - 1;
    return pages[i];
  }

  @override
  Future<Order?> getOrderById({required int storeId, required int orderId}) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(newOrderDialogGuard.resetForTest);
  tearDown(newOrderDialogGuard.resetForTest);

  group('OrderWatcher', () {
    late GlobalKey<NavigatorState> nav;
    late _Sound sound;
    late List<int> refreshedFor;

    Future<OrderWatcher> startWatcher(WidgetTester tester, _Repo repo) async {
      nav = GlobalKey<NavigatorState>();
      sound = _Sound();
      refreshedFor = [];
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const SizedBox()));
      final w = OrderWatcher(
        prefsStorage: _Prefs(),
        ordersRepository: repo,
        sound: sound,
        navigatorKey: nav,
        onNewOrders: refreshedFor.add,
      );
      w.start(interval: const Duration(seconds: 10));
      await tester.pump();
      await tester.pump();
      return w;
    }

    testWidgets(
        'an order paid while the push dialog is open is alarmed once it closes '
        '(it used to be marked first and never alarmed)', (tester) async {
      // The push dialog for an OLDER order (1094) holds the slot.
      expect(newOrderDialogGuard.tryAcquire(), isTrue);
      newOrderDialogGuard.markShown(1094);

      final repo = _Repo(polls: [_paid([1095])]);
      final w = await startWatcher(tester, repo);

      expect(find.text('Заказ #1095 • paid'), findsNothing);
      expect(sound.rings, 0);
      expect(refreshedFor, [3], reason: 'the list refreshes even while the slot is busy');

      newOrderDialogGuard.release(); // operator closes the push dialog
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.text('Заказ #1095 • paid'), findsOneWidget);
      expect(sound.rings, 1);
      expect(refreshedFor, [3], reason: 'one list refresh per order, not per tick');

      await tester.tap(find.text('Позже'));
      await tester.pumpAndSettle();
      await w.stop();
    });

    testWidgets(
        'an order the push already showed is not alarmed again when it turns '
        'paid, but the list still refreshes for it', (tester) async {
      newOrderDialogGuard.markShown(1095); // push at creation, dialog closed

      final repo = _Repo(polls: [_paid([1095])]);
      final w = await startWatcher(tester, repo);

      expect(find.textContaining('Заказ #1095'), findsNothing);
      expect(sound.rings, 0);
      expect(refreshedFor, [3]);
      await w.stop();
    });

    testWidgets('each new paid order refreshes the list exactly once',
        (tester) async {
      newOrderDialogGuard.markShown(1095);
      newOrderDialogGuard.markShown(1096);

      final repo = _Repo(polls: [
        _paid([1095]),
        _paid([1095]),
        _paid([1096, 1095]),
        _paid([1096, 1095]),
      ]);
      final w = await startWatcher(tester, repo);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 10));
        await tester.pump();
      }

      expect(repo.pollCalls, 4);
      expect(refreshedFor, [3, 3]);
      await w.stop();
    });

    testWidgets('a poll while our own dialog is open still refreshes the list',
        (tester) async {
      final repo = _Repo(polls: [
        _paid([1095]),
        _paid([1096, 1095]),
      ]);
      final w = await startWatcher(tester, repo);
      expect(find.text('Заказ #1095 • paid'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10)); // dialog still open
      await tester.pump();

      expect(repo.pollCalls, 2, reason: 'polling carries on under the dialog');
      expect(refreshedFor, [3, 3]);
      expect(sound.rings, 1, reason: 'no second dialog on top of the first');

      await tester.tap(find.text('Позже'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text('Заказ #1096 • paid'), findsOneWidget,
          reason: '1096 is alarmed after the first dialog closes');
      await tester.tap(find.text('Позже'));
      await tester.pumpAndSettle();
      await w.stop();
    });
  });

  group('OrdersCubit.refreshQuietly', () {
    test('adds the new order without a loading state', () async {
      final repo = _Repo(pages: [_page([1094]), _page([1095, 1094])]);
      final cubit = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await cubit.refresh(storeId: 3);

      final seen = <OrdersState>[];
      final sub = cubit.stream.listen(seen.add);
      await cubit.refreshQuietly(storeId: 3);
      await Future<void>.delayed(Duration.zero);

      expect(seen.whereType<OrdersLoading>(), isEmpty);
      final st = cubit.state as OrdersLoaded;
      expect(st.items.map((o) => o.id), [1095, 1094]);
      await sub.cancel();
      await cubit.close();
    });

    test('a failed quiet refresh keeps the list the operator had', () async {
      final repo = _Repo(pages: [_page([1094])]);
      final cubit = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await cubit.refresh(storeId: 3);
      repo.failOrders = true;

      await cubit.refreshQuietly(storeId: 3);

      expect(cubit.state, isA<OrdersLoaded>());
      expect((cubit.state as OrdersLoaded).items.map((o) => o.id), [1094]);
      await cubit.close();
    });

    test('a failed list is left with its error, not reloaded every 30 s',
        () async {
      final repo = _Repo(pages: [_page([1094])])..failOrders = true;
      final cubit = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await cubit.refresh(storeId: 3);
      expect(cubit.state, isA<OrdersFailure>());

      final seen = <OrdersState>[];
      final sub = cubit.stream.listen(seen.add);
      await cubit.refreshQuietly(storeId: 3);
      await Future<void>.delayed(Duration.zero);

      expect(repo.orderCalls.length, 1);
      expect(seen, isEmpty, reason: 'no spinner, no reload under «Новые»');
      await sub.cancel();
      await cubit.close();
    });

    test('a quiet refresh for another store does nothing', () async {
      final repo = _Repo(pages: [_page([1094])]);
      final cubit = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await cubit.refresh(storeId: 3);

      await cubit.refreshQuietly(storeId: 5);

      expect(repo.orderCalls.length, 1);
      await cubit.close();
    });

    test('a quiet refresh that lands after a tab switch is dropped', () async {
      final repo = _Repo(pages: [_page([1094])]);
      final cubit = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await cubit.refresh(storeId: 3);

      final quiet = Completer<OrdersPage>();
      final tab = Completer<OrdersPage>();
      final again = Completer<OrdersPage>();
      repo.pageCompleters
        ..add(quiet)
        ..add(tab)
        ..add(again);

      final q = cubit.refreshQuietly(storeId: 3); // in flight
      final f = cubit.applyFilters(OrderFilters.empty.copyWith(statusIds: [8]));
      tab.complete(_page([2000]));
      await f;
      quiet.complete(_page([1095, 1094])); // stale: fetched before the switch
      await q;

      expect((cubit.state as OrdersLoaded).items.map((o) => o.id), [2000],
          reason: 'the stale rows never reach the screen');
      expect(repo.orderCalls.length, 4, reason: 'fetched again');
      expect(repo.orderCalls.last.statusIds, [8],
          reason: 'with the tab the operator is on now');
      again.complete(_page([2001, 2000]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as OrdersLoaded).items.map((o) => o.id), [2001, 2000]);
      await cubit.close();
    });

    test('a quiet refresh does not undo a status the operator just changed',
        () async {
      final repo = _Repo(pages: [_page([1095])]);
      final cubit = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await cubit.refresh(storeId: 3);

      final quiet = Completer<OrdersPage>();
      final again = Completer<OrdersPage>();
      repo.pageCompleters
        ..add(quiet)
        ..add(again);
      final q = cubit.refreshQuietly(storeId: 3);
      cubit.updateOrderInList(_order(1095, status: 'processing'));
      quiet.complete(_page([1095])); // still says paid
      await q;

      expect((cubit.state as OrdersLoaded).items.single.status, 'processing',
          reason: 'the stale answer is dropped');
      expect(repo.orderCalls.length, 3,
          reason: 'and fetched again instead of waiting 30 s');
      again.complete(OrdersPage(
        pagination: _page([]).pagination,
        items: [_order(1096), _order(1095, status: 'processing')],
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as OrdersLoaded).items.map((o) => o.id), [1096, 1095]);
      await cubit.close();
    });

    test('the poller\'s refresh is not lost behind a refresh already running',
        () async {
      final repo = _Repo(pages: [_page([1094])]);
      final cubit = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await cubit.refresh(storeId: 3);

      // The refresh after the push dialog: sent at 16:02:00, before payment.
      final early = Completer<OrdersPage>();
      final again = Completer<OrdersPage>();
      repo.pageCompleters
        ..add(early)
        ..add(again);
      final r = cubit.refresh(storeId: 3);
      // 16:02:02: the poller sees 1095 paid while that refresh is running.
      await cubit.refreshQuietly(storeId: 3);
      early.complete(_page([1094])); // the early answer has no 1095
      await r;
      expect(repo.orderCalls.length, 3, reason: 'the quiet refresh ran again');
      again.complete(_page([1095, 1094]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as OrdersLoaded).items.map((o) => o.id), [1095, 1094]);
      await cubit.close();
    });

    test('after scrolling, the fresh first page goes on top and loaded rows stay',
        () async {
      final repo = _Repo(pages: [
        _page([30, 29], hasNext: true),
        _page([28, 27], page: 2),
        _page([31, 30, 29]),
      ]);
      final cubit = OrdersCubit(ordersRepository: repo, autoRefreshEvery: null);
      await cubit.refresh(storeId: 3);
      await cubit.loadMore();

      await cubit.refreshQuietly(storeId: 3);

      final st = cubit.state as OrdersLoaded;
      expect(st.items.map((o) => o.id), [31, 30, 29, 28, 27]);
      expect(st.pagination.page, 2, reason: 'loadMore continues from page 3');
      await cubit.close();
    });
  });

  testWidgets('the loaded list re-reads page 1 every 30 s by itself',
      (tester) async {
    final repo = _Repo(pages: [_page([1094]), _page([1095, 1094])]);
    final cubit = OrdersCubit(ordersRepository: repo);
    await cubit.refresh(storeId: 3);
    expect(repo.orderCalls.length, 1);

    await tester.pump(const Duration(seconds: 29));
    expect(repo.orderCalls.length, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repo.orderCalls.length, 2);
    expect((cubit.state as OrdersLoaded).items.map((o) => o.id), [1095, 1094]);

    cubit.reset(); // logout stops it
    await tester.pump(const Duration(seconds: 60));
    expect(repo.orderCalls.length, 2);
    await cubit.close();
  });
}
