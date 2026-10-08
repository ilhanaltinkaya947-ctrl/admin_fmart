import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// A weighed line can be removed again (review H1). Without it, an unweighed
/// cheese that is not on the shelf blocks «Сборка завершена» forever: the
/// server refuses to settle with a line unweighed.
void main() {
  test('removal refund of a weight line includes the buffer (976, not 930)',
      () {
    final it = OrderItem.fromJson(cheeseLine());
    expect(it.removalRefund, 976);
    final piece = OrderItem.fromJson(<String, dynamic>{
      'id': 1, 'product_id': 1, 'qty': 2, 'price': '450.00', 'total': '900.00',
      'product': {'name': 'Молоко'},
    });
    expect(piece.removalRefund, 900);
  });

  Finder removeOf(String name) => find.descendant(
        of: find.ancestor(
          of: find.text(name),
          matching: find.byType(Card),
        ),
        matching: find.byTooltip('Удалить'),
      );

  testWidgets('unweighed cheese → remove → repo remove → order can settle',
      (t) async {
    final repo = fakeRepo(weighedOrderJson(
      weightSettled: false,
      items: [
        cheeseLine(id: 7, actualG: 270),
        cheeseLine(id: 8, name: 'Сыр Гауда весовой'),
      ],
    ));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.text('Сборка завершена'));
    // Blocked: one line has no weight.
    expect(find.text('Осталось взвесить 1 позицию из 2'), findsOneWidget);

    await scrollTo(t, removeOf('Сыр Гауда весовой'));
    await t.tap(removeOf('Сыр Гауда весовой'));
    await settle(t);
    // The existing confirm names the real refund, buffer included.
    expect(find.text('Убрать и вернуть 976 ₸'), findsOneWidget);
    await t.tap(find.text('Убрать и вернуть 976 ₸'));
    await settle(t);
    expect(repo.removeCalls, [8]);
    expect(find.text('Сыр Гауда весовой'), findsNothing);

    await scrollTo(t, find.text('Сборка завершена'));
    await t.tap(find.text('Сборка завершена'));
    await settle(t);
    await t.tap(find.text('Завершить'));
    await settle(t);
    expect(repo.settleCalls, 1);
    await disposePage(t);
  });

  testWidgets('a settled weight line has no remove control', (t) async {
    final repo = fakeRepo(weighedOrderJson(
      weightSettled: true,
      weightRefundAmount: '138.00',
      items: [cheeseLine(id: 7, actualG: 270), cheeseLine(id: 8, actualG: 300)],
    ));
    await pumpOrderPage(t, repo);
    await scrollTo(t, find.byKey(const ValueKey('weight-settle-subtitle')));
    expect(find.byTooltip('Удалить'), findsNothing);
    await disposePage(t);
  });

  testWidgets('panel shows remove only when given one and editable', (t) async {
    var removed = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WeightLinePanel(
          item: OrderItem.fromJson(cheeseLine()),
          onWeightSet: (_) {},
          onRemove: () => removed++,
        ),
      ),
    ));
    await t.tap(find.byTooltip('Удалить'));
    expect(removed, 1);
  });
}
