// iPad screenshots of the weighed-order screen states.
//
// Off by default (no PNGs on a normal `flutter test`). Run with:
//   WEIGHT_SHOTS=1 WEIGHT_SHOTS_DIR=<dir> flutter test test/weight_admin_screenshots_test.dart
//
// Text uses the Noto Sans subset in test/fonts (OFL, copied from the customer
// app's feat/weight-ux-final), which carries ₸ (U+20B8) and Cyrillic; the
// default test font renders every glyph as a box.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:admin_fmart/features/orders/presentation/weight_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

bool get _enabled => Platform.environment['WEIGHT_SHOTS'] == '1';
String get _outDir =>
    Platform.environment['WEIGHT_SHOTS_DIR'] ?? 'build/weight_shots';

Future<void> _loadFonts() async {
  final text = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('test/fonts/NotoSans-$w-subset.ttf').readAsBytesSync();
    text.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await text.load();
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    if (family == 'Roboto') continue;
    final loader = FontLoader(family);
    for (final f in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(f['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _shot(WidgetTester t, String name) async {
  await t.pump();
  final view = t.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final size = view.size;
  await t.runAsync(() async {
    final ui.Image img = await layer.toImage(Offset.zero & size);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_outDir/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Scroll so the weight card sits near the top of the screen.
Future<void> _toWeightCard(WidgetTester t) async {
  final card = find.text('Сыр Emsar для пиццы');
  await scrollTo(t, card);
  await t.drag(
    find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first,
    Offset(0, -(t.getTopLeft(card).dy - 140)),
  );
  await settle(t);
}

void main() {
  const sizes = {
    'portrait_1024x1366': Size(1024, 1366),
    'landscape_1366x1024': Size(1366, 1024),
  };

  setUpAll(() async {
    if (!_enabled) return;
    await _loadFonts();
    // The screenshot capture runs real async (runAsync), so a stray request
    // from the page (feature flags) reaches ApiClient's token read. No token.
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
  });

  for (final e in sizes.entries) {
    final tag = e.key;
    final size = e.value;

    testWidgets('$tag 1 before weighing', (t) async {
      final repo = fakeRepo(weighedOrderJson(weightSettled: false));
      await pumpOrderPage(t, repo, size: size);
      await _toWeightCard(t);
      await _shot(t, '${tag}_1_before_weighing');
      await disposePage(t);
    }, skip: !_enabled);

    testWidgets('$tag 2 under 80%', (t) async {
      final repo = fakeRepo(weighedOrderJson(weightSettled: false));
      await pumpOrderPage(t, repo, size: size);
      await _toWeightCard(t);
      await t.enterText(find.widgetWithText(TextField, 'Факт, г'), '220');
      await t.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(t);
      await _shot(t, '${tag}_2_under_80');
      await disposePage(t);
    }, skip: !_enabled);

    testWidgets('$tag 2b under the order (amber)', (t) async {
      final repo = fakeRepo(weighedOrderJson(weightSettled: false));
      await pumpOrderPage(t, repo, size: size);
      await _toWeightCard(t);
      await t.enterText(find.widgetWithText(TextField, 'Факт, г'), '270');
      await t.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(t);
      await _shot(t, '${tag}_2b_under_order');
      await disposePage(t);
    }, skip: !_enabled);

    testWidgets('$tag 3 over cap confirm', (t) async {
      final repo = fakeRepo(weighedOrderJson(weightSettled: false));
      await pumpOrderPage(t, repo, size: size);
      await _toWeightCard(t);
      await t.enterText(find.widgetWithText(TextField, 'Факт, г'), '330');
      await t.pump();
      final save = find.descendant(
        of: find.byType(WeightLinePanel),
        matching: find.widgetWithText(FilledButton, 'Сохранить'),
      );
      await t.tap(save);
      await settle(t);
      await _shot(t, '${tag}_3_over_cap_confirm');
      await disposePage(t);
    }, skip: !_enabled);

    testWidgets('$tag 4 settle confirm', (t) async {
      final repo =
          fakeRepo(weighedOrderJson(actualG: 270, weightSettled: false));
      await pumpOrderPage(t, repo, size: size);
      await scrollTo(t, find.text('Сборка завершена'));
      await t.tap(find.text('Сборка завершена'));
      await settle(t);
      await _shot(t, '${tag}_4_settle_confirm');
      await disposePage(t);
    }, skip: !_enabled);

    testWidgets('$tag 5 settled after reload', (t) async {
      final repo = fakeRepo(weighedOrderJson(
        actualG: 270,
        weightSettled: true,
        weightRefundAmount: '98.00',
      ));
      await pumpOrderPage(t, repo, size: size);
      await _toWeightCard(t);
      await _shot(t, '${tag}_5_settled_after_reload');
      await disposePage(t);
    }, skip: !_enabled);

    testWidgets('$tag 6 manager on a closed order', (t) async {
      final repo = fakeRepo(weighedOrderJson(
        status: 'completed',
        closed: true,
        actualG: 270,
        weightSettled: true,
        weightRefundAmount: '98.00',
      ));
      await pumpOrderPage(t, repo, size: size);
      await scrollTo(t, find.text('Возврат по закрытому заказу делает администратор'));
      await t.drag(
        find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first,
        const Offset(0, -300),
      );
      await settle(t);
      await _shot(t, '${tag}_6_manager_closed_order');
      await disposePage(t);
    }, skip: !_enabled);
  }
}
