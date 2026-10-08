import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// Review M2: a typed «Факт, г» belongs to its line. Removing the line above
/// must not move the figure onto the next line.
void main() {
  Finder cardOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(Card));
  Finder fieldOf(String name) => find.descendant(
      of: cardOf(name), matching: find.widgetWithText(TextField, 'Факт, г'));
  String textOf(WidgetTester t, String name) =>
      t.widget<TextField>(fieldOf(name)).controller!.text;

  testWidgets('type into A, remove the line above, B stays empty', (t) async {
    final repo = fakeRepo(weighedOrderJson(
      weightSettled: false,
      items: [
        cheeseLine(id: 5, name: 'Сыр X весовой'),
        cheeseLine(id: 6, name: 'Сыр A весовой'),
        cheeseLine(id: 7, name: 'Сыр B весовой'),
      ],
    ));
    await pumpOrderPage(t, repo);
    await scrollTo(t, fieldOf('Сыр B весовой'));

    await t.enterText(fieldOf('Сыр A весовой'), '250');
    await t.pump();

    final removeX = find.descendant(
        of: cardOf('Сыр X весовой'), matching: find.byTooltip('Удалить'));
    await t.ensureVisible(removeX);
    await t.tap(removeX);
    await settle(t);
    await t.tap(find.text('Убрать и вернуть 976 ₸'));
    await settle(t);
    expect(repo.removeCalls, [5]);

    expect(textOf(t, 'Сыр A весовой'), '250');
    expect(textOf(t, 'Сыр B весовой'), '');
    await disposePage(t);
  });
}
