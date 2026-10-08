import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// «Сборка завершена» moves money and freezes weights; it asks first
/// (UX review §1 B6, §2 item 17). Driven through the REAL order page, and
/// the assertion is on the settle POST itself, not a local flag.
void main() {
  group('estimateWeightRefund', () {
    OrderItem line({int? actualG}) =>
        Order.fromJson(weighedOrderJson(actualG: actualG)).items.single;

    test('uses the settle formula when there is no server preview', () {
      // paid = 155 × 6 + 46 = 976; final = floor(3105 × 270 / 1000) = 838.
      expect(estimateWeightRefund([line(actualG: 270)]), 138);
      // Over the cap bills only the cap: floor(3105 × 315 / 1000) = 978 > 976.
      expect(estimateWeightRefund([line(actualG: 400)]), 0);
    });

    test('prefers the server preview for the line', () {
      expect(
        estimateWeightRefund([line(actualG: 270)], previews: {7: 98}),
        98,
      );
    });

    test('unweighed lines add nothing', () {
      expect(estimateWeightRefund([line()]), 0);
    });
  });

  testWidgets('Отмена on the confirm sends NO settle', (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    await t.tap(find.text('Сборка завершена'));
    await settle(t);

    expect(find.text('Завершить сборку?'), findsOneWidget);
    expect(
      find.text('Вернём клиенту примерно 138 ₸ за вес. '
          'После этого вес изменить нельзя.'),
      findsOneWidget,
    );
    await t.tap(find.text('Отмена'));
    await settle(t);
    expect(repo.settleCalls, 0);
    await disposePage(t);
  });

  testWidgets('Завершить sends exactly ONE settle', (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    expect(repo.settleCalls, 0, reason: 'nothing sent before the confirm');

    await t.tap(find.text('Завершить'));
    await settle(t);
    expect(repo.settleCalls, 1);
    await disposePage(t);
  });

  testWidgets('zero refund still asks, and says no refund is due', (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 315, weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    expect(
      find.text('Возврат за вес не нужен. После этого вес изменить нельзя.'),
      findsOneWidget,
    );
    await t.tap(find.text('Отмена'));
    await settle(t);
    expect(repo.settleCalls, 0);
    await disposePage(t);
  });
}
