import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_panel_warnings_test.dart' show weightItem, host;

/// Over the cap is ALLOWED with a confirm (Ilhan 08.10, decision 2).
///
/// The server bills at most `charged_g_cap`, so recording the true weight
/// costs the customer nothing extra; blocking Save only forced the picker to
/// type a false figure for a portion that cannot be trimmed.
void main() {
  testWidgets('Save stays enabled over the cap and the old copy is gone',
      (t) async {
    await t.pumpWidget(host(WeightLinePanel(
      item: weightItem(),
      onWeightSet: (_) {},
    )));
    await t.enterText(find.byType(TextField), '330');
    await t.pump();
    final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Сохранить'));
    expect(btn.onPressed, isNotNull);
    expect(find.textContaining('берём только до'), findsNothing);
    expect(find.textContaining('Больше лимита'), findsNothing);
  });

  testWidgets('over the cap: confirm, then Сохранить saves the TRUE weight',
      (t) async {
    final saved = <int>[];
    await t.pumpWidget(host(WeightLinePanel(
      item: weightItem(),
      onWeightSet: saved.add,
    )));
    await t.enterText(find.byType(TextField), '330');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pumpAndSettle();

    expect(
      find.text('Сохранить 330 г? Клиент заплатит только за 315 г, '
          'остальное за счёт магазина.'),
      findsOneWidget,
    );
    expect(saved, isEmpty, reason: 'nothing saved before the confirm');

    await t.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Сохранить'),
    ));
    await t.pumpAndSettle();
    expect(saved, [330]);
  });

  testWidgets('over the cap: Отмена saves nothing', (t) async {
    final saved = <int>[];
    await t.pumpWidget(host(WeightLinePanel(
      item: weightItem(),
      onWeightSet: saved.add,
    )));
    await t.enterText(find.byType(TextField), '400');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pumpAndSettle();
    await t.tap(find.text('Отмена'));
    await t.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('at or under the cap: no confirm, saved directly', (t) async {
    final saved = <int>[];
    await t.pumpWidget(host(WeightLinePanel(
      item: weightItem(),
      onWeightSet: saved.add,
    )));
    await t.enterText(find.byType(TextField), '315');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(saved, [315]);
  });
}
