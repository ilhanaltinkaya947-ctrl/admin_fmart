// Which rail took the money must be readable in the admin app.
//
// `orders.payment_method` has carried `epay` since the Halyk rail went live
// (23 orders on 2026-09-12) and `OrderModel` parsed it all along — but nothing
// rendered it, so an ePay order and a card order were indistinguishable. That
// matters most during a refund: the two rails fail in different ways, and a
// manager chasing a stuck one has to know which gateway to ask about.
//
// The load-bearing assertion here is the UNKNOWN case. Mapping an
// unrecognised token to a friendly guess reads as fact and sends staff to the
// wrong provider; echoing it verbatim is both honest and diagnosable.
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/payment_method_label.dart';

void main() {
  group('the rails we actually run', () {
    test('epay is named for the bank, not the token', () {
      // "epay" on screen means nothing to a manager on the phone to Halyk.
      expect(paymentMethodLabel('epay'), 'Halyk ePay');
      expect(isEpay('epay'), isTrue);
      expect(isKnownPaymentMethod('epay'), isTrue);
    });

    test('card and the wallets', () {
      expect(paymentMethodLabel('card'), 'Карта');
      expect(paymentMethodLabel('apple_pay'), 'Apple Pay');
      expect(paymentMethodLabel('google_pay'), 'Google Pay');
    });

    test('every value currently in the orders table maps', () {
      // Measured on prod 2026-09-12: card 594, apple_pay 107, epay 23.
      for (final v in ['card', 'apple_pay', 'epay']) {
        expect(isKnownPaymentMethod(v), isTrue, reason: '$v is unmapped');
      }
    });
  });

  group('an unknown token is echoed, never guessed', () {
    test('a rail added later shows its raw value', () {
      // The alternative — defaulting to «Карта» — would state something false
      // about where the money went.
      expect(paymentMethodLabel('kaspi_qr'), 'kaspi_qr');
      expect(isKnownPaymentMethod('kaspi_qr'), isFalse);
      expect(isEpay('kaspi_qr'), isFalse);
    });

    test('it is never silently mapped to a known rail', () {
      const unknown = 'some_rail_invented_next_year';
      final label = paymentMethodLabel(unknown);
      expect(label, unknown);
      expect(label, isNot('Карта'));
      expect(label, isNot('Halyk ePay'));
    });
  });

  group('missing data hides the row instead of printing a stub', () {
    test('null and empty yield null so the caller can omit the row', () {
      // Returning '' would render «Оплата: » with nothing after it.
      expect(paymentMethodLabel(null), isNull);
      expect(paymentMethodLabel(''), isNull);
      expect(paymentMethodLabel('   '), isNull);
    });

    test('predicates are safe on null', () {
      expect(isKnownPaymentMethod(null), isFalse);
      expect(isEpay(null), isFalse);
    });
  });

  group('tolerant of shape, not of meaning', () {
    test('case and surrounding whitespace do not change the rail', () {
      expect(paymentMethodLabel(' EPAY '), 'Halyk ePay');
      expect(paymentMethodLabel('Apple_Pay'), 'Apple Pay');
      expect(isEpay(' Epay'), isTrue);
    });
  });
}
