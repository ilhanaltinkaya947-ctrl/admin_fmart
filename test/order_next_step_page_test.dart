import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// 1.3.0 S1 on the REAL order screen (critic HIGH-1: the pure function was
/// tested while an old `if (!_isPickup) return []` kept the delivery steps off
/// the page). Rendered for delivery orders, not only computed.
void main() {
  Map<String, dynamic> delivery(String status) => {
        ...weighedOrderJson(status: status),
        'fulfillment_type': 'delivery',
        'weight_settled': true,
      };

  testWidgets('a paid delivery order shows «Принять заказ» on screen', (t) async {
    await pumpOrderPage(t, fakeRepo(delivery('paid')));
    expect(find.text('Принять заказ'), findsOneWidget);
    await disposePage(t);
  });

  testWidgets('a picked delivery order shows «Заказ собран, вызвать курьера»', (t) async {
    await pumpOrderPage(t, fakeRepo(delivery('processing')));
    expect(find.text('Заказ собран, вызвать курьера'), findsOneWidget);
    await disposePage(t);
  });

  testWidgets('…and nothing once the courier owns it', (t) async {
    await pumpOrderPage(t, fakeRepo(delivery('ready-for-delivery')));
    expect(find.text('Заказ собран, вызвать курьера'), findsNothing);
    expect(find.text('Принять заказ'), findsNothing);
    await disposePage(t);
  });

  testWidgets('critic round 2: unweighed kg lines -> the reason, not the courier button', (t) async {
    await pumpOrderPage(t, fakeRepo({...delivery('processing'), 'weight_settled': false}));
    expect(find.text('Заказ собран, вызвать курьера'), findsNothing);
    expect(find.textContaining('Сначала взвесьте весовые товары'), findsWidgets);
    await disposePage(t);
  });
}
