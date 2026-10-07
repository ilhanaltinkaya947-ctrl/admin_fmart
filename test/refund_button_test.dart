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

import 'dart:io';

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


  group('a CLOSED order is admin-only whatever its current status', () {
    // Round 4b: after an admin partial refund a completed order reads
    // `partially-refunded`. A status-only rule re-offered «Возврат» to a
    // manager on a DELIVERED order, and the API allowed it.
    test('a manager gets nothing on a closed order still reading partially-refunded', () {
      expect(
        canRefund(status: 'partially-refunded', isAdmin: false, closed: true),
        isFalse,
        reason: 'the rest of a delivered order must not be a manager\'s to refund',
      );
    });

    test('an admin still does', () {
      expect(
        canRefund(status: 'partially-refunded', isAdmin: true, closed: true),
        isTrue,
      );
    });

    test('closed wins over every live-looking status, for a manager', () {
      for (final s in const [
        'paid', 'processing', 'ready-for-delivery', 'delivering',
        'partially-refunded', 'completed',
      ]) {
        expect(canRefund(status: s, isAdmin: false, closed: true), isFalse,
            reason: 'closed order must not offer refund on $s to a manager');
      }
    });

    test('closed does NOT hide it from an admin', () {
      for (final s in const [
        'partially-refunded', 'refunded', 'canceled',
      ]) {
        // refunded/canceled are never offered (nothing left to refund), even to
        // an admin — assert the closed flag does not override that.
        final expected = s == 'partially-refunded';
        expect(canRefund(status: s, isAdmin: true, closed: true), expected,
            reason: 'closed + $s for an admin');
      }
    });

    test('an OPEN order is unaffected by the flag being false', () {
      expect(canRefund(status: 'partially-refunded', isAdmin: false, closed: false),
          isTrue);
    });
  });

  group('the flag defaults to false, so an old backend hides nothing', () {
    test('omitting closed leaves the live-order behaviour intact', () {
      expect(canRefund(status: 'paid', isAdmin: false), isTrue);
      expect(canRefund(status: 'completed', isAdmin: false), isFalse);
    });
  });


  group('the 403 text comes from the SERVER, not a constant here', () {
    // Round 5, LOW. `_showMoneyPathError` serves the refund, the cancel AND the
    // weight-difference paths. A hardcoded refund sentence showed on all three,
    // so a manager whose CANCEL was refused read refund wording. The server's
    // `detail` is already specific per action; the app must show it.
    final page = File(
      'lib/features/orders/presentation/order_details_page.dart',
    ).readAsStringSync();

    test('the 403 branch raises the message from the exception', () {
      final i = page.indexOf('} else if (code == 403) {');
      expect(i, greaterThan(-1));
      final j = page.indexOf('} else if (code == 409', i);
      final branch = page.substring(i, j > i ? j : i + 1400);
      expect(branch.contains('e.message'), isTrue,
          reason: 'the 403 copy must come from the server response');
    });

    test('no hardcoded refund sentence is shown for every 403', () {
      final i = page.indexOf('} else if (code == 403) {');
      final j = page.indexOf('} else if (code == 409', i);
      final branch = page.substring(i, j > i ? j : i + 1400);
      expect(branch.contains('Возврат по закрытому заказу'),
          isFalse,
          reason: 'a refund-specific sentence must not be used for cancel '
              'and weight-difference refusals too');
    });

    test('it still offers NO retry (a 403 can never succeed on retry)', () {
      // Bound the window to the 403 branch ITSELF, ending at the next `else if`.
      // A fixed-length window ran past the branch and picked up the
      // `_showErrorWithRetry` from the 409/5xx arms below, so the assertion
      // failed on a clean tree — a bad window, not a real defect.
      final i = page.indexOf('} else if (code == 403) {');
      final j = page.indexOf('} else if (code == 409', i);
      expect(j, greaterThan(i), reason: 'could not find the end of the 403 arm');
      final branch = page.substring(i, j);
      expect(branch.contains('_showErrorWithRetry'), isFalse,
          reason: 'a 403 must not offer a retry control');
    });
  });
}
