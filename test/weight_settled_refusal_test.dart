import 'package:admin_fmart/core/api/api_errors.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// 409 «Расчёт по весу уже выполнен» (order-service, after another iPad or an
/// earlier tap settled the order) reads as a plain decision with NO
/// «Повторить», and the screen reloads into the settled state.
void main() {
  const putRefusal = 'Расчёт по весу уже выполнен: вес больше не меняется';
  const removeRefusal = 'Расчёт по весу уже выполнен: весовую позицию '
      'нельзя убрать, оформите возврат вручную';

  group('pure mapping', () {
    test('recognised only as a 409 carrying the phrase', () {
      expect(isWeightAlreadySettledRefusal(409, putRefusal), isTrue);
      expect(isWeightAlreadySettledRefusal(409, removeRefusal), isTrue);
      expect(isWeightAlreadySettledRefusal(422, putRefusal), isFalse);
      expect(isWeightAlreadySettledRefusal(409, 'Заказ уже закрыт'), isFalse);
      expect(isWeightAlreadySettledRefusal(409, null), isFalse);
    });

    test('two plain sentences, the server tail kept', () {
      expect(weightAlreadySettledText(putRefusal),
          'Расчёт по весу уже выполнен. Вес больше не меняется.');
      expect(
          weightAlreadySettledText(removeRefusal),
          'Расчёт по весу уже выполнен. Весовую позицию нельзя убрать, '
          'оформите возврат вручную.');
      expect(weightAlreadySettledText('Расчёт по весу уже выполнен'),
          'Расчёт по весу уже выполнен. Вес больше не меняется.');
    });
  });

  testWidgets('weight PUT refused: clear message, no retry, screen freezes',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(weightSettled: false));
    repo.weightError = OrdersApiException(putRefusal, statusCode: 409);
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.widgetWithText(TextField, 'Факт, г'));

    // Meanwhile another iPad settled it; the refetch will say so.
    repo.detail = weighedOrderJson(
        actualG: 300, weightSettled: true, weightRefundAmount: '0.00');
    await t.enterText(find.widgetWithText(TextField, 'Факт, г'), '300');
    await t.pump();
    final save = find.descendant(
      of: find.byType(WeightLinePanel),
      matching: find.widgetWithText(FilledButton, 'Сохранить'),
    );
    await t.ensureVisible(save);
    await t.tap(save);
    await settle(t);

    expect(repo.weightPuts, [300]);
    expect(find.text('Расчёт по весу уже выполнен. Вес больше не меняется.'),
        findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    // Not left as a red error under a field that can no longer save.
    expect(find.text(putRefusal), findsNothing);
    expect(find.widgetWithText(TextField, 'Факт, г'), findsNothing);
    await disposePage(t);
  });

  testWidgets('settle refused: clear message, no retry', (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 300, weightSettled: false));
    repo.settleError = OrdersApiException(putRefusal, statusCode: 409);
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    await t.tap(find.text('Завершить'));
    await settle(t);

    expect(repo.settleCalls, 1);
    expect(find.text('Расчёт по весу уже выполнен. Вес больше не меняется.'),
        findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    await disposePage(t);
  });
}
