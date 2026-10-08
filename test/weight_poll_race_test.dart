import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

/// Review M1: the 8 s poll must not put an old reading back in the «Факт, г»
/// field while a weight save is in flight or just after it.
void main() {
  Finder field() => find.widgetWithText(TextField, 'Факт, г');
  Finder save() => find.descendant(
        of: find.byType(Card),
        matching: find.widgetWithText(FilledButton, 'Сохранить'),
      );
  String fieldText(WidgetTester t) =>
      t.widget<TextField>(field()).controller!.text;

  testWidgets('no poll GET while a weight PUT is in flight', (t) async {
    final repo = fakeRepo(weighedOrderJson(weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, field());
    repo.putGate = Completer<void>();
    await t.enterText(field(), '300');
    await t.pump();
    await t.tap(save().first);
    await t.pump();

    final before = repo.getCalls;
    await t.pump(const Duration(seconds: 9)); // a poll tick
    await settle(t);
    expect(repo.getCalls, before, reason: 'polled during the save');

    repo.putGate!.complete();
    await settle(t);
    expect(fieldText(t), '300');
    await disposePage(t);
  });

  testWidgets('a slow GET from before the save does not undo it', (t) async {
    final repo = fakeRepo(weighedOrderJson(weightSettled: false));
    await pumpOrderPage(t, repo);
    await scrollTo(t, field());

    // A poll goes out and hangs, holding the order WITHOUT a reading.
    repo.getGate = Completer<void>();
    await t.pump(const Duration(seconds: 9));
    await t.pump();

    await t.enterText(field(), '300');
    await t.pump();
    await t.tap(save().first);
    await settle(t);
    expect(repo.weightPuts, [300]);

    // The stale answer lands now.
    repo.getGate!.complete();
    repo.getGate = null;
    await settle(t);
    expect(fieldText(t), '300', reason: 'the stale poll wiped the reading');
    expect(find.text('Клиент доплатил заранее, возврат 0 ₸'), findsNothing);
    await disposePage(t);
  });
}
