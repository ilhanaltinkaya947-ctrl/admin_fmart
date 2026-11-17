// 1.3.1 refund guard: refunded against owed (server `refund_summary`), the
// live over-owed check in «Возврат», the 409 `refund_over_owed` confirm step,
// and «Клиенту вернётся N ₸» before a quantity cut or a removed line.
import 'dart:convert';
import 'dart:typed_data';

import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/format/money.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/models/refund_summary.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart' show StubTokenStorage;
import 'weight_page_harness.dart';

Map<String, dynamic> summaryJson({
  String owed = '7650.00',
  String refunded = '7700.00',
  String pending = '0.00',
  String remaining = '0.00',
  String over = '50.00',
}) =>
    {
      'captured': '17050.00',
      'current_total': '9400.00',
      'owed': owed,
      'refunded': refunded,
      'pending': pending,
      'remaining_owed': remaining,
      'over_by': over,
    };

Map<String, dynamic> milkLine({int id = 21, int qty = 3}) => {
      'id': id,
      'product_id': 500 + id,
      'qty': qty,
      'price': '450.00',
      'total': (450 * qty).toStringAsFixed(2),
      'product': {'name': 'Молоко 3,2% 1 л', 'in_stock': true},
    };

Map<String, dynamic> breadLine() => {
      'id': 22,
      'product_id': 522,
      'qty': 1,
      'price': '250.00',
      'total': '250.00',
      'product': {'name': 'Хлеб белый', 'in_stock': true},
    };

/// A card order with plain (not weighed) lines; [summary] null = old server.
Map<String, dynamic> orderJson({
  String status = 'partially-refunded',
  Map<String, dynamic>? summary,
}) =>
    {
      ...weighedOrderJson(
        status: status,
        items: [milkLine(), breadLine()],
      ),
      'total_amount': '9400.00',
      'captured_amount': '17050.00',
      if (summary != null) 'refund_summary': summary,
    };

Finder get _refundButton => find.ancestor(
      of: find.text('Возврат'),
      matching: find.byWidgetPredicate((w) => w is ElevatedButton),
    );

Future<void> openSheet(WidgetTester t) async {
  await scrollTo(t, _refundButton);
  await t.tap(_refundButton);
  await settle(t);
}

Future<void> pickReason(WidgetTester t) async {
  await t.tap(find.text('Причина возврата'));
  await settle(t);
  await t.tap(find.text('Жалоба клиента').last);
  await settle(t);
}

Future<void> typeAmount(WidgetTester t, String v) async {
  await t.enterText(find.widgetWithText(TextField, 'Сумма возврата'), v);
  await t.pump();
}

Future<void> submitAndConfirm(WidgetTester t) async {
  final submit = find.byKey(const ValueKey('refund-sheet-submit'));
  await t.ensureVisible(submit);
  await t.tap(submit);
  await settle(t);
  await t.tap(find.text('Подтвердить'));
  await settle(t);
}

// ---- a fake order-service for the repository's wire format ----------------

