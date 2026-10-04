import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/weight_format.dart';

/// Weight lines in the admin app (part A).
///
/// The load-bearing test here is `isWeightLine`, because the SERVER decides
/// which lines are weighed and refunded. If the app disagreed with it, a picker
/// would be offered a «Факт, г» box for a line the server refuses to weigh — or
/// denied one for a line the server will refuse to settle without, which blocks
/// «Сборка завершена» on an order that looks complete.
void main() {
  Map<String, dynamic> line({
    Object? unitG,
    Object? pricePerKg,
    Object? orderedG,
    Object? chargedGCap,
    Object? actualG,
    Object? uom,
    String total = '1023.00',
  }) =>
      <String, dynamic>{
        'id': 7,
        'product_id': 42,
        'qty': 6,
        'price': '155.00',
        'total': total,
        'product': {'name': 'Сыр Emsar для пиццы'},
        if (unitG != null) 'unit_g': unitG,
        if (pricePerKg != null) 'price_per_kg': pricePerKg,
        if (orderedG != null) 'ordered_g': orderedG,
        if (chargedGCap != null) 'charged_g_cap': chargedGCap,
        if (actualG != null) 'actual_g': actualG,
        if (uom != null) 'uom': uom,
      };

  /// A complete profiled weight line: 50 g units, 300 g ordered, cap 330 g.
  Map<String, dynamic> fullLine({Object? actualG}) => line(
        unitG: 50,
        pricePerKg: '3105.00',
        orderedG: 300,
        chargedGCap: 330,
        actualG: actualG,
      );

  group('isWeightLine mirrors the server four-field rule', () {
    test('a complete snapshot is a weight line', () {
      expect(OrderItem.fromJson(fullLine()).isWeightLine, isTrue);
    });

    test('ALL FOUR fields are required', () {
      // Each removed individually — a partial snapshot must not be weighed.
      final cases = <String, Map<String, dynamic>>{
        'no unit_g': line(pricePerKg: '3105.00', orderedG: 300, chargedGCap: 330),
        'no price_per_kg': line(unitG: 50, orderedG: 300, chargedGCap: 330),
        'no ordered_g': line(unitG: 50, pricePerKg: '3105.00', chargedGCap: 330),
        'no charged_g_cap': line(unitG: 50, pricePerKg: '3105.00', orderedG: 300),
      };
      cases.forEach((name, json) {
        expect(OrderItem.fromJson(json).isWeightLine, isFalse,
            reason: '$name must not be treated as a weight line');
      });
    });

    test('🔴 uom alone does NOT make a weight line', () {
      // Fresh produce carries «кг» and is sold in fixed half-kilo units with no
      // buffer and no settlement. Keying on the unit string would offer a
      // weight box for ordinary produce and let «Сборка завершена» send a
      // refund the server would refuse.
      final fresh = line(uom: 'кг', actualG: 500);
      expect(OrderItem.fromJson(fresh).isWeightLine, isFalse);
    });

    test('a plain piece line is not a weight line', () {
      expect(OrderItem.fromJson(line()).isWeightLine, isFalse);
    });

    test('an unweighed line is a weight line that is not yet weighed', () {
      final it = OrderItem.fromJson(fullLine());
      expect(it.isWeightLine, isTrue);
      expect(it.isWeighed, isFalse);
    });

    test('a weighed line reports both', () {
      final it = OrderItem.fromJson(fullLine(actualG: 314));
      expect(it.isWeightLine, isTrue);
      expect(it.isWeighed, isTrue);
      expect(it.actualG, 314);
    });
  });

  group('tolerant parsing', () {
    test('a numeric string parses for an int field', () {
      // The server sends ints, but a JSON round-trip through some proxies
      // yields strings. Reading it as null would hide the field entirely.
      final it = OrderItem.fromJson(fullLine(actualG: '314'));
      expect(it.actualG, 314);
      expect(it.isWeighed, isTrue);
    });

    test('money stays a string, as price/total do', () {
      final it = OrderItem.fromJson(fullLine());
      expect(it.pricePerKg, '3105.00');
    });

    test('an unparseable weight is null, never 0', () {
      // 0 would read as a real scale reading and lock the settle button on a
      // line that looks weighed.
      final it = OrderItem.fromJson(fullLine(actualG: 'abc'));
      expect(it.actualG, isNull);
      expect(it.isWeighed, isFalse);
    });
  });

  group('copyWith preserves the snapshot', () {
    test('a qty change does not strip the weight fields', () {
      // Dropping these would silently turn a weight line into a piece line
      // mid-pick, and its «Факт, г» box would vanish.
      final it = OrderItem.fromJson(fullLine(actualG: 314));
      final edited = it.copyWith(qty: 3);
      expect(edited.isWeightLine, isTrue);
      expect(edited.actualG, 314);
      expect(edited.orderedG, 300);
      expect(edited.chargedGCap, 330);
    });

    test('a new weight replaces the old one', () {
      final it = OrderItem.fromJson(fullLine(actualG: 314));
      expect(it.copyWith(actualG: 320).actualG, 320);
    });
  });

  group('formatGrams', () {
    test('grams below a kilo', () {
      expect(formatGrams(300), '300 г');
      expect(formatGrams(50), '50 г');
    });

    test('kilos at and above 1000, with a comma', () {
      expect(formatGrams(1000), '1 кг');
      expect(formatGrams(1500), '1,5 кг');
      expect(formatGrams(2000), '2 кг');
    });
  });

  group('weightLineSummary', () {
    test('reads as weight, never as a count', () {
      final it = OrderItem.fromJson(fullLine());
      final s = weightLineSummary(it);
      expect(s, contains('300 г'));
      expect(s, contains('/кг'));
      expect(s, contains('заказ'));
      expect(s, contains('до 330 г'));
      // The whole point: no «шт» anywhere on a weight line.
      expect(s.contains('шт'), isFalse);
    });
  });
}
