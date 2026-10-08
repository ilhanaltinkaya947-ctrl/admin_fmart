import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// Manager on a CLOSED order: «Возврат» is hidden (Кирилл 07.10), and a muted
/// line now says who does it instead of the button just vanishing (UX review
/// §1 B10, §2 item 23). Rendered through the real page with a real role.
void main() {
  const line = 'Возврат по закрытому заказу делает администратор';
  // ElevatedButton.icon builds a private subclass, so match by `is`.
  final refundButton = find.ancestor(
    of: find.text('Возврат'),
    matching: find.byWidgetPredicate((w) => w is ElevatedButton),
  );

  Future<void> open(WidgetTester t, {
    required String role,
    required String status,
    required bool closed,
  }) async {
    final repo = fakeRepo(weighedOrderJson(
      status: status,
      closed: closed,
      actualG: 300,
      weightSettled: true,
      weightRefundAmount: '0.00',
    ));
    await pumpOrderPage(t, repo, role: role);
  }

  testWidgets('manager, completed order: the line, no button', (t) async {
    await open(t, role: 'manager', status: 'completed', closed: true);
    await scrollTo(t, find.byKey(const ValueKey('refund-admin-only')));
    expect(find.text(line), findsOneWidget);
    expect(refundButton, findsNothing);
    await disposePage(t);
  });

  testWidgets('manager, partially refunded but once completed: the line',
      (t) async {
    await open(t, role: 'manager', status: 'partially-refunded', closed: true);
    await scrollTo(t, find.byKey(const ValueKey('refund-admin-only')));
    expect(find.text(line), findsOneWidget);
    await disposePage(t);
  });

  testWidgets('admin, completed order: the button, no line', (t) async {
    await open(t, role: 'admin', status: 'completed', closed: true);
    await scrollTo(t, refundButton);
    expect(find.text(line), findsNothing);
    await disposePage(t);
  });

  testWidgets('manager, live order: the button, no line', (t) async {
    await open(t, role: 'manager', status: 'processing', closed: false);
    await scrollTo(t, refundButton);
    expect(find.text(line), findsNothing);
    await disposePage(t);
  });

  testWidgets('manager, fully refunded: neither (nothing left to refund)',
      (t) async {
    await open(t, role: 'manager', status: 'refunded', closed: true);
    await scrollTo(t, find.text('Товары'));
    expect(find.text(line), findsNothing);
    expect(refundButton, findsNothing);
    await disposePage(t);
  });
}