class FakeOrderSvc implements HttpClientAdapter {
  final List<Map<String, dynamic>> bodies = [];
  int status = 200;
  Object answer = {'success': true, 'message': 'Возврат оформлен'};

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async {
    bodies.add(Map<String, dynamic>.from(o.data as Map));
    return ResponseBody.fromString(jsonEncode(answer), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

OrdersRepository wireRepo(FakeOrderSvc svc) {
  final api = ApiClient(
    baseUrl: 'http://127.0.0.1:1',
    tokenStorage: StubTokenStorage(),
    onUnauthorized: () {},
  );
  api.dio.httpClientAdapter = svc;
  api.dio.interceptors.clear();
  return OrdersRepository(api: api);
}

void main() {
  // ------------------------------------------------------------ pure rules
  group('RefundSummary', () {
    test('absent or malformed = null (old server hides everything)', () {
      expect(RefundSummary.tryParse(null), isNull);
      expect(RefundSummary.tryParse('x'), isNull);
      expect(RefundSummary.tryParse({'owed': '1.00'}), isNull);
      expect(Order.fromJson(orderJson()).refundSummary, isNull);
    });

    test('parses the string money of the contract and survives copyWith', () {
      final o = Order.fromJson(orderJson(summary: summaryJson()));
      final s = o.refundSummary!;
      expect(s.owed, 7650);
      expect(s.refunded, 7700);
      expect(s.overBy, 50);
      expect(s.captured, 17050);
      expect(o.copyWith(status: 'refunded').refundSummary, same(s));
    });

    test('over-owed only beyond the 1 ₸ tolerance', () {
      const s = RefundSummary(
          captured: 17050, currentTotal: 9400, owed: 7650, refunded: 7000);
      expect(s.overOwedBy(650), isNull);
      expect(s.overOwedBy(651), isNull);
      expect(s.overOwedBy(652), 2);
      expect(s.overOwedBy(0), isNull);
    });

    test('409 body: top-level or inside detail; anything else is not it', () {
      final top = RefundOverOwed.tryParse({
        'code': 'refund_over_owed',
        'owed': '7650.00',
        'refunded': '7700.00',
        'requested': 300,
      })!;
      expect(top.excess, 350);
      expect(top.requested, 300);
      expect(
          RefundOverOwed.tryParse({
            'detail': {
              'code': 'refund_over_owed',
              'owed': 100,
              'refunded': 0,
              'requested': 150,
            }
          })!
              .excess,
          50);
      expect(RefundOverOwed.tryParse({'detail': 'Нельзя'}), isNull);
    });

    test('copy: Russian, no dashes', () {
      const s = RefundSummary(
          captured: 17050,
          currentTotal: 9400,
          owed: 7650,
          refunded: 7700,
          overBy: 50);
      final all = [
        refundedOfOwedText(s),
        alreadyRefundedOfOwedText(refunded: 7700, owed: 7650),
        refundPendingBankText(300),
        refundOverByChipText(50),
        refundRemainingOwedText(950),
        overOwedWarningText(50),
        overOwedConfirmButtonText(300),
        itemEditRefundText(450),
      ];
      expect(refundedOfOwedText(s), 'Возвращено 7 700 ₸ из 7 650 ₸');
      expect(refundOverByChipText(50), 'Возвращено больше на 50 ₸');
      for (final line in all) {
        expect(line.contains('-') || line.contains('—') || line.contains('–'),
            isFalse,
            reason: line);
      }
    });
  });

  // ------------------------------------------------------------ wire format
  group('repository', () {
    test('confirm_over_owed: absent for an old server, else always explicit',
        () async {
      final svc = FakeOrderSvc();
      final repo = wireRepo(svc);
      // Old server (no refund_summary): the exact 1.3.0 request.
      await repo.refundOrder(
          orderId: 1, amount: 100, reason: 'Другое · x', idempotencyKey: 'k');
      // Server knows the field: false must be SENT (absent = old app = the
      // server allows and only logs, so the guard would never run).
      await repo.refundOrder(
          orderId: 1,
          amount: 100,
          reason: 'Другое · x',
          idempotencyKey: 'k',
          confirmOverOwed: false);
      await repo.refundOrder(
          orderId: 1,
          amount: 100,
          reason: 'Другое · x',
          idempotencyKey: 'k',
          confirmOverOwed: true);
      expect(svc.bodies[0].containsKey('confirm_over_owed'), isFalse);
      expect(svc.bodies[1].containsKey('confirm_over_owed'), isTrue);
      expect(svc.bodies[1]['confirm_over_owed'], false);
      expect(svc.bodies[2]['confirm_over_owed'], true);
    });

    test('409 refund_over_owed → RefundOverOwedException with the numbers',
        () async {
      final svc = FakeOrderSvc()
        ..status = 409
        ..answer = {
          'code': 'refund_over_owed',
          'owed': '7650.00',
          'refunded': '7700.00',
          'requested': '300.00',
        };
      final repo = wireRepo(svc);
      await expectLater(
        repo.refundOrder(
            orderId: 1, amount: 300, reason: 'r', idempotencyKey: 'k'),
        throwsA(isA<RefundOverOwedException>()
            .having((e) => e.numbers.excess, 'excess', 350)),
      );
    });

    test('another 409 stays a plain OrdersApiException', () async {
      final svc = FakeOrderSvc()
        ..status = 409
        ..answer = {'detail': 'Сначала взвесьте весовые товары'};
      final repo = wireRepo(svc);
      await expectLater(
        repo.refundOrder(
            orderId: 1, amount: 300, reason: 'r', idempotencyKey: 'k'),
        throwsA(isA<OrdersApiException>().having(
            (e) => e is RefundOverOwedException, 'over owed', isFalse)),
      );
    });
  });

  // ------------------------------------------------------------ order screen
  group('order screen refund block', () {
    testWidgets('old server: no block, sheet as in 1.3.0', (t) async {
      final repo = fakeRepo(orderJson());
      await pumpOrderPage(t, repo);
      expect(find.byKey(const ValueKey('refund-summary')), findsNothing);
      await openSheet(t);
      expect(find.byKey(const ValueKey('refund-sheet-already')), findsNothing);
      await typeAmount(t, '7000');
      expect(find.byKey(const ValueKey('refund-over-owed-warning')),
          findsNothing);
      expect(find.text('Оформить'), findsOneWidget);
      await pickReason(t);
      await submitAndConfirm(t);
      expect(repo.refundConfirmFlags, [null],
          reason: 'old server: no confirm_over_owed key at all');
      await disposePage(t);
    });

    testWidgets('exact: refunded = owed, no chips', (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(refunded: '7650.00', over: '0.00')));
      await pumpOrderPage(t, repo);
      final line = find.text(refundedOfOwedText(
          const RefundSummary(
              captured: 0, currentTotal: 0, owed: 7650, refunded: 7650)));
      await scrollTo(t, line);
      expect(line, findsOneWidget);
      expect(find.byKey(const ValueKey('refund-summary-over')), findsNothing);
      expect(find.byKey(const ValueKey('refund-summary-remaining')),
          findsNothing);
      expect(
          find.byKey(const ValueKey('refund-summary-pending')), findsNothing);
      await disposePage(t);
    });

    testWidgets('under: «Осталось вернуть»', (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '6700.00', remaining: '950.00', over: '0.00')));
      await pumpOrderPage(t, repo);
      final rem = find.text(refundRemainingOwedText(950));
      await scrollTo(t, rem);
      expect(rem, findsOneWidget);
      expect(find.byKey(const ValueKey('refund-summary-over')), findsNothing);
      await disposePage(t);
    });

