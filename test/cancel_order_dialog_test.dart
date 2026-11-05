// Sweep 31.10 #4: 6 of 42 paid orders at Адырбекова were cancelled 7-33 min
// after the store accepted, 84 K, and nobody could tell whether it was
// missing items or a bad phone call — there was no reason at all.
//
// `_cancelOrder` is not widget-tested directly (it needs the full order
// page's auth/store/repo context, like the rest of this file); the pattern
// this repo uses instead for that page is a source-anchored assertion, same
// as `refund_button_test.dart`'s round-6 group.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File(
    'lib/features/orders/presentation/order_details_page.dart',
  ).readAsStringSync();

  group('cancelling a PAID order asks why', () {
    test('a reason is required only when money actually moved', () {
      final i = page.indexOf('Future<void> _cancelOrder()');
      final j = page.indexOf('Future<void> _performCancel(', i);
      expect(i, greaterThan(-1));
      expect(j, greaterThan(i));
      final body = page.substring(i, j);
      expect(
        body.contains('askReason = _canRefund'),
        isTrue,
        reason: 'a pending-payment cancel never moved money; '
            'it must not demand a reason',
      );
    });

    test('the confirm button is disabled until a reason is picked', () {
      expect(
        page.contains('onPressed: missingReason'),
        isTrue,
        reason: 'an operator must not be able to cancel a paid order '
            'with no reason recorded',
      );
    });

    test('the picked reason reaches cancelOrder', () {
      expect(page.contains('_performCancel(reason: result.reason)'), isTrue);
    });

    test('the 8s poll cannot swap the order under the open dialog', () {
      // flutter-critic (6fd815f): askReason is read once, before the dialog
      // opens; without this guard a webhook landing mid-dialog could ship a
      // now-actually-paid cancel with reason: null.
      final i = page.indexOf('Future<void> _cancelOrder()');
      final j = page.indexOf('Future<void> _performCancel(', i);
      final body = page.substring(i, j);
      expect(body.contains('_confirmOpen = true;'), isTrue);
      expect(body.contains('_confirmOpen = false;'), isTrue);
    });

    test('"Другое" cannot be confirmed with no comment', () {
      // ux-flow-designer review: a rushed manager reaches for the
      // no-further-questions option first, which is exactly the
      // un-analyzable gap this dropdown exists to close.
      expect(
        page.contains(
            '(code == null || (code == kOtherCancelReason && note.isEmpty))'),
        isTrue,
        reason: '"Другое" with an empty note must not confirm — same rule '
            'the refund sheet already enforces for its own "Другое"',
      );
    });
  });
}
