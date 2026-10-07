// The refund button on a COMPLETED order is admin-only (Kirill 2026-10-07):
//   «закрыть доступы к возвратам на закрытом заказе у сотрудников, оставить
//    только у админов»
//
// This is the client half of the rule order-service enforces with a 403. The
// server gate is the one that counts; this stops a manager seeing a control
// that would fail. The two must agree, and these tests pin the client side of
// that agreement — if they drift, a manager taps a button that 403s, which
// reads as a broken app rather than "not your action".
//
// Mutation guard: delete the `isAdmin` check in `canRefund` and the two
// completed-order-manager cases below go red. Remove the completed branch
// entirely and the same two go red. Both directions are covered.

import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/refund_button.dart';

void main() {
  group('a completed order is admin-only', () {
    test('a manager does NOT get the refund button', () {
      expect(canRefund(status: 'completed', isAdmin: false), isFalse);
    });

    test('an admin DOES get it', () {
      expect(canRefund(status: 'completed', isAdmin: true), isTrue);
    });

    test('case does not matter — the API sends lowercase, but be safe', () {
      expect(canRefund(status: 'COMPLETED', isAdmin: false), isFalse);
      expect(canRefund(status: ' Completed ', isAdmin: false), isFalse);
      expect(canRefund(status: 'Completed', isAdmin: true), isTrue);
    });
  });

  group('a LIVE order is unchanged — the normal counter flow', () {
    // Kirill's words are specifically about a CLOSED order. If these broke,
    // a manager could no longer do the partial refund they do every day.
    for (final s in const [
      'paid',
      'processing',
      'ready-for-delivery',
      'delivering',
      'partially-refunded',
    ]) {
      test('a manager keeps it on $s', () {
        expect(canRefund(status: s, isAdmin: false), isTrue);
      });

      test('an admin keeps it on $s', () {
        expect(canRefund(status: s, isAdmin: true), isTrue);
      });
    }
  });

  group('nothing else ever offers a refund', () {
    for (final s in const [
      'canceled',
      'refunded',
      'payment-failed',
      'pending-payment',
      'scheduled',
      'unknown',
      '',
    ]) {
      test('no button on $s, for anyone', () {
        expect(canRefund(status: s, isAdmin: false), isFalse);
        expect(canRefund(status: s, isAdmin: true), isFalse);
      });
    }
  });

  group('the rule is ONE-SIDED: it can only take a control away', () {
    // A rule that could also reveal the button would be a second source of
    // truth about who may refund, and the two would drift from the server.
    // Being admin must never ADD a status that a manager would not get.
    test('admin is never offered more statuses than a manager, except completed', () {
      const all = [
        'pending-payment', 'paid', 'processing', 'ready-for-delivery',
        'delivering', 'completed', 'partially-refunded', 'canceled',
        'refunded', 'payment-failed', 'scheduled', 'unknown', '',
      ];
      for (final s in all) {
        final asManager = canRefund(status: s, isAdmin: false);
        final asAdmin = canRefund(status: s, isAdmin: true);
        if (!asManager && asAdmin) {
          expect(s.trim().toLowerCase(), 'completed',
              reason: 'admin gained a status other than completed: $s');
        }
      }
    });
  });
}
