import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// Review M3: the settle estimate follows the server's current reading and
/// nets what was already returned for weight.
void main() {
  OrderItem line(int g) => OrderItem.fromJson(cheeseLine(actualG: g));

  test('nets the weight refund already returned, never below zero', () {
    expect(estimateWeightRefund([line(270)]), 138);
    expect(estimateWeightRefund([line(270)], alreadyRefunded: 38), 100);
    expect(estimateWeightRefund([line(270)], alreadyRefunded: 200), 0);
  });

  testWidgets('a poll that changes the reading drops the old preview',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.widgetWithText(TextField, 'Факт, г'));
    await t.enterText(find.widgetWithText(TextField, 'Факт, г'), '270');
    await t.pump();
    await t.tap(find.descendant(
      of: find.byType(Card),
      matching: find.widgetWithText(FilledButton, 'Сохранить'),
    ));
    await settle(t);

    // Another iPad re-weighs to 310 g. 976 − floor(3105 × 310 / 1000) = 14.
    repo.detail = weighedOrderJson(actualG: 310, weightSettled: false);
    await t.pump(const Duration(seconds: 9));
    await settle(t);

    await scrollTo(t, find.text('Сборка завершена'));
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    expect(
      find.text('Вернём клиенту примерно 14 ₸ за вес. '
          'После этого вес изменить нельзя.'),
      findsOneWidget,
    );
    await t.tap(find.text('Отмена'));
    await settle(t);
    await disposePage(t);
  });

  testWidgets('the confirm nets an earlier manual weight refund', (t) async {
    final repo = fakeRepo(weighedOrderJson(
        actualG: 270, weightSettled: false, weightRefundAmount: '38.00'));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    expect(
      find.text('Вернём клиенту примерно 100 ₸ за вес. '
          'После этого вес изменить нельзя.'),
      findsOneWidget,
    );
    await t.tap(find.text('Отмена'));
    await settle(t);
    await disposePage(t);
  });
}
