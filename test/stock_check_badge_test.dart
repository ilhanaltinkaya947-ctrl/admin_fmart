// «Проверьте наличие» (26.10): the order line badge reads order-service's
// stock_check verdict; without one (older server) it reads in_stock as before.
// Since the dropdown (same day) the answered labels are «В наличии» / «Нет в
// наличии» and the reasons carry a «⚠ »; see stock_check_dropdown_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/widgets/order_item_card.dart';

Map<String, dynamic> _line({bool inStock = true, Object? check}) => {
      'id': 8423,
      'product_id': 66505,
      'qty': 1,
      'price': '1775.00',
      'total': '1775.00',
      'product': {'name': 'Яйцо Аймар 30шт', 'sku': '4870', 'image_url': null, 'in_stock': inStock, 'on_sale': false},
      if (check != null) 'stock_check': check,
    };

Future<void> _pump(WidgetTester t, OrderItem item) => t.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: OrderItemCard(item: item))),
    ));

void main() {
  test('parse: tolerant, absent = null', () {
    expect(OrderItem.fromJson(_line()).stockCheck, isNull);
    expect(OrderItem.fromJson(_line(check: 'junk')).stockCheck, isNull);
    final c = OrderItem.fromJson(_line(check: {'level': 'check', 'reasons': ['в 1С было 1 шт', 7]})).stockCheck!;
    expect(c.needsCheck, isTrue);
    expect(c.reasons, ['в 1С было 1 шт']);
  });

  test('copyWith keeps the verdict (picking a line must not drop it)', () {
    final it = OrderItem.fromJson(_line(check: {'level': 'check', 'reasons': ['x']}));
    expect(it.copyWith(pickedAt: DateTime(2026, 10, 26)).stockCheck?.level, 'check');
  });

  testWidgets('check: amber badge and the reasons', (t) async {
    await _pump(t, OrderItem.fromJson(_line(inStock: false,
        check: {'level': 'check', 'reasons': ['в 1С было 1 шт', 'не хватало 2 раз за 14 дней']})));
    expect(find.text('Проверьте наличие'), findsOneWidget);
    expect(find.text('Нет'), findsNothing);
    expect(find.text('⚠ в 1С было 1 шт · не хватало 2 раз за 14 дней'), findsOneWidget);
  });

  testWidgets('confirmed and missing', (t) async {
    await _pump(t, OrderItem.fromJson(_line(check: {'level': 'confirmed', 'reasons': []})));
    expect(find.text('В наличии'), findsOneWidget);
    await _pump(t, OrderItem.fromJson(_line(inStock: true, check: {'level': 'missing', 'reasons': []})));
    expect(find.text('Нет в наличии'), findsOneWidget);
  });

  testWidgets('older server: the yes/no badge exactly as before', (t) async {
    await _pump(t, OrderItem.fromJson(_line(inStock: true)));
    expect(find.text('В наличии'), findsOneWidget);
    await _pump(t, OrderItem.fromJson(_line(inStock: false)));
    expect(find.text('Нет'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-check-reasons')), findsNothing);
  });
}
