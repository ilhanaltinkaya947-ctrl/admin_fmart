// Round 2 (07.11) admin fixes, from 08_sweep_admin_ops.md and the lane
// contracts B and C. Every group here fails on 1.2.7 (69) e8a89d8.
import 'dart:io';

import 'package:admin_fmart/core/services/staff_push.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:dio/dio.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/models/refund_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// The page's status list as the server sends it (renumbered ids, by name).
class _StatusRepo extends FakeOrdersRepository {
  _StatusRepo({required super.api, required super.detail});

  @override
  Future<OrderStatusesResponse> getOrderStatuses() async =>
      OrderStatusesResponse(items: [
        for (final (i, n) in const [
          'pending-payment',
          'paid',
          'processing',
          'ready-for-delivery',
          'delivering',
          'completed',
          'canceled',
          'payment-failed',
          'refunded',
          'partially-refunded',
          'scheduled',
        ].indexed)
          OrderStatusDto(id: i + 1, statusName: n, createdAt: DateTime.utc(2026)),
      ]);
}

/// A refund ledger the test controls (GET /admin/orders/{id}/refunds).
class _LedgerRepo extends FakeOrdersRepository {
  _LedgerRepo({required super.api, required super.detail});
  List<RefundHistoryEntry> ledger = const [];
  List<RefundHistoryEntry> ledgerAfterRefund = const [];

  @override
  Future<List<RefundHistoryEntry>> getRefundHistory({required int orderId}) async =>
      ledger;

  @override
  Future<SimpleActionResponse> refundOrder({
    required int orderId,
    required double amount,
    required String reason,
    required String idempotencyKey,
    List<int> oosProductIds = const [],
  }) async {
    final r = await super.refundOrder(
        orderId: orderId,
        amount: amount,
        reason: reason,
        idempotencyKey: idempotencyKey,
        oosProductIds: oosProductIds);
    ledger = ledgerAfterRefund;
    return r;
  }
}

/// «Выпустить» answers as the test says.
class _ReleaseRepo extends FakeOrdersRepository {
  _ReleaseRepo({required super.api, required super.detail});
  OrdersApiException? releaseError;
  int releaseCalls = 0;

  @override
  Future<SimpleActionResponse> releaseOrder({required int orderId}) async {
    releaseCalls++;
    final e = releaseError;
    if (e != null) throw e;
    detail = {...detail, 'status': 'paid'};
    return SimpleActionResponse(
        success: true, message: 'Заказ выпущен и передан в сборку');
  }
}

RefundHistoryEntry _row(int id, DateTime at) => RefundHistoryEntry(
    id: id, amount: 100, reason: 'Жалоба клиента', createdBy: 1, createdAt: at);

_StatusRepo _statusRepo(Map<String, dynamic> detail) {
  final base = fakeRepo(detail);
  return _StatusRepo(api: base.api, detail: detail);
}

String _handler(String src, String marker) {
  final i = src.indexOf(marker);
  expect(i, greaterThan(-1), reason: '$marker not found');
  return src.substring(i, src.indexOf('};', i));
}

