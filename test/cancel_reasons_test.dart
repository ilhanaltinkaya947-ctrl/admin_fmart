import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/cancel_reasons.dart';

void main() {
  test('a fixed set of Russian reasons, no accidental blanks', () {
    expect(cancelReasons, isNotEmpty);
    for (final r in cancelReasons) {
      expect(r, isNotEmpty);
      expect(r.trim(), r, reason: 'stray whitespace in "$r"');
    }
  });

  test('"Другое" is last — the catch-all belongs after the named reasons', () {
    expect(cancelReasons.last, 'Другое');
  });
}
