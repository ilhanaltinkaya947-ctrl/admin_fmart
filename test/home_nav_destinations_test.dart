import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone navigation bar must stay usable.
///
/// WHY THIS TEST EXISTS. An admin reported the Промокоды screen "is not
/// visible". It existed and was wired — it was the 9th of TWELVE destinations
/// in a Material NavigationBar, which does NOT scroll: it divides the width.
/// At 390pt that is 32.5px per tab, so the label was unreadable and the tap
/// target unhittable. Nothing had measured the count, so nothing caught it.
///
/// The fix moved the four admin configuration screens into Настройки. This
/// test pins the invariant that made the bug possible, at the level where it
/// is decidable: the bar's destination list.
///
/// (A full HomeShell pump would need OrdersCubit + OrdersRepository +
/// StoreCubit + AuthCubit + NewOrderCounter and is not what this bug was
/// about — the crowding is a property of the list, not of any provider.)
void main() {
  /// Mirrors the phone bar's list in home_shell.dart. Kept deliberately
  /// literal: if someone edits the shell, this test must be edited too, which
  /// is the point — it forces the count to be considered.
  // Every label here is <= 6 characters. Measured (05.11): a 7-character
  // Cyrillic label wraps mid-word at 10 destinations / ~37-39px per
  // destination ("Сегодня" -> "Сегод" / "ня" on two lines) — this hit
  // "Сегодня", "История", "Клиенты", "Скрытые" AND the already-abbreviated
  // "Заплан." (7 chars incl. the dot), none of which the test below had
  // caught because wrapping lays out without throwing. 6 characters is the
  // longest that stayed single-line in that same measurement.
  const phoneBarLabels = <String>[
    'Сегод.', 'Новые', 'Запл.', 'Истор.', 'Клиен.',
    'Отчёты', 'Отзывы', 'Слоты', 'Скрыт.', 'Настр.',
  ];

  /// Admin configuration screens. These live in Настройки, NOT the bar.
  const adminOnlyLabels = <String>['Промокоды', 'Баннеры', 'Пользователи', 'Рассылка'];

  const kMaxDestinations = 10;

  test('the phone bar does not exceed a legible destination count', () {
    expect(
      phoneBarLabels.length,
      lessThanOrEqualTo(kMaxDestinations),
      reason: 'A Material NavigationBar divides the width instead of '
          'scrolling, so every destination added makes ALL of them narrower. '
          'Twelve tabs at 390pt = 32.5px each, which is how the Промокоды tab '
          'became invisible. Add to Настройки instead of the bar.',
    );
  });

  test('admin configuration screens are not in the phone bar', () {
    for (final label in adminOnlyLabels) {
      expect(
        phoneBarLabels,
        isNot(contains(label)),
        reason: '"$label" is configuration an operator visits occasionally, '
            'not a daily operation. In the bar it costs a slot for every user '
            'on every screen — and that is how the bar reached 12 tabs.',
      );
    }
  });

  testWidgets('a NavigationBar with this many destinations lays out cleanly',
      (t) async {
    t.view.physicalSize = const Size(1170, 2532); // 390pt logical
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: [
            for (final l in phoneBarLabels)
              NavigationDestination(icon: const Icon(Icons.circle), label: l),
          ],
        ),
      ),
    ));
    await t.pumpAndSettle();

    final dests = find.byType(NavigationDestination).evaluate().toList();
    expect(dests.length, phoneBarLabels.length);

    // Measure it for real, rather than trusting a character-width estimate
    // (my first attempt at that arithmetic was wrong by a wide margin).
    final cell = (dests.first.renderObject as RenderBox).size.width;
    expect(
      cell,
      greaterThanOrEqualTo(35.0),
      reason: 'each destination was ${cell.toStringAsFixed(1)}px',
    );

    // A label that wraps lays out fine (no exception) but reads as broken
    // mid-word, e.g. "Сегод" / "ня" — this is how that bug survived the
    // test above. All ten labels must render on ONE line; the unselected
    // ones share one render height, so a wrapped label stands out as a
    // taller box than its siblings at the same index-0-unselected row.
    final heights = <String, double>{
      for (final l in phoneBarLabels)
        l: (find.text(l).evaluate().single.renderObject as RenderBox)
            .size
            .height,
    };
    final oneLine = heights.values.reduce((a, b) => a < b ? a : b);
    for (final entry in heights.entries) {
      expect(
        entry.value,
        oneLine,
        reason: '"${entry.key}" rendered taller than the shortest label '
            '(${entry.value} vs $oneLine) — it wrapped to a second line',
      );
    }

    var exceptions = 0;
    for (var i = 0; i < 10; i++) {
      if (t.takeException() == null) break;
      exceptions++;
    }
    expect(exceptions, 0, reason: 'the bar overflowed at this width');
  });
}
