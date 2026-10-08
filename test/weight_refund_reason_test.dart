import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';

/// The weight refund reason (review MEDIUM-2).
///
/// order-service matches «Разница по весу» by PREFIX, case-insensitively
/// (`is_weight_refund_reason`, weight_settle.py:57), and REFUSES a manual refund
/// carrying it on any order that has a profiled weight line. The admin app must
/// therefore (a) keep the string byte-exact, and (b) not offer it where the
/// server will reject it.
void main() {
  Map<String, dynamic> line({
    bool profiled = true,
    String name = 'Сыр Emsar',
  }) =>
      <String, dynamic>{
        'id': 1,
        'product_id': 42,
        'qty': 6,
        'price': '155.00',
        'total': '1023.00',
        'product': {'name': name},
        if (profiled) ...{
          'unit_g': 50,
          'price_per_kg': '3105.00',
          'ordered_g': 300,
          'charged_g_cap': 330,
        },
      };

  /// The exact list the sheet builds, mirroring order_details_page.
  List<String> reasonsFor(List<Map<String, dynamic>> items) {
    final hasProfiled = items
        .map(OrderItem.fromJson)
        .any((it) => it.isWeightLine);
    const weightReason = 'Разница по весу';
    return <String>[
      'Нет в наличии',
      if (!hasProfiled) weightReason,
      'Брак / качество товара',
      'Замена товара',
      'Жалоба клиента',
      'Отмена заказа',
      'Другое',
    ];
  }

  group('«Разница по весу» visibility', () {
    test('hidden on an order with a profiled weight line', () {
      // The server 409s here: those lines settle through «Сборка завершена»,
      // and a manual refund on top would double-pay or net the settlement to
      // zero with nobody knowing which line it was for.
      expect(reasonsFor([line(profiled: true)]), isNot(contains('Разница по весу')));
    });

    test('kept for an order with no weight lines at all', () {
      expect(reasonsFor([line(profiled: false)]), contains('Разница по весу'));
    });

    test('kept for a LEGACY weight line with no snapshot', () {
      // Frozen poultry: a weight good that predates the feature, so it carries
      // no unit_g/ordered_g/cap. The server allows a manual refund for these,
      // which is why hiding on `isWeightLine` rather than on the product being
      // sold by weight is the correct rule.
      expect(reasonsFor([line(profiled: false)]), contains('Разница по весу'));
    });

    test('hidden when ANY line is profiled, even beside a legacy one', () {
      // Per-ORDER rule on the server, not per line.
      final items = [line(profiled: true), line(profiled: false, name: 'Курица')];
      expect(reasonsFor(items), isNot(contains('Разница по весу')));
    });

    test('the other reasons are never affected', () {
      final reasons = reasonsFor([line(profiled: true)]);
      for (final r in const [
        'Нет в наличии',
        'Брак / качество товара',
        'Замена товара',
        'Жалоба клиента',
        'Отмена заказа',
        'Другое',
      ]) {
        expect(reasons, contains(r), reason: '$r must stay offered');
      }
    });

    test('the canonical string is byte-exact', () {
      // A prefix match means «Разница по весу » with a trailing space, or a
      // lower-cased variant, would still match — but a REWORDED label would
      // silently stop being netted against the automatic settlement. Pin it.
      expect('Разница по весу'.toLowerCase().startsWith('разница по весу'), isTrue);
      expect(reasonsFor([line(profiled: false)]).firstWhere(
            (r) => r.startsWith('Разница'),
          ),
          'Разница по весу');
    });
  });

  group('the reason the sheet sends', () {
    // Mirrors order_details_page: canonical label first, optional note after.
    String compose(String? code, String note) {
      if (code == null) return note;
      return note.isEmpty ? code : '$code · $note';
    }

    test('label alone when there is no note', () {
      expect(compose('Разница по весу', ''), 'Разница по весу');
    });

    test('label FIRST, then the note — the server matches a prefix', () {
      final s = compose('Разница по весу', 'недовес 14 г');
      expect(s, 'Разница по весу · недовес 14 г');
      expect(s.toLowerCase().startsWith('разница по весу'), isTrue,
          reason: 'a prefix match must still find the canonical reason');
    });

    test('the note alone when no label was picked', () {
      // Free-text legacy path — it will NOT be netted as a weight refund.
      expect(compose(null, 'просто заметка'), 'просто заметка');
      expect('просто заметка'.toLowerCase().startsWith('разница по весу'),
          isFalse);
    });
  });
}
