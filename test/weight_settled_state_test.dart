import 'package:admin_fmart/core/format/money.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// The settled state comes from the server's `weight_settled`, not from the
/// screen's memory (UX review §1 B7, §2 item 16). Each page test opens the
/// order FRESH, the way a reload or a second iPad would: `_settleResult` is
/// empty, so only the server field can say «settled».
void main() {
  group('Order.fromJson weight fields', () {
    test('present', () {
      final o = Order.fromJson(
          weighedOrderJson(weightSettled: true, weightRefundAmount: '98.00'));
      expect(o.weightSettled, isTrue);
      expect(o.weightRefundAmount, '98.00');
    });

    test('absent key is UNKNOWN (null), not false', () {
      final o = Order.fromJson(weighedOrderJson());
      expect(o.weightSettled, isNull);
      expect(o.weightRefundAmount, isNull);
    });

    test('malformed value reads as unknown, never throws', () {
      final o = Order.fromJson(weighedOrderJson(weightSettled: 'yes'));
      expect(o.weightSettled, isNull);
    });

    test('copyWith keeps both', () {
      final o = Order.fromJson(
              weighedOrderJson(weightSettled: true, weightRefundAmount: '98.00'))
          .copyWith(status: 'ready-for-delivery');
      expect(o.weightSettled, isTrue);
      expect(o.weightRefundAmount, '98.00');
    });
  });

  test('settledBarText', () {
    expect(settledBarText('98.00'), 'Расчёт выполнен · Возврат 98 ₸');
    expect(settledBarText('1250.50'),
        'Расчёт выполнен · Возврат ${formatTenge('1250.50')}');
    expect(settledBarText('0.00'), 'Расчёт выполнен');
    expect(settledBarText(null), 'Расчёт выполнен');
  });

  testWidgets('after a reload: settled line, no weight field, no settle button',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(
      actualG: 270,
      weightSettled: true,
      weightRefundAmount: '98.00',
    ));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.byKey(const ValueKey('weight-settle-subtitle')));

    expect(find.text('Расчёт выполнен · Возврат 98 ₸'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Факт, г'), findsNothing);
    expect(find.text('Сборка завершена'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Расчёт выполнен'), findsNothing);
    expect(find.textContaining('Нужно:'), findsNothing);
    expect(find.text('Факт: 270 г'), findsOneWidget);
    await disposePage(t);
  });

  testWidgets('server says NOT settled: fields and the button are live',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    expect(find.widgetWithText(TextField, 'Факт, г'), findsOneWidget);
    expect(find.text('Сборка завершена'), findsOneWidget);
    await disposePage(t);
  });

  testWidgets('missing key: behaves as before (editable, button live)',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    expect(find.widgetWithText(TextField, 'Факт, г'), findsOneWidget);
    expect(find.textContaining('Возврат 98'), findsNothing);
    await disposePage(t);
  });

  testWidgets('a poll that turns settled freezes an open screen', (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    expect(find.widgetWithText(TextField, 'Факт, г'), findsOneWidget);

    // Another iPad settles; the next 8 s poll brings the server's truth.
    repo.detail = weighedOrderJson(
        actualG: 270, weightSettled: true, weightRefundAmount: '98.00');
    await t.pump(const Duration(seconds: 9));
    await settle(t);
    expect(find.widgetWithText(TextField, 'Факт, г'), findsNothing);
    expect(find.text('Расчёт выполнен · Возврат 98 ₸'), findsOneWidget);
    await disposePage(t);
  });
}
