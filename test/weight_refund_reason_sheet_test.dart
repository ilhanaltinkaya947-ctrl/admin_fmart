import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// Review H2b, rendered: the refund sheet on an order with a profiled weight
/// line offers «Разница по весу» to an admin and not to a manager.
void main() {
  final refundButton = find.ancestor(
    of: find.text('Возврат'),
    matching: find.byWidgetPredicate((w) => w is ElevatedButton),
  );

  Future<void> openSheet(WidgetTester t, String role) async {
    final repo = fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
    await pumpOrderPage(t, repo, role: role);
    await scrollTo(t, refundButton);
    await t.tap(refundButton);
    await settle(t);
    expect(find.text('Причина возврата'), findsOneWidget,
        reason: 'the refund sheet did not open');
    // Open the reason dropdown so its items are built.
    await t.tap(find.text('Причина возврата'));
    await settle(t);
    expect(find.text('Нет в наличии'), findsWidgets);
  }

  testWidgets('admin sees «Разница по весу»', (t) async {
    await openSheet(t, 'admin');
    expect(find.text('Разница по весу'), findsWidgets);
    await disposePage(t);
  });

  testWidgets('manager does not', (t) async {
    await openSheet(t, 'manager');
    expect(find.text('Разница по весу'), findsNothing);
    await disposePage(t);
  });
}
