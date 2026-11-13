import 'package:admin_fmart/core/services/order_watcher.dart';
import 'package:admin_fmart/core/widgets/unaccepted_bar.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Store app 1.3.0 S2: the red «Не приняты» bar above every screen.
NewOrderItem _o(int id, DateTime createdUtc) =>
    NewOrderItem(id: id, status: 'paid', storeId: 5, createdGmt: createdUtc.toIso8601String());

void main() {
  tearDown(() => unacceptedOrders.value = const []);

  test('Russian plural of «заказ»', () {
    expect([1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 111].map(ordersWord).toList(), [
      '1 заказ', '2 заказа', '4 заказа', '5 заказов', '11 заказов', '12 заказов',
      '14 заказов', '21 заказ', '22 заказа', '25 заказов', '111 заказов',
    ]);
  });

  test('the text names the oldest wait', () {
    final now = DateTime.utc(2026, 11, 13, 20, 0);
    expect(unacceptedText([_o(1, now.subtract(const Duration(minutes: 12)))], now),
        'Не принят: 1 заказ · ждёт 12 мин');
    expect(
        unacceptedText([
          _o(1, now.subtract(const Duration(minutes: 12))),
          _o(2, now.subtract(const Duration(minutes: 3))),
        ], now),
        'Не приняты: 2 заказа · ждут 12 мин');
  });

  test('a missing or future time never shows a negative wait', () {
    final now = DateTime.utc(2026, 11, 13, 20, 0);
    expect(waitedMinutes(NewOrderItem(id: 1, status: 'paid', storeId: 5), now), 0);
    expect(waitedMinutes(_o(1, now.add(const Duration(minutes: 5))), now), 0);
  });

  testWidgets('no waiting order: no bar, the screen is untouched', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: UnacceptedBarFrame(onOpen: (_) {}, child: const Text('экран')),
    ));
    expect(find.text('экран'), findsOneWidget);
    expect(find.textContaining('Не принят'), findsNothing);
  });

  testWidgets('waiting orders: the bar shows, a tap opens the OLDEST', (tester) async {
    final opened = <int>[];
    final now = DateTime.now().toUtc();
    await tester.pumpWidget(MaterialApp(
      home: UnacceptedBarFrame(onOpen: opened.add, child: const Text('экран')),
    ));
    unacceptedOrders.value = [
      _o(100091, now.subtract(const Duration(minutes: 9))),
      _o(100095, now.subtract(const Duration(minutes: 2))),
    ];
    await tester.pump();
    expect(find.text('Не приняты: 2 заказа · ждут 9 мин'), findsOneWidget);
    expect(find.text('экран'), findsOneWidget, reason: 'the screen stays under the bar');
    await tester.tap(find.text('Открыть'));
    expect(opened, [100091]);
    unacceptedOrders.value = const [];
    await tester.pump();
    expect(find.textContaining('Не принят'), findsNothing);
  });
}