    testWidgets('over: warning chip', (t) async {
      final repo = fakeRepo(orderJson(summary: summaryJson()));
      await pumpOrderPage(t, repo);
      final chip = find.text('Возвращено больше на 50 ₸');
      await scrollTo(t, chip);
      expect(chip, findsOneWidget);
      await disposePage(t);
    });

    testWidgets('pending: «Ещё уходит в банк»', (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '6650.00', pending: '1000.00', over: '0.00')));
      await pumpOrderPage(t, repo);
      final p = find.text(refundPendingBankText(1000));
      await scrollTo(t, p);
      expect(p, findsOneWidget);
      await disposePage(t);
    });
  });

  // ------------------------------------------------------------ refund sheet
  group('refund sheet', () {
    testWidgets('within owed: plain «Оформить», no flag', (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '6700.00', remaining: '950.00', over: '0.00')));
      await pumpOrderPage(t, repo);
      await openSheet(t);
      expect(
          find.text(alreadyRefundedOfOwedText(refunded: 6700, owed: 7650)),
          findsOneWidget);
      // Prefilled with what is still owed.
      expect(find.widgetWithText(TextField, 'Сумма возврата'), findsOneWidget);
      expect(find.text('950.00'), findsOneWidget);
      await pickReason(t);
      expect(find.text('Оформить'), findsOneWidget);
      await submitAndConfirm(t);
      expect(repo.refundCalls, 1);
      expect(repo.refundConfirmFlags, [false]);
      await disposePage(t);
    });

    testWidgets('over owed: inline warning, confirm button sends the flag',
        (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '6700.00', remaining: '950.00', over: '0.00')));
      await pumpOrderPage(t, repo);
      await openSheet(t);
      await pickReason(t);
      await typeAmount(t, '1000');
      expect(find.text(overOwedWarningText(50)), findsOneWidget);
      expect(find.text(overOwedConfirmButtonText(1000)), findsOneWidget);
      expect(find.text('Оформить'), findsNothing);
      // Back within owed: the warning goes, the plain button returns.
      await typeAmount(t, '951');
      expect(find.byKey(const ValueKey('refund-over-owed-warning')),
          findsNothing);
      expect(find.text('Оформить'), findsOneWidget);
      await typeAmount(t, '1000');
      await submitAndConfirm(t);
      expect(repo.refundConfirmFlags, [true]);
      expect(repo.refundAmounts, [1000]);
      await disposePage(t);
    });

    testWidgets('409 refund_over_owed: confirm step with the server numbers',
        (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '6700.00', remaining: '950.00', over: '0.00')))
        ..refundErrorOnce = true
        ..refundError = RefundOverOwedException(const RefundOverOwed(
            owed: 7650, refunded: 7400, requested: 900));
      await pumpOrderPage(t, repo);
      await openSheet(t);
      await pickReason(t);
      await typeAmount(t, '900');
      await submitAndConfirm(t);
      // Not a generic error: the confirm step, the server's numbers.
      expect(find.byKey(const ValueKey('refund-over-owed-dialog')),
          findsOneWidget);
      expect(
          find.text(alreadyRefundedOfOwedText(refunded: 7400, owed: 7650)),
          findsOneWidget);
      expect(find.text(overOwedWarningText(650)), findsOneWidget);
      expect(find.text('Не удалось оформить возврат'), findsNothing);
      await t.tap(find.text(overOwedConfirmButtonText(900)));
      await settle(t);
      expect(repo.refundConfirmFlags, [false, true]);
      expect(repo.refundKeys.toSet().length, 1,
          reason: 'the confirmed retry is the same refund');
      await disposePage(t);
    });

    testWidgets('409 confirm step: «Назад» sends nothing more', (t) async {
      final repo = fakeRepo(orderJson(summary: summaryJson()))
        ..refundErrorOnce = true
        ..refundError = RefundOverOwedException(const RefundOverOwed(
            owed: 7650, refunded: 7700, requested: 100));
      await pumpOrderPage(t, repo, role: 'admin');
      await openSheet(t);
      await pickReason(t);
      await typeAmount(t, '100');
      // Already over: the sheet itself asks first.
      expect(find.text(overOwedConfirmButtonText(100)), findsOneWidget);
      await submitAndConfirm(t);
      expect(find.byKey(const ValueKey('refund-over-owed-dialog')),
          findsOneWidget);
      await t.tap(find.text('Назад'));
      await settle(t);
      expect(repo.refundCalls, 1);
      await disposePage(t);
    });
  });

  // ------------------------------------------------------------ item edits
  group('item edits', () {
    testWidgets('quantity cut: «Клиенту вернётся» the removed units',
        (t) async {
      final repo = fakeRepo(orderJson(status: 'processing'));
      await pumpOrderPage(t, repo);
      final minus = find.descendant(
        of: find.ancestor(
            of: find.text('Молоко 3,2% 1 л'), matching: find.byType(Card)),
        matching: find.byIcon(Icons.remove),
      );
      await scrollTo(t, minus);
      await t.tap(minus);
      await settle(t);
      expect(find.text(itemEditRefundText(450)), findsOneWidget);
      expect(find.text('Клиенту вернётся 450 ₸'), findsOneWidget);
      await t.tap(find.text('Назад'));
      await settle(t);
      await disposePage(t);
    });

    testWidgets('remove line: «Клиенту вернётся» the line total', (t) async {
      final repo = fakeRepo(orderJson(status: 'processing'));
      await pumpOrderPage(t, repo);
      final del = find.descendant(
        of: find.ancestor(
            of: find.text('Молоко 3,2% 1 л'), matching: find.byType(Card)),
        matching: find.byTooltip('Удалить'),
      );
      await scrollTo(t, del);
      await t.tap(del);
      await settle(t);
      expect(find.text(itemEditRefundText('1350.00')), findsOneWidget);
      expect(find.text('Убрать и вернуть ${formatTenge(1350)}'), findsOneWidget);
      await t.tap(find.text('Назад'));
      await settle(t);
      await disposePage(t);
    });
  });

  // ---- review fixes of 2b452b2 ----------------------------------------

  group('review HIGH: fresh summary, explicit flag', () {
    testWidgets('sheet re-reads the order: another iPad refunded meanwhile',
        (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '0.00', remaining: '7650.00', over: '0.00')));
      await pumpOrderPage(t, repo);
      // iPad A refunds 7 650; this screen still holds the old summary.
      repo.detail = orderJson(
          summary: summaryJson(refunded: '7650.00', over: '0.00'));
      final before = repo.getCalls;
      await openSheet(t);
      expect(repo.getCalls, greaterThan(before));
      expect(
          find.text(alreadyRefundedOfOwedText(refunded: 7650, owed: 7650)),
          findsOneWidget);
      // Nothing owed any more: no prefill, and 7 650 again is over owed.
      expect(find.text('7650.00'), findsNothing);
      await typeAmount(t, '7650');
      expect(find.text(overOwedWarningText(7650)), findsOneWidget);
      await disposePage(t);
    });

    testWidgets('fetch fails: cached summary, flag still sent as false',
        (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '6700.00', remaining: '950.00', over: '0.00')));
      await pumpOrderPage(t, repo);
      repo.getError = Exception('offline');
      await openSheet(t);
      expect(
          find.text(alreadyRefundedOfOwedText(refunded: 6700, owed: 7650)),
          findsOneWidget);
      await pickReason(t);
      await submitAndConfirm(t);
      expect(repo.refundConfirmFlags, [false]);
      await disposePage(t);
    });

    testWidgets('after a refund the summary updates at once', (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '6700.00', remaining: '950.00', over: '0.00')));
      repo.onRefund = () => repo.detail = orderJson(
          summary: summaryJson(refunded: '7650.00', over: '0.00'));
      await pumpOrderPage(t, repo);
      await openSheet(t);
      await pickReason(t);
      await submitAndConfirm(t);
      final line = find.text(refundedOfOwedText(const RefundSummary(
          captured: 0, currentTotal: 0, owed: 7650, refunded: 7650)));
      await scrollTo(t, line);
      expect(line, findsOneWidget);
      await disposePage(t);
    });

    test('pending is inside refunded (server field meaning): not added twice',
        () {
      // refund_summary.py: refunded = every counted row (sent, in flight,
      // held); pending = the part of refunded not yet sent.
      const s = RefundSummary(
          captured: 17050,
          currentTotal: 9400,
          owed: 7650,
          refunded: 7650,
          pending: 1000);
      expect(s.overOwedBy(1), isNull);
      expect(s.overOwedBy(2), 2);
    });
  });

  group('review MED: a full refund is never over owed', () {
    test('rule', () {
      const s = RefundSummary(
          captured: 17050, currentTotal: 9400, owed: 7650, refunded: 0);
      expect(overOwedForRefund(s, 17050, remainingOnCard: 17050), isNull);
      expect(overOwedForRefund(s, 9000, remainingOnCard: 17050), 1350);
      expect(overOwedForRefund(null, 9000, remainingOnCard: 17050), isNull);
    });

    testWidgets('amount empties the card: plain «Оформить», flag false',
        (t) async {
      final repo = fakeRepo(orderJson(
          summary: summaryJson(
              refunded: '0.00', remaining: '7650.00', over: '0.00')));
      await pumpOrderPage(t, repo, role: 'admin');
      await openSheet(t);
      await pickReason(t);
      await typeAmount(t, '17050');
      expect(find.byKey(const ValueKey('refund-over-owed-warning')),
          findsNothing);
      expect(find.text('Оформить'), findsOneWidget);
      await submitAndConfirm(t);
      expect(repo.refundConfirmFlags, [false]);
      await disposePage(t);
    });
  });

  group('review LOW: unedited order (goodwill)', () {
    testWidgets('no «Уже возвращено 0 из 0», softer warning', (t) async {
      final repo = fakeRepo(orderJson(
          status: 'processing',
          summary: summaryJson(
              owed: '0.00',
              refunded: '0.00',
              remaining: '0.00',
              over: '0.00')));
      await pumpOrderPage(t, repo);
      await openSheet(t);
      expect(find.byKey(const ValueKey('refund-sheet-already')), findsNothing);
      await typeAmount(t, '100');
      expect(
          find.text('Заказ не менялся. Возврат будет сверх суммы изменений: 100 ₸'),
          findsOneWidget);
      expect(find.textContaining('больше, чем клиенту положено'), findsNothing);
      await disposePage(t);
    });
  });

  group('review LOW: comma money', () {
    test('formatTenge reads "145,00"', () {
      expect(formatTenge('145,00'), '145 ₸');
      expect(formatTenge('1350,50'), '1 350,5 ₸');
    });

    testWidgets('remove line with a comma total names the money', (t) async {
      final line = milkLine()..['total'] = '1350,00';
      final repo = fakeRepo({
        ...orderJson(status: 'processing'),
        'items': [line, breadLine()],
      });
      await pumpOrderPage(t, repo);
      final del = find.descendant(
        of: find.ancestor(
            of: find.text('Молоко 3,2% 1 л'), matching: find.byType(Card)),
        matching: find.byTooltip('Удалить'),
      );
      await scrollTo(t, del);
      await t.tap(del);
      await settle(t);
      expect(find.text('Клиенту вернётся 1 350 ₸'), findsOneWidget);
      await t.tap(find.text('Назад'));
      await settle(t);
      await disposePage(t);
    });
  });
}
