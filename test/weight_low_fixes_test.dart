import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// Review LOWs: fixture arithmetic, the typed-value hint, and the settle
/// outcome when nothing is left to refund.
void main() {
  test('fixture arithmetic: 930 + 46 = 976 paid; 270 g refunds 138', () {
    final it = OrderItem.fromJson(cheeseLine());
    expect(it.removalRefund, 976);
    expect(weightLineRefund(it, 270), 138);
    expect(cheesePreview(270), 138);
    // 315 g (the cap) costs floor(3105 × 315 / 1000) = 978 > 976 paid: 0.
    expect(weightLineRefund(it, 315), 0);
    expect(weightLineRefund(it, 300), 976 - 931);
  });

  testWidgets('the «доплатил заранее» hint follows the typed figure',
      (t) async {
    // Saved 300 g with the server's preview for 300 g (45 ₸) ...
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WeightLinePanel(
          item: OrderItem.fromJson(cheeseLine(actualG: 300)),
          onWeightSet: (_) {},
          refundPreview: 45,
        ),
      ),
    ));
    expect(find.text('Клиент доплатил заранее, возврат 45 ₸'), findsOneWidget);
    // ... now 310 is typed: 976 − floor(3105 × 310 / 1000) = 976 − 962 = 14.
    await t.enterText(find.byType(TextField), '310');
    await t.pump();
    expect(find.text('Клиент доплатил заранее, возврат 14 ₸'), findsOneWidget);
    expect(find.text('Клиент доплатил заранее, возврат 45 ₸'), findsNothing);
  });

  group('settleOutcomeText', () {
    WeightSettleResult res({
      double due = 138,
      double already = 0,
      double refund = 0,
      bool published = false,
    }) =>
        WeightSettleResult(
          orderId: 1,
          weightLines: 1,
          due: due,
          alreadySettled: already,
          refundAmount: refund,
          refundPublished: published,
          lines: const [],
        );

    test('nothing left on the capture: no refund needed, not support', () {
      final text = settleOutcomeText(res(), remainingCapture: 0);
      expect(text, contains('Возврат не нужен'));
      expect(text, isNot(contains('поддержку')));
    });

    test('capture left but nothing published: still a support case', () {
      expect(settleOutcomeText(res(), remainingCapture: 500),
          contains('Передайте в поддержку'));
    });

    test('published refund', () {
      expect(settleOutcomeText(res(refund: 138, published: true)),
          'Вернём клиенту 138 ₸');
    });
  });
}
