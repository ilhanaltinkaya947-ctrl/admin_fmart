import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// `partially-refunded` must sit on the ACTIVE tab, not «Закрытые».
///
/// order-service's state machine is explicit that a partial refund is not
/// terminal and allows it on to processing / ready-for-delivery / delivering /
/// completed. The admin app treated it as closed, which mattered most on
/// самовывоз: about a tenth of orders here lose a line to phantom stock, so a
/// bag waiting at the counter has often already had one line refunded — and
/// that refund used to move the order off the tab managers actually work from,
/// hiding the overdue cue from exactly the cohort it was built for.
///
/// Asserted against source because the groupings are private constants. The
/// same approach is already used elsewhere in this suite.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/orders/state/orders_cubit.dart').readAsStringSync();
  });

  String _block(String name) {
    final start = src.indexOf('const $name = {');
    expect(start, isNot(-1), reason: '$name not found — was it renamed?');
    final end = src.indexOf('};', start);
    return src.substring(start, end);
  }

  test('partially-refunded is on the ACTIVE tab', () {
    expect(_block('_activeStatusCodes'), contains("'partially-refunded'"));
  });

  test('partially-refunded is NOT on the closed tab', () {
    expect(_block('_closedStatusCodes'), isNot(contains("'partially-refunded'")),
        reason: 'listing it in both would make the tabs overlap');
  });

  test('the genuinely terminal statuses stay closed', () {
    final closed = _block('_closedStatusCodes');
    for (final s in ['completed', 'canceled', 'refunded', 'payment-failed',
                     'payment-timeout']) {
      expect(closed, contains("'$s'"), reason: '$s is terminal and must stay closed');
    }
  });

  test('the picking statuses are still active', () {
    final active = _block('_activeStatusCodes');
    for (final s in ['paid', 'processing', 'ready-for-delivery', 'delivering']) {
      expect(active, contains("'$s'"));
    }
  });
}