void main() {
  // ---------------------------------------------------------------- 1. push kind
  group('contract B: only new_order (or no kind) rings', () {
    test('new_order and a missing kind ring, everything else is quiet', () {
      expect(isNewOrderPush({'order_id': 1, 'type': 'order'}), isTrue,
          reason: 'an older server sends no kind: keep the siren');
      expect(isNewOrderPush({'order_id': 1, 'kind': null}), isTrue);
      expect(isNewOrderPush({'order_id': 1, 'kind': ''}), isTrue);
      expect(isNewOrderPush({'order_id': 1, 'kind': 'new_order'}), isTrue);
      expect(isNewOrderPush({'order_id': 1, 'kind': ' NEW_ORDER '}), isTrue);
      for (final k in [
        'customer_confirmed',
        'status_changed',
        'refund',
        'order_modified',
        'substitution',
        'something_new',
      ]) {
        expect(isNewOrderPush({'order_id': 1, 'kind': k}), isFalse, reason: k);
      }
    });

    test('the quiet banner uses the push text, then a per-kind line', () {
      expect(
        quietStaffPushText({'kind': 'customer_confirmed'},
            title: 'Клиент подтвердил заказ',
            body: 'Заказ №100000: состав подтверждён, можно собирать.'),
        'Клиент подтвердил заказ. Заказ №100000: состав подтверждён, можно собирать.',
      );
      expect(quietStaffPushText({'kind': 'customer_confirmed'}, orderId: 7),
          'Клиент подтвердил заказ №7');
      expect(quietStaffPushText({'kind': 'refund'}, orderId: 7),
          'Возврат по заказу №7');
      expect(quietStaffPushText({'kind': 'status_changed'}, orderId: 7),
          'Статус заказа №7 изменился');
      expect(quietStaffPushText({'kind': 'x'}), 'Новое уведомление');
      for (final k in ['customer_confirmed', 'status_changed', 'refund',
          'order_modified', 'substitution', 'x']) {
        final s = quietStaffPushText({'kind': k}, orderId: 1);
        expect(s.contains('—') || s.contains(' - ') || s.contains('–'), isFalse,
            reason: 'no dashes in RU copy: $s');
        expect(s.contains('Новый заказ'), isFalse);
      }
    });

    // app.dart's handlers are closures over the OneSignal SDK, so the
    // placement is pinned in the source, as morning_check_test does.
    final app = File('lib/app.dart').readAsStringSync();

    test('foreground: a non-new_order push returns before counter, siren, '
        'markShown and the dialog', () {
      final h = _handler(app, 'onForegroundNotification =');
      final branch = h.indexOf('if (!isNewOrderPush(data))');
      expect(branch, greaterThan(-1), reason: 'no kind gate in the handler');
      final ret = h.indexOf('return;', branch);
      for (final step in [
        '_newOrderCounter.bump()',
        '_sound.ring()',
        'markShown(',
        'showDialog(',
      ]) {
        expect(h.indexOf(step), greaterThan(ret),
            reason: '$step runs before the quiet branch returns');
      }
      expect(h.substring(branch, ret), contains('_showQuietStaffPush('));
      // The morning check stays first.
      expect(h.indexOf('if (isMorningCheckPush(data))'), lessThan(branch));
    });

    test('quiet banner refreshes the list and never rings', () {
      final i = app.indexOf('Future<void> _showQuietStaffPush(');
      expect(i, greaterThan(-1));
      final body = app.substring(i, app.indexOf('\n  }\n', i));
      expect(body, contains('refreshQuietly('));
      expect(body, contains('quietStaffPushText('));
      for (final bad in ['_sound.ring()', 'showDialog(', 'markShown(',
          '_newOrderCounter.bump()', 'Новый заказ']) {
        expect(body.contains(bad), isFalse, reason: bad);
      }
    });

    test('tap: counter and markShown only for a new order', () {
      final h = _handler(app, 'onNotificationClick = (data) async {');
      expect(h, contains('final isNewOrder = isNewOrderPush(data);'));
      expect(h, contains('if (isNewOrder) _newOrderCounter.bump();'));
      expect(h, contains('if (isNewOrder) newOrderDialogGuard.markShown(orderId);'));
      expect(RegExp(r'^\s*_newOrderCounter\.bump\(\);', multiLine: true)
          .hasMatch(h), isFalse, reason: 'an unconditional bump is back');
    });

    test('iOS presents only a new order or the morning check in the '
        'foreground (no siren sound for a quiet kind)', () {
      expect(shouldDisplayForegroundPush({'order_id': 1}), isTrue);
      expect(shouldDisplayForegroundPush({'kind': 'new_order'}), isTrue);
      expect(shouldDisplayForegroundPush({'type': 'morning_check'}), isTrue);
      expect(shouldDisplayForegroundPush({'kind': 'customer_confirmed'}), isFalse);
      final svc =
          File('lib/core/services/onesignal_service.dart').readAsStringSync();
      expect(svc, contains(
          'if (shouldDisplayForegroundPush(data)) event.notification.display();'));
      expect(RegExp(r'^\s*event\.notification\.display\(\);', multiLine: true)
          .hasMatch(svc), isFalse, reason: 'an unconditional display() is back');
    });

    test('the push title and body reach the foreground handler', () {
      final svc =
          File('lib/core/services/onesignal_service.dart').readAsStringSync();
      expect(svc, contains('title: event.notification.title,'));
      expect(svc, contains('body: event.notification.body,'));
    });
  });

  // ---------------------------------------------------------------- 2. no manual paid
  group('HIGH-1: an unpaid order is never offered «Оплачен»', () {
    const all = [
      'pending-payment', 'paid', 'processing', 'ready-for-delivery',
      'delivering', 'completed', 'payment-failed', 'payment-timeout',
      'canceled', 'partially-refunded', 'refunded', 'scheduled',
    ];

    test('pending-payment offers cancel and payment-failed, never paid', () {
      for (final f in ['delivery', 'pickup']) {
        final a = adminAllowedTransitions('pending-payment', fulfillmentType: f);
        expect(a.contains('paid'), isFalse, reason: f);
        expect(a, containsAll(['canceled', 'payment-failed']));
      }
      expect(kAdminAllowedTransitions['pending-payment']!.contains('paid'),
          isFalse);
    });

    test('no status but scheduled can be moved to paid by hand', () {
      for (final s in all) {
        for (final f in ['delivery', 'pickup']) {
          final a = adminAllowedTransitions(s, fulfillmentType: f);
          expect(a.contains('paid'), s == 'scheduled',
              reason: '$s ($f) -> paid');
        }
      }
    });

    test('the send-time check refuses pending-payment -> paid', () {
      expect(isAdminTransitionAllowed('pending-payment', 'paid'), isFalse);
      expect(isAdminTransitionAllowed(' Pending-Payment ', ' PAID '), isFalse);
      expect(isAdminTransitionAllowed('pending-payment', 'canceled'), isTrue);
      expect(isAdminTransitionAllowed('scheduled', 'paid'), isTrue);
      final page = File('lib/features/orders/presentation/order_details_page.dart')
          .readAsStringSync();
      final i = page.indexOf('Future<void> _changeStatus() async {');
      final body = page.substring(i, page.indexOf('repo.changeStatus(', i));
      expect(body, contains('isAdminTransitionAllowed(_order.status, status'),
          reason: '_changeStatus must re-check before it sends');
    });

    testWidgets('rendered: the dropdown on a pending-payment order has no '
        '«Оплачен»', (t) async {
      final repo = _statusRepo(weighedOrderJson(status: 'pending-payment'));
      await pumpOrderPage(t, repo, role: 'manager');
      final dropdown = find.byWidgetPredicate(
          (w) => w is DropdownButtonFormField<String>);
      await scrollTo(t, dropdown);
      await t.tap(dropdown);
      await settle(t);
      Finder item(String v) => find.byWidgetPredicate(
          (w) => w is DropdownMenuItem<String> && w.value == v);
      expect(item('canceled'), findsWidgets,
          reason: 'the dropdown did not build its items');
      expect(item('paid'), findsNothing);
      await disposePage(t);
    });
  });

  // ---------------------------------------------------------------- 3. refund state
  group('contract C: refund_state', () {
    test('labels: «оформлен» only for done', () {
      expect(refundStateView(null), isNull);
      expect(refundStateView('none'), isNull);
      expect(refundStateView('done')!.text, 'Возврат оформлен');
      expect(refundStateView('pending')!.text, 'Возврат в обработке');
      expect(refundStateView('deferred')!.text, 'Возврат в обработке');
      expect(refundStateView('failed')!.text,
          'Возврат требует проверки, мы уже разбираемся');
      expect(refundStateView('unknown')!.text,
          'Возврат требует проверки, мы уже разбираемся');
      expect(refundStateView('retry')!.text, 'Возврат в обработке',
          reason: 'an unknown value must not claim the money is back');
    });

    test('Order parses refund_state, missing stays null, copyWith keeps it', () {
      final o = Order.fromJson({
        ...weighedOrderJson(status: 'refunded'),
        'refund_state': 'Pending',
        'refund_state_updated_at': '2026-11-07T10:59:16Z',
      });
      expect(o.refundState, 'pending');
      expect(o.refundStateUpdatedAt, DateTime.utc(2026, 11, 7, 10, 59, 16));
      expect(o.copyWith(status: 'refunded').refundState, 'pending');
      expect(Order.fromJson(weighedOrderJson()).refundState, isNull);
    });

    test('after a tap: an OLD done does not count, a newer done does', () {
      final t0 = DateTime.utc(2026, 11, 7, 10);
      final t1 = DateTime.utc(2026, 11, 7, 11);
      expect(
          refundStateViewAfterTap(
                  state: 'done', updatedAt: t0, awaiting: true, awaitingSince: t0)!
              .text,
          'Возврат в обработке');
      expect(
          refundStateViewAfterTap(
                  state: 'done', updatedAt: t1, awaiting: true, awaitingSince: t0)!
              .text,
          'Возврат оформлен');
      expect(
          refundStateViewAfterTap(
                  state: 'none', updatedAt: null, awaiting: true, awaitingSince: null)!
              .text,
          'Возврат в обработке');
      expect(
          refundStateViewAfterTap(
              state: null, updatedAt: null, awaiting: false, awaitingSince: null),
          isNull,
          reason: 'older server: today\'s behaviour');
      expect(refundWaitSettled(state: null, updatedAt: null, awaitingSince: t0),
          isFalse, reason: 'an outage (field left out) must not end the wait');
      expect(
          refundStateViewAfterTap(
                  state: null, updatedAt: null, awaiting: true, awaitingSince: t0)!
              .text,
          'Возврат в обработке');
      expect(refundWaitBaseline(t0, [t1]), t1);
      expect(refundWaitBaseline(t1, [t0]), t1);
      expect(refundWaitBaseline(null, const []), isNull);
      expect(refundWaitSettled(state: 'pending', updatedAt: t1, awaitingSince: t0),
          isFalse);
      expect(refundWaitSettled(state: 'failed', updatedAt: t1, awaitingSince: t0),
          isTrue);
      expect(refundWaitSettled(state: 'done', updatedAt: t0, awaitingSince: t0),
          isFalse);
    });

    Map<String, dynamic> order(String status, String? state, String? at) => {
          ...weighedOrderJson(status: status),
          if (state != null) 'refund_state': state,
          if (at != null) 'refund_state_updated_at': at,
        };

    for (final (state, text) in [
      ('done', 'Возврат оформлен'),
      ('pending', 'Возврат в обработке'),
      ('deferred', 'Возврат в обработке'),
      ('failed', 'Возврат требует проверки, мы уже разбираемся'),
      ('unknown', 'Возврат требует проверки, мы уже разбираемся'),
    ]) {
      testWidgets('rendered: $state shows «$text»', (t) async {
        final repo =
            fakeRepo(order('refunded', state, '2026-11-07T10:59:17Z'));
        await pumpOrderPage(t, repo, role: 'admin');
        final line = find.byKey(const ValueKey('refund-state-line'));
        await scrollTo(t, line);
        expect(find.descendant(of: line, matching: find.text(text)),
            findsOneWidget);
        await disposePage(t);
      });
    }

    testWidgets('rendered: no refund_state (older server) draws no line',
        (t) async {
      final repo = fakeRepo(order('refunded', null, null));
      await pumpOrderPage(t, repo, role: 'admin');
      expect(find.byKey(const ValueKey('refund-state-line')), findsNothing);
      await disposePage(t);
    });

    final refundButton = find.ancestor(
      of: find.text('Возврат'),
      matching: find.byWidgetPredicate((w) => w is ElevatedButton),
    );

    Future<void> tapRefund(WidgetTester t) async {
      await scrollTo(t, refundButton);
      await t.tap(refundButton);
      await settle(t);
      await t.tap(find.text('Причина возврата'));
      await settle(t);
      await t.tap(find.text('Жалоба клиента').last);
      await settle(t);
      await t.tap(find.text('Оформить'));
      await settle(t);
      await t.tap(find.text('Подтвердить'));
      await settle(t);
    }

    testWidgets('after the tap: «Возврат в обработке» until the server says '
        'done for THIS refund', (t) async {
      // An earlier partial refund is already done at 09:00.
      final repo = fakeRepo(
          order('partially-refunded', 'done', '2026-11-07T09:00:00Z'));
      await pumpOrderPage(t, repo, role: 'admin');
      await tapRefund(t);
      expect(repo.refundCalls, 1);
      expect(find.text('Возврат в обработке'), findsWidgets,
          reason: 'the toast and the line must say in processing');
      expect(find.text('Возврат оформлен'), findsNothing,
          reason: 'never «оформлен» before the bank answers');

      // The poll still sees the OLD done: keep waiting.
      await t.pump(const Duration(seconds: 9));
      await settle(t);
      final line = find.byKey(const ValueKey('refund-state-line'));
      expect(find.descendant(of: line, matching: find.text('Возврат в обработке')),
          findsOneWidget);

      // The bank answered on the new refund.
      repo.detail = order('refunded', 'done', '2026-11-07T11:00:00Z');
      await t.pump(const Duration(seconds: 9));
      await settle(t);
      expect(find.descendant(of: line, matching: find.text('Возврат оформлен')),
          findsOneWidget);
      await disposePage(t);
    });

    testWidgets('an earlier refund\'s done, newer than the old baseline but '
        'older than THIS refund\'s ledger row, does not count (critic MED-2)',
        (t) async {
      final detail = order('partially-refunded', 'done', '2026-11-07T09:00:00Z');
      final base = fakeRepo(detail);
      final repo = _LedgerRepo(api: base.api, detail: detail)
        ..ledger = [_row(1, DateTime.utc(2026, 11, 7, 8, 59))]
        ..ledgerAfterRefund = [
          _row(2, DateTime.utc(2026, 11, 7, 10, 30)),
          _row(1, DateTime.utc(2026, 11, 7, 8, 59)),
        ];
      await pumpOrderPage(t, repo, role: 'admin');
      await tapRefund(t);
      final line = find.byKey(const ValueKey('refund-state-line'));
      // Refund A finished at 10:00 before any poll; B's request row is not
      // created yet, so payment-service still says done@10:00.
      repo.detail = order('refunded', 'done', '2026-11-07T10:00:00Z');
      await t.pump(const Duration(seconds: 9));
      await settle(t);
      await scrollTo(t, line);
      expect(find.descendant(of: line, matching: find.text('Возврат в обработке')),
          findsOneWidget);
      // payment-service briefly down: the field is left out. Keep waiting.
      repo.detail = order('refunded', null, null);
      await t.pump(const Duration(seconds: 9));
      await settle(t);
      expect(find.descendant(of: line, matching: find.text('Возврат в обработке')),
          findsOneWidget);
      // B is done.
      repo.detail = order('refunded', 'done', '2026-11-07T10:31:00Z');
      await t.pump(const Duration(seconds: 9));
      await settle(t);
      expect(find.descendant(of: line, matching: find.text('Возврат оформлен')),
          findsOneWidget);
      await disposePage(t);
    });

    testWidgets('a refund tapped during a payment-service outage (key sent, '
        'value null) still waits, never «оформлен» (critic r2 MED-1)',
        (t) async {
      final detail = {...weighedOrderJson(status: 'processing'),
          'refund_state': null, 'refund_state_updated_at': null};
      final repo = fakeRepo(detail);
      await pumpOrderPage(t, repo, role: 'admin');
      await tapRefund(t);
      expect(repo.refundCalls, 1);
      expect(find.text('Возврат оформлен'), findsNothing);
      expect(find.text('Возврат в обработке'), findsWidgets);
      await disposePage(t);
    });

        testWidgets('older server (no refund_state): today\'s toast', (t) async {
      final repo = fakeRepo(order('processing', null, null));
      await pumpOrderPage(t, repo, role: 'admin');
      await tapRefund(t);
      expect(repo.refundCalls, 1);
      expect(find.text('Возврат оформлен'), findsOneWidget);
      expect(find.byKey(const ValueKey('refund-state-line')), findsNothing);
      await disposePage(t);
    });
  });

  // ---------------------------------------------------------------- 4. release
  group('contract D: «Выпустить»', () {
    test('POST /gw/order/admin/orders/{id}/release, no body', () async {
      final base = fakeRepo(weighedOrderJson());
      final sent = <RequestOptions>[];
      base.api.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
        sent.add(o);
        h.resolve(Response(
            requestOptions: o,
            statusCode: 200,
            data: {'success': true, 'message': 'Заказ уже выпущен'}));
      }));
      final repo = OrdersRepository(api: base.api);
      final r = await repo.releaseOrder(orderId: 100123);
      expect(sent.single.method, 'POST');
      expect(sent.single.path, '/gw/order/admin/orders/100123/release');
      expect(sent.single.data, isNull);
      expect(r.success, isTrue);
      expect(r.message, 'Заказ уже выпущен');
    });

    Map<String, dynamic> scheduled() => {
          ...weighedOrderJson(status: 'scheduled'),
          'scheduled_for_at': '2026-11-08T04:00:00Z',
        };
    final releaseButton = find.text('Выпустить заказ');

    Future<void> tapRelease(WidgetTester t) async {
      await scrollTo(t, releaseButton);
      await t.tap(releaseButton);
      await settle(t);
      await t.tap(find.text('Выпустить').last);
      await settle(t);
    }

    testWidgets('200: the server message, the order reloads as paid', (t) async {
      final base = fakeRepo(scheduled());
      final repo = _ReleaseRepo(api: base.api, detail: scheduled());
      await pumpOrderPage(t, repo, role: 'manager');
      await tapRelease(t);
      expect(repo.releaseCalls, 1);
      expect(find.text('Заказ выпущен и передан в сборку'), findsOneWidget);
      expect(find.text('Выпустить заказ'), findsNothing);
      await disposePage(t);
    });

    testWidgets('409: the server words, no «Повторить», the order reloads',
        (t) async {
      final base = fakeRepo(scheduled());
      final repo = _ReleaseRepo(api: base.api, detail: scheduled())
        ..releaseError = OrdersApiException(
            'Заказ уже не ждёт выпуска. Обновите экран заказа.',
            statusCode: 409);
      await pumpOrderPage(t, repo, role: 'manager');
      repo.detail = {...weighedOrderJson(status: 'canceled')};
      final before = repo.getCalls;
      await tapRelease(t);
      expect(find.text('Заказ уже не ждёт выпуска. Обновите экран заказа.'),
          findsOneWidget);
      expect(find.text('Повторить'), findsNothing,
          reason: 'a retry of a 409 can only fail again');
      expect(repo.getCalls, greaterThan(before));
      expect(find.text('Выпустить заказ'), findsNothing);
      await disposePage(t);
    });

    test('no dash in the release fallback copy', () {
      final page = File('lib/features/orders/presentation/order_details_page.dart')
          .readAsStringSync();
      expect(page.contains("'Заказ выпущен — передан в сборку'"), isFalse);
    });
  });

  // ---------------------------------------------------------------- 5. version
  group('1.2.9 (71)', () {
    test('pubspec and the push extension carry the same version', () {
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('\nversion: 1.2.9+71\n'));
      final pbx =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      // Debug, Release, Profile of the extension target.
      final blocks = pbx
          .split('isa = XCBuildConfiguration;')
          .where((b) => b.contains(
              'PRODUCT_BUNDLE_IDENTIFIER = com.fmart.admin.OneSignalNotificationServiceExtension;'))
          .toList();
      expect(blocks.length, 3);
      for (final b in blocks) {
        final head = b.split('name = ').first;
        expect(head, contains('MARKETING_VERSION = 1.2.9;'));
        expect(head, contains('CURRENT_PROJECT_VERSION = 71;'));
      }
    });
  });
}
