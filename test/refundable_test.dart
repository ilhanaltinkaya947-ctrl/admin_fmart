// Tests for the refund ceiling the admin sheet offers.
//
// The five headline cases are real production orders. Each was cancelled or
// hand-refunded after a partial refund and came out short by exactly the size
// of that earlier refund. Two of them (392, 424) were refunded BY HAND from
// this very screen, which is what makes this a client-side bug and not only a
// backend one: the wrong figure was displayed and prefilled, so the manager
// confirmed it without anything on screen to reveal the shortfall.
// 
// Mutation guard: `legacy formula is wrong for every measured case`
// re-implements the OLD arithmetic and asserts it gets all five WRONG. Revert
// the fix and the rest of this file goes red; "fix" it by restoring the old
// formula and that test goes red instead.

import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/refundable.dart';

/// (order, captured, first refund, totalAmount AFTER that refund's recalc)
const measured = <List<dynamic>>[
  ['392', '1530.00', 20.0, '1510.00'],
  ['396', '3015.00', 230.0, '2785.00'],
  ['424', '1545.00', 55.0, '1490.00'],
  ['595', '145.00', 130.0, '15.00'],
  ['596', '145.00', 40.0, '105.00'],
];

void main() {
  group('the bug, case by case', () {
    for (final m in measured) {
      final order = m[0] as String;
      final captured = m[1] as String;
      final first = m[2] as double;
      final totalAfter = m[3] as String;

      test('order $order offers the rest of the capture', () {
        final c = refundCeiling(
          capturedAmount: captured,
          totalAmount: totalAfter,
          alreadyRefunded: first,
        );
        expect(c.known, isTrue);
        expect(c.remaining, closeTo(parseMoney(captured) - first, 0.001));
        // stated as money rather than as arithmetic
        expect(first + c.remaining, closeTo(parseMoney(captured), 0.001));
      });
    }

    test('legacy formula is wrong for every measured case', () {
      for (final m in measured) {
        final captured = parseMoney(m[1] as String);
        final first = m[2] as double;
        final totalAfter = parseMoney(m[3] as String);

        final legacy = totalAfter - first;
        final correct = captured - first;
        expect(legacy, isNot(closeTo(correct, 0.001)));
        // short by exactly the earlier refund, every time
        expect(correct - legacy, closeTo(first, 0.001));
      }
    });

    test('order 595 offered a NEGATIVE remaining, so nothing was refunded', () {
      // 15 - 130 = -115. Clamped to 0, the sheet offers nothing at all and the
      // packaging fee is silently kept.
      final legacy = 15.0 - 130.0;
      expect(legacy, lessThan(0));

      final c = refundCeiling(
        capturedAmount: '145.00',
        totalAmount: '15.00',
        alreadyRefunded: 130.0,
      );
      expect(c.remaining, closeTo(15.0, 0.001));
    });
  });

  group('the case that made the bug survive review', () {
    test('a manual partial refund does not touch total, and still works', () {
      // Charged 1000, refunded 200 by hand, totalAmount still 1000. The legacy
      // formula was RIGHT here — the fix must not break it.
      final c = refundCeiling(
        capturedAmount: '1000.00',
        totalAmount: '1000.00',
        alreadyRefunded: 200.0,
      );
      expect(c.remaining, closeTo(800.0, 0.001));
      expect(c.remaining, closeTo(1000.0 - 200.0, 0.001)); // agrees with legacy
    });

    test('both kinds of refund on one order', () {
      // Charged 1000; 200 manual (total stays 1000); then 100 by substitution
      // (total recalculates to 900). Ledger holds 300. Remaining must be 700.
      final c = refundCeiling(
        capturedAmount: '1000.00',
        totalAmount: '900.00',
        alreadyRefunded: 300.0,
      );
      expect(c.remaining, closeTo(700.0, 0.001));
    });
  });

  group('null is not zero', () {
    test('a missing capture falls back to the legacy figure, unchanged', () {
      // An older backend, or an order captured before the column existed. It
      // must behave exactly as it does today rather than offering no refund.
      final c = refundCeiling(
        capturedAmount: null,
        totalAmount: '1510.00',
        alreadyRefunded: 20.0,
      );
      expect(c.known, isFalse);
      expect(c.remaining, closeTo(1490.0, 0.001)); // the legacy (short) number
    });

    test('a zero capture is a real value, not a sentinel', () {
      // 0.00 means we captured nothing. It must NOT be read as "unknown" and
      // fall back to totalAmount, or the sheet offers a refund on money that
      // was never taken.
      final c = refundCeiling(
        capturedAmount: '0.00',
        totalAmount: '500.00',
        alreadyRefunded: 0.0,
      );
      expect(c.known, isTrue);
      expect(c.basis, 0.0); // NOT 500
      expect(c.remaining, 0.0);
    });
  });

  group('never negative, never surprising', () {
    test('remaining clamps at zero when already over-refunded', () {
      final c = refundCeiling(
        capturedAmount: '100.00',
        totalAmount: '100.00',
        alreadyRefunded: 150.0,
      );
      expect(c.remaining, 0.0);
    });

    test('a fully refunded order offers nothing', () {
      final c = refundCeiling(
        capturedAmount: '145.00',
        totalAmount: '0.00',
        alreadyRefunded: 145.0,
      );
      expect(c.remaining, 0.0);
    });

    test('comma decimals parse', () {
      expect(parseMoney('145,00'), closeTo(145.0, 0.001));
      expect(parseMoney('145.00'), closeTo(145.0, 0.001));
      expect(parseMoney(null), 0.0);
      expect(parseMoney('nonsense'), 0.0);
    });
  });
}
