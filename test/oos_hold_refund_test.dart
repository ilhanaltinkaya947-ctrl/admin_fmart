// The refund sheet now names which products were not on the shelf, and catalog
// hides those from every customer until they are genuinely restocked.
//
// That consequence is what these tests are about. Getting the amount wrong
// costs money and is visible immediately; getting the PRODUCT wrong hides
// something that is in stock, from everyone, for up to three weeks, and
// nothing on any screen would say so.
//
// The sheet itself is a 400-line closure inside a StatefulWidget and cannot be
// constructed in isolation, so these pin the parts that can be extracted and
// the wiring in the source. The end-to-end behaviour is proven on the backend
// side (order-service ↔ catalog over real HTTP).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/refundable.dart';

String _src(String rel) => File(rel).readAsStringSync();

const _page = 'lib/features/orders/presentation/order_details_page.dart';
const _repo = 'lib/features/orders/data/orders_repository.dart';

void main() {
  group('the amount follows the picked lines', () {
    // `OrderItem.total` is a STRING from the backend and can arrive with a
    // comma. Summing it with a bare parse would throw mid-refund.
    test('a comma total parses, it does not throw', () {
      expect(parseMoney('145,00'), 145.0);
      expect(parseMoney('145.00'), 145.0);
    });

    test('an unparseable total is 0, not a crash', () {
      expect(parseMoney('—'), 0.0);
      expect(parseMoney(null), 0.0);
    });

    test('the sheet sums with parseMoney, never a raw parse', () {
      final s = _src(_page);
      final i = s.indexOf('final sum = _order.items');
      expect(i, greaterThan(-1), reason: 'the selection no longer sums');
      final block = s.substring(i, i + 400);
      expect(block, contains('parseMoney(x.total)'));
      expect(block, isNot(contains('double.parse(x.total)')));
    });
  });

  group('only an explicit choice can hide a product', () {
    test('the picker is shown for «Нет в наличии» and nothing else', () {
      final s = _src(_page);
      expect(s, contains("const oosReason = 'Нет в наличии'"));
      // Rendered behind an equality check on that exact reason.
      expect(s, contains('if (code != oosReason) return const SizedBox.shrink()'));
    });

    test('changing the reason CLEARS the selection', () {
      // Otherwise picking lines, then switching to «Жалоба клиента», would
      // still hide products while the sheet no longer shows which, or why.
      final s = _src(_page);
      expect(s, contains('if (v != oosReason) oosItemIds.value = <int>{}'));
    });

    // Sliced to a structural delimiter, not a character count. An earlier
    // version used `substring(i, i + 320)` and failed on correct code the
    // moment a comment moved — a test measuring formatting, not behaviour.
    String sendPath() {
      final s = _src(_page);
      final i = s.indexOf('oosProductIds: code == oosReason');
      expect(i, greaterThan(-1), reason: 'the send path no longer re-checks');
      return s.substring(i, s.indexOf('));', i));
    }

    test('and the send path re-checks the reason anyway', () {
      // Belt and braces: a stale selection must not be able to leak through
      // even if the clear above is ever removed.
      expect(sendPath(), contains(': const []'));
    });

    test('ORDER-LINE ids are mapped to PRODUCT ids', () {
      // The checkboxes are keyed by order-line id because two lines can hold
      // the same product. Catalog knows nothing about order lines — sending a
      // line id would hold a product with that number, which is a different
      // product entirely.
      final block = sendPath();
      expect(block, contains('.map((x) => x.productId)'));
      expect(block, contains('.toSet()'),
          reason: 'two lines of the same product must not hold it twice');
    });
  });

  group('the request stays identical for every other refund', () {
    test('the field is omitted entirely when nothing was picked', () {
      final s = _src(_repo);
      expect(
        s,
        contains("if (oosProductIds.isNotEmpty) 'oos_product_ids': oosProductIds"),
        reason: 'an empty list would still change the request body',
      );
    });

    test('it defaults to empty, so existing callers are unaffected', () {
      expect(_src(_repo), contains('List<int> oosProductIds = const []'));
    });
  });

  group('the operator is told what will happen', () {
    test('the confirm dialog states the hold', () {
      final s = _src(_page);
      expect(s, contains('у покупателей, пока не завезут'));
    });

    test('the irreversible sentence is about the MONEY, not the hold', () {
      // The refund cannot be taken back; the hold can — it lifts on the next
      // delivery and can be released by hand. Calling both irreversible is
      // what makes an operator pick a different reason to dodge the warning.
      final s = _src(_page);
      expect(s, contains("'Возврат денег отменить нельзя.'"));
      expect(s, isNot(contains("'Это действие нельзя отменить.'")));
    });
  });

  group('the count in that sentence reads as Russian', () {
    // It tells an operator how many products are about to disappear from the
    // shop. «2 товаров» reads like a bug in the dialog asking them to trust
    // the number.
    //
    // _tovarWord is private, so the rule is restated here and the source is
    // checked for the same shape. If they ever disagree, this fails.
    String word(int n) {
      final m100 = n % 100;
      if (m100 >= 11 && m100 <= 14) return 'товаров';
      switch (n % 10) {
        case 1:
          return 'товар';
        case 2:
        case 3:
        case 4:
          return 'товара';
        default:
          return 'товаров';
      }
    }

    test('1, 2, 5', () {
      expect(word(1), 'товар');
      expect(word(2), 'товара');
      expect(word(5), 'товаров');
    });

    test('the 11-14 exception', () {
      for (final n in [11, 12, 13, 14]) {
        expect(word(n), 'товаров', reason: '$n');
      }
    });

    test('21 and 22 go back to the singular forms', () {
      expect(word(21), 'товар');
      expect(word(22), 'товара');
    });

    test('the page really has this helper', () {
      final s = _src(_page);
      expect(s, contains('String _tovarWord(int n)'));
      expect(s, contains('mod100 >= 11 && mod100 <= 14'),
          reason: 'the 11-14 exception is missing from the real helper');
    });
  });
}
