import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// Review M4: a weight or settle failure never shows raw English.
void main() {
  Finder field() => find.widgetWithText(TextField, 'Факт, г');

  Future<void> saveWeight(WidgetTester t, FakeOrdersRepository repo) async {
    await pumpOrderPage(t, repo);
    await scrollTo(t, field());
    await t.enterText(field(), '300');
    await t.pump();
    await t.tap(find.descendant(
      of: find.byType(Card),
      matching: find.widgetWithText(FilledButton, 'Сохранить'),
    ));
    await settle(t);
  }

  Future<void> pressSettle(WidgetTester t, FakeOrdersRepository repo) async {
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    await t.tap(find.text('Завершить'));
    await settle(t);
  }

  testWidgets('weight PUT, English 409: Russian fallback beside the field',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(weightSettled: false));
    repo.weightError = OrdersApiException(
        'Cannot enter a weight in status=delivering', statusCode: 409);
    await saveWeight(t, repo);
    expect(find.text('Не удалось сохранить вес. Попробуйте ещё раз.'),
        findsOneWidget);
    expect(find.textContaining('Cannot'), findsNothing);
    await disposePage(t);
  });

  testWidgets('weight PUT, Russian 422: the server reason as is', (t) async {
    final repo = fakeRepo(weighedOrderJson(weightSettled: false));
    repo.weightError = OrdersApiException(
        'Вес слишком большой: не больше 945 г', statusCode: 422);
    await saveWeight(t, repo);
    expect(find.text('Вес слишком большой: не больше 945 г'), findsOneWidget);
    await disposePage(t);
  });

  testWidgets('settle, English 409: Russian fallback', (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
    repo.settleError = OrdersApiException(
        'Cannot settle weights in status=refunded', statusCode: 409);
    await pressSettle(t, repo);
    expect(find.text('Не удалось рассчитать вес. Попробуйте ещё раз.'),
        findsOneWidget);
    expect(find.textContaining('Cannot'), findsNothing);
    await disposePage(t);
  });

  testWidgets('settle, Russian 403: the server reason', (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
    repo.settleError = OrdersApiException(
        'Возврат по закрытому заказу доступен только администратору.',
        statusCode: 403);
    await pressSettle(t, repo);
    expect(
        find.text('Возврат по закрытому заказу доступен только администратору.'),
        findsOneWidget);
    await disposePage(t);
  });

  testWidgets('settle, English 403: Russian, never "Admin only"', (t) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
    repo.settleError = OrdersApiException('Admin only', statusCode: 403);
    await pressSettle(t, repo);
    expect(find.text('Действие доступно только администратору.'),
        findsOneWidget);
    expect(find.text('Admin only'), findsNothing);
    await disposePage(t);
  });
}
