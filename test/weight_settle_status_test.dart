import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// Review H2a. «Сборка завершена» is offered in every status order-service
/// settles in (`_WEIGHT_SETTLE_STATUSES`: paid, processing,
/// ready-for-delivery, delivering, completed, partially-refunded). Weight
/// fields stay editable only in paid/processing. An ever-completed order is
/// settled by an admin only (the server 403s managers).
void main() {
  Future<void> open(
    WidgetTester t,
    FakeOrdersRepository repo, {
    String role = 'manager',
  }) async {
    await pumpOrderPage(t, repo, role: role);
    await scrollTo(t, find.text('Весовые товары'));
    await t.drag(
      find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first,
      const Offset(0, -200),
    );
    await settle(t);
  }

  for (final status in ['ready-for-delivery', 'delivering']) {
    testWidgets('$status: read-only weight, settle button live, settles once',
        (t) async {
      final repo = fakeRepo(weighedOrderJson(
          status: status, actualG: 270, weightSettled: false));
      await open(t, repo);
      expect(find.widgetWithText(TextField, 'Факт, г'), findsNothing);
      expect(find.text('Факт: 270 г'), findsOneWidget);
      // The cut rules are for the knife; past picking they are noise.
      expect(find.textContaining('Отрежьте не меньше заказа'), findsNothing);
      await t.tap(find.text('Сборка завершена'));
      await settle(t);
      await t.tap(find.text('Завершить'));
      await settle(t);
      expect(repo.settleCalls, 1);
      await disposePage(t);
    });
  }

  testWidgets('completed, manager: no button, says the admin does it',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(
        status: 'completed', closed: true, actualG: 270, weightSettled: false));
    await open(t, repo);
    expect(find.text('Сборка завершена'), findsNothing);
    expect(find.text('Расчёт по закрытому заказу делает администратор'),
        findsOneWidget);
    await disposePage(t);
  });

  testWidgets('completed, admin: the button, and it settles', (t) async {
    final repo = fakeRepo(weighedOrderJson(
        status: 'completed', closed: true, actualG: 270, weightSettled: false));
    await open(t, repo, role: 'admin');
    expect(find.byKey(const ValueKey('settle-admin-only')), findsNothing);
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    await t.tap(find.text('Завершить'));
    await settle(t);
    expect(repo.settleCalls, 1);
    await disposePage(t);
  });

  testWidgets('partially refunded while picking, then settled by a manager',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(
        status: 'processing', actualG: 270, weightSettled: false));
    await open(t, repo);
    expect(find.text('Сборка завершена'), findsOneWidget);

    // A partial refund lands (another line was out of stock); the poll brings
    // the new status. The order never completed, so it is not admin-only.
    repo.detail = weighedOrderJson(
        status: 'partially-refunded', actualG: 270, weightSettled: false);
    await t.pump(const Duration(seconds: 9));
    await settle(t);
    expect(find.text('Сборка завершена'), findsOneWidget);
    expect(find.byKey(const ValueKey('settle-admin-only')), findsNothing);
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    await t.tap(find.text('Завершить'));
    await settle(t);
    expect(repo.settleCalls, 1);
    await disposePage(t);
  });

  testWidgets('partially refunded AFTER completion, manager: admin only',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(
        status: 'partially-refunded',
        closed: true,
        actualG: 270,
        weightSettled: false));
    await open(t, repo);
    expect(find.text('Сборка завершена'), findsNothing);
    expect(find.byKey(const ValueKey('settle-admin-only')), findsOneWidget);
    await disposePage(t);
  });

  testWidgets('refunded: no settle bar at all', (t) async {
    final repo = fakeRepo(weighedOrderJson(
        status: 'refunded', closed: true, actualG: 270, weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Товары'));
    expect(find.text('Весовые товары'), findsNothing);
    await disposePage(t);
  });
}
