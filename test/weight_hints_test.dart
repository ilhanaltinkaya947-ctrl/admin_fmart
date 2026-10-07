// The two picker hints on the weigh/settle bar.
//
// Кирилл 2026-10-07 gave both rules for the person holding the knife:
//   * «Отрежьте не меньше заказа и не больше чем на 5% сверху»  (Сб.1)
//   * «Меньше 80% заказа: позвоните покупателю»                 (Сб.2)
//
// They are plain Text, not fields, so nothing can functionally "break" them —
// which is exactly why they need pinning: a rule stated in prose and then
// quietly reworded, or with its NUMBER dropped, stops being a rule. The numbers
// are the content. `5%` here is the same 5% as cart's WEIGHT_BUFFER_PCT and
// order-service's settle cap; if that changes these must change with it, and a
// failing test is the only thing that will say so.
//
// Source-level on purpose: the hint lives inside a 3,700-line page with heavy
// dependency wiring, and a widget test would need most of the app to assert a
// sentence. The property under test IS the sentence.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File(
    'lib/features/orders/presentation/order_details_page.dart',
  ).readAsStringSync();

  group('the 5% cut rule is stated where the picker cuts', () {
    test('the hint is present', () {
      expect(
        page.contains('Отрежьте не меньше заказа и не больше чем на 5% сверху'),
        isTrue,
        reason: 'the cut hint is gone — the picker is back to guessing',
      );
    });

    test('it states the number, not just "немного"', () {
      expect(page.contains('на 5% сверху'), isTrue);
    });

    test('it says BOTH bounds — not less than ordered AND not more than +5%', () {
      // The under-cut bound matters as much as the over-cut one: Ilhan's rule is
      // a range, and a hint that only named the ceiling would invite a short cut.
      expect(page.contains('не меньше заказа'), isTrue);
      expect(page.contains('не больше чем на 5%'), isTrue);
    });
  });

  group('the <80% call rule is stated', () {
    test('the hint is present', () {
      expect(
        page.contains('Меньше 80% заказа: позвоните покупателю'),
        isTrue,
        reason: 'the call-the-customer hint is gone',
      );
    });

    test('it names the threshold and the action', () {
      expect(page.contains('80%'), isTrue);
      expect(page.contains('позвоните покупателю'), isTrue);
    });
  });

  group('the hints sit on the settle bar, above the button that applies them', () {
    test('both hints precede the settle button', () {
      final cutHint = page.indexOf('Отрежьте не меньше заказа');
      final callHint = page.indexOf('Меньше 80% заказа');
      final button = page.indexOf("'Сборка завершена'");
      expect(cutHint, greaterThan(-1));
      expect(callHint, greaterThan(-1));
      expect(button, greaterThan(-1));
      expect(cutHint, lessThan(button),
          reason: 'the cut rule must be visible before the picker taps settle');
      expect(callHint, lessThan(button));
    });
  });

  group('the hints are not validation errors', () {
    test('neither is wired to _weightError', () {
      // A hint that only appeared on failure would be learned by getting it
      // wrong. These are permanent Text, so they must not be in the error map.
      final cutHint = page.indexOf('Отрежьте не меньше заказа');
      final callHint = page.indexOf('Меньше 80% заказа');
      final around = page.substring(
        cutHint - 400 < 0 ? 0 : cutHint - 400,
        callHint + 400,
      );
      expect(around.contains('_weightError'), isFalse);
    });
  });
}
