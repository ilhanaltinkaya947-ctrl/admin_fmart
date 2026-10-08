import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The per-line weight warnings (UX review §1 B1, B4, B5; §2 item 18).
///
/// Rendered and typed into, not read from source: the point of each warning is
/// what the picker SEES while the knife is still in their hand.
OrderItem weightItem({int? actualG, int ordered = 300, int cap = 315}) =>
    OrderItem.fromJson(<String, dynamic>{
      'id': 7,
      'product_id': 42,
      'qty': 6,
      'price': '155.00',
      'total': '976.00',
      'product': {'name': 'Сыр Emsar для пиццы'},
      'unit_g': 50,
      'price_per_kg': '3105.00',
      'ordered_g': ordered,
      'charged_g_cap': cap,
      if (actualG != null) 'actual_g': actualG,
    });

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  group('pure rules', () {
    test('formatGrams keeps a 1 050 g cap exact', () {
      expect(formatGrams(1050), '1,05 кг');
      expect(formatGrams(1500), '1,5 кг');
      expect(formatGrams(1000), '1 кг');
      expect(formatGrams(315), '315 г');
    });

    test('target text', () {
      expect(weightTargetText(300, 315), 'Нужно: от 300 г до 315 г');
    });

    test('80% boundary is exact', () {
      expect(weightCheck(actualG: 239, orderedG: 300, capG: 315),
          WeightCheck.under80);
      expect(weightCheck(actualG: 240, orderedG: 300, capG: 315),
          WeightCheck.underOrder);
      expect(weightCheck(actualG: 299, orderedG: 300, capG: 315),
          WeightCheck.underOrder);
      expect(weightCheck(actualG: 300, orderedG: 300, capG: 315),
          WeightCheck.inRange);
      expect(weightCheck(actualG: 315, orderedG: 300, capG: 315),
          WeightCheck.inRange);
      expect(weightCheck(actualG: 316, orderedG: 300, capG: 315),
          WeightCheck.overCap);
      expect(weightCheck(actualG: null, orderedG: 300, capG: 315),
          WeightCheck.none);
    });
  });

  group('WeightLinePanel', () {
    testWidgets('shows the target range before weighing', (t) async {
      await t.pumpWidget(host(WeightLinePanel(
        item: weightItem(),
        onWeightSet: (_) {},
      )));
      expect(find.text('Нужно: от 300 г до 315 г'), findsOneWidget);
      expect(find.byKey(const ValueKey('weight-under-order')), findsNothing);
      expect(find.byKey(const ValueKey('weight-under80')), findsNothing);
    });

    testWidgets('under the order: amber top-up line, no refund promise',
        (t) async {
      await t.pumpWidget(host(WeightLinePanel(
        item: weightItem(),
        onWeightSet: (_) {},
        refundPreview: 98,
      )));
      await t.enterText(find.byType(TextField), '270');
      await t.pump();
      expect(find.text('Меньше заказа на 30 г. Довесьте до 300 г'),
          findsOneWidget);
      final txt = t.widget<Text>(find.byKey(const ValueKey('weight-under-order')));
      expect(txt.style?.color, kWeightAmber);
      expect(find.textContaining('Вернём клиенту'), findsNothing);
      expect(find.byKey(const ValueKey('weight-under80')), findsNothing);
    });

    testWidgets('under 80%: red call prompt with the phone, copy works',
        (t) async {
      final copied = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await t.pumpWidget(host(WeightLinePanel(
        item: weightItem(),
        onWeightSet: (_) {},
        customerPhone: '+77011234567',
      )));
      await t.enterText(find.byType(TextField), '220');
      await t.pump();

      expect(find.byKey(const ValueKey('weight-under80')), findsOneWidget);
      expect(find.text('Меньше 80% заказа. Позвоните клиенту'), findsOneWidget);
      expect(find.text('+77011234567'), findsOneWidget);
      // The amber line yields to the red one.
      expect(find.byKey(const ValueKey('weight-under-order')), findsNothing);

      await t.tap(find.text('Скопировать номер'));
      await t.pump();
      expect(copied, ['+77011234567']);
      expect(find.text('Номер скопирован'), findsOneWidget);
    });

    testWidgets('under 80% from the STORED reading after a reload', (t) async {
      await t.pumpWidget(host(WeightLinePanel(
        item: weightItem(actualG: 200),
        onWeightSet: (_) {},
        customerPhone: '+77011234567',
      )));
      expect(find.byKey(const ValueKey('weight-under80')), findsOneWidget);
    });

    testWidgets('no phone: the warning stays, the copy button does not',
        (t) async {
      await t.pumpWidget(host(WeightLinePanel(
        item: weightItem(actualG: 100),
        onWeightSet: (_) {},
      )));
      expect(find.text('Меньше 80% заказа. Позвоните клиенту'), findsOneWidget);
      expect(find.text('Скопировать номер'), findsNothing);
    });

    testWidgets('read-only line: no target, no warnings', (t) async {
      await t.pumpWidget(host(WeightLinePanel(item: weightItem(actualG: 100))));
      expect(find.textContaining('Нужно:'), findsNothing);
      expect(find.byKey(const ValueKey('weight-under80')), findsNothing);
    });
  });
}
