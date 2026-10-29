// Sentry 157089965 / 157089610 (29.10): «string is not well-formed UTF-16».
// name[0] on a name that starts with an emoji is half a surrogate pair; the
// avatar Text then throws. Initials take whole characters.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no code-unit initials left in the avatar builders', () {
    for (final p in [
      'lib/features/customers/presentation/customers_list_page.dart',
      'lib/features/customers/presentation/customer_detail_page.dart',
      'lib/features/users/presentation/users_list_page.dart',
    ]) {
      final s = File(p).readAsStringSync();
      expect(s, isNot(contains('fn[0]')), reason: p);
      expect(s, isNot(contains('ln[0]')), reason: p);
      expect(s, contains('fn.characters.first'), reason: p);
    }
  });

  testWidgets('an emoji first letter renders whole', (tester) async {
    const name = '😊Айгерим';
    expect(name[0].codeUnits.length, 1, reason: 'the old way: half an emoji');
    await tester.pumpWidget(MaterialApp(home: Text(name.characters.first.toUpperCase())));
    expect(tester.takeException(), isNull);
    expect(find.text('😊'), findsOneWidget);
  });
}
