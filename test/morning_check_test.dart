// «Утренняя проверка» (26.10): the list, its rows, and the push that opens it.
//
// The push half matters most. Every OneSignal push used to be a new order:
// siren, counter, a dialog nobody can dismiss without a tap. A morning stock
// question treated that way at 08:00 teaches the store to mute the one alarm
// it has to trust, so the branch is pinned both as a function and in place.
import 'dart:async';
import 'dart:io';

import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/services/morning_check_push.dart';
import 'package:admin_fmart/core/storage/token_storage.dart';
import 'package:admin_fmart/features/stock/data/morning_check_repository.dart';
import 'package:admin_fmart/features/stock/presentation/morning_check_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(int id, {Object? answer, Object? stock1c = 3, String? held = '2026-10-25T13:05:00Z'}) => {
      'product_id': id,
      'name': 'Товар $id',
      'image_url': null,
      'held_at': held,
      'stock_1c': stock1c,
      'lapses_at': '2026-10-28T13:05:00Z',
      'answer': answer,
      'answered_at': answer == null ? null : '2026-10-26T03:10:00Z',
    };

Map<String, dynamic> _list(List<Map<String, dynamic>> items, {bool enabled = true}) =>
    {'store_id': 3, 'day': '2026-10-26', 'enabled': enabled, 'items': items};

/// The transport answers GET with [state] and POST by applying the answer to
/// it, as the server does, and records every request.
class _Server {
  Map<String, dynamic> state;
  final sent = <RequestOptions>[];
  bool failPost = false;
  _Server(this.state);

  MorningCheckRepository repo() {
    final api = ApiClient(baseUrl: 'http://localhost', tokenStorage: TokenStorage(), onUnauthorized: () {});
    api.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      sent.add(o);
      if (o.method == 'POST') {
        if (failPost) {
          h.reject(DioException(requestOptions: o, response: Response(requestOptions: o, statusCode: 502)));
          return;
        }
        final body = (o.data as Map).cast<String, dynamic>();
        for (final it in (state['items'] as List).cast<Map<String, dynamic>>()) {
          if (it['product_id'] == body['product_id']) it['answer'] = body['present'];
        }
      }
      h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: state));
    }));
    return MorningCheckRepository(api: api);
  }
}

Future<void> _pump(WidgetTester t, MorningCheckRepository repo) async {
  t.view.physicalSize = const Size(1024, 1366);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(RepositoryProvider<MorningCheckRepository>.value(
    value: repo,
    child: const MaterialApp(home: MorningCheckPage(storeId: 3, storeName: 'F-Mart Фиркан Сити')),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('parsing', () {
    test('a full list parses, answers and all', () {
      final l = MorningCheckList.fromJson(
          _list([_row(1), _row(2, answer: true), _row(3, answer: false, stock1c: null)]), storeId: 9);
      expect(l.storeId, 3);
      expect(l.enabled, isTrue);
      expect(l.items.map((i) => i.answer), [null, true, false]);
      expect(l.items[2].stock1c, isNull);
      expect(l.remaining, 1);
    });

    test('a bad row is skipped, a row without held_at is kept', () {
      final l = MorningCheckList.fromJson(
          _list([{'name': 'нет id'}, _row(5, held: null)]), storeId: 3);
      expect(l.items.single.productId, 5);
      expect(l.items.single.heldAt, isNull);
    });

    test('held_at is shown on the store clock (UTC+5), offset or not', () {
      expect(formatAlmaty(DateTime.parse('2026-10-25T13:05:00Z')), '25.10 18:05');
      final naive = MorningCheckItem.tryFromJson(_row(1, held: '2026-10-25T21:30:00'))!;
      expect(formatAlmaty(naive.heldAt!), '26.10 02:30');
      final offset = MorningCheckItem.tryFromJson(_row(1, held: '2026-10-25T18:05:00+05:00'))!;
      expect(formatAlmaty(offset.heldAt!), '25.10 18:05');
    });

    test('what an answer did', () {
      MorningCheckItem i({Object? answer, Object? q = 3}) =>
          MorningCheckItem.tryFromJson(_row(1, answer: answer, stock1c: q))!;
      expect(morningCheckOutcome(i()), isNull);
      expect(morningCheckOutcome(i(answer: true)), 'снова виден в приложении');
      expect(morningCheckOutcome(i(answer: true, q: 0)), 'в 1С 0: появится после исправления остатка в 1С');
      expect(morningCheckOutcome(i(answer: false)), 'скрыт ещё на день, спросим завтра');
    });
  });

  group('the screen', () {
    testWidgets('rows, progress and an answer refreshing from the server', (t) async {
      final server = _Server(_list([_row(1), _row(2, answer: false), _row(3, stock1c: 0)]));
      await _pump(t, server.repo());
      expect(find.text('Утренняя проверка'), findsOneWidget);
      expect(find.text('F-Mart Фиркан Сити'), findsOneWidget);
      expect(find.text('осталось 2'), findsOneWidget);
      expect(find.text('без ответа'), findsNWidgets(2));
      expect(find.text('скрыт с 25.10 18:05'), findsNWidgets(3));
      expect(find.text('скрыт ещё на день, спросим завтра'), findsOneWidget);
      expect(find.byKey(const ValueKey('morning-Нет, ещё нет-selected')), findsOneWidget);

      await t.tap(find.descendant(
          of: find.byKey(const ValueKey('morning-row-3')),
          matching: find.byKey(const ValueKey('morning-Да, есть'))));
      await t.pumpAndSettle();
      final post = server.sent.last;
      expect(post.path, '/gw/catalog/admin/morning-check/answer');
      expect(post.data, {'store_id': 3, 'product_id': 3, 'present': true});
      expect(find.text('в 1С 0: появится после исправления остатка в 1С'), findsOneWidget);
      expect(find.text('осталось 1'), findsOneWidget);

      // Changing an answer: tap the other button.
      await t.tap(find.descendant(
          of: find.byKey(const ValueKey('morning-row-2')),
          matching: find.byKey(const ValueKey('morning-Да, есть'))));
      await t.pumpAndSettle();
      expect(server.sent.last.data, {'store_id': 3, 'product_id': 2, 'present': true});
      expect(find.text('снова виден в приложении'), findsOneWidget);

      // The selected button again is a no-op, not a second POST.
      final n = server.sent.length;
      await t.tap(find.descendant(
          of: find.byKey(const ValueKey('morning-row-2')),
          matching: find.byKey(const ValueKey('morning-Да, есть-selected'))));
      await t.pumpAndSettle();
      expect(server.sent.length, n);

      await t.tap(find.descendant(
          of: find.byKey(const ValueKey('morning-row-1')),
          matching: find.byKey(const ValueKey('morning-Нет, ещё нет'))));
      await t.pumpAndSettle();
      expect(find.text('готово'), findsOneWidget);
    });

    testWidgets('a refused answer says so and keeps the row', (t) async {
      final server = _Server(_list([_row(1)]))..failPost = true;
      await _pump(t, server.repo());
      await t.tap(find.byKey(const ValueKey('morning-Да, есть')));
      await t.pumpAndSettle();
      expect(find.text('Не удалось сохранить ответ'), findsOneWidget);
      expect(find.text('без ответа'), findsOneWidget);
    });

    testWidgets('a store switch mid-load shows the NEW store, not the late old answer', (t) async {
      final slow = Completer<void>();
      final api = ApiClient(baseUrl: 'http://localhost', tokenStorage: TokenStorage(), onUnauthorized: () {});
      api.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) async {
        final store = o.queryParameters['store_id'];
        if (store == 3) await slow.future;
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: {
          'store_id': store, 'day': '2026-10-26', 'enabled': true,
          'items': [{..._row(store == 3 ? 30 : 40), 'name': 'Магазин $store'}],
        }));
      }));
      final repo = MorningCheckRepository(api: api);
      Widget page(int id) => RepositoryProvider<MorningCheckRepository>.value(
            value: repo,
            child: MaterialApp(home: MorningCheckPage(storeId: id, storeName: 'S$id')),
          );
      await t.pumpWidget(page(3));
      await t.pump();
      await t.pumpWidget(page(4));
      await t.pumpAndSettle();
      expect(find.text('Магазин 4'), findsOneWidget);
      slow.complete();
      await t.pumpAndSettle();
      expect(find.text('Магазин 4'), findsOneWidget);
      expect(find.text('Магазин 3'), findsNothing);
    });

    testWidgets('empty and switched off', (t) async {
      await _pump(t, _Server(_list([])).repo());
      expect(find.text('Сегодня проверять нечего'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await _pump(t, _Server(_list([], enabled: false)).repo());
      expect(find.text('Утренняя проверка выключена'), findsOneWidget);
    });
  });

  group('the push', () {
    test('morning_check is told apart from an order push', () {
      expect(isMorningCheckPush({'type': 'morning_check', 'store_id': 3, 'count': 4}), isTrue);
      expect(isMorningCheckPush({'order_id': 1382}), isFalse);
      expect(isMorningCheckPush({}), isFalse);
      expect(isMorningCheckPush({'type': 'order'}), isFalse);
    });

    test('count and banner text', () {
      expect(morningCheckCount({'count': 4}), 4);
      expect(morningCheckCount({'count': '7'}), 7);
      expect(morningCheckCount({}), isNull);
      expect(morningCheckBannerText(1), 'Утренняя проверка: 1 товар ждёт ответа');
      expect(morningCheckBannerText(3), 'Утренняя проверка: 3 товара ждут ответа');
      expect(morningCheckBannerText(12), 'Утренняя проверка: 12 товаров ждут ответа');
      expect(morningCheckBannerText(21), 'Утренняя проверка: 21 товар ждёт ответа');
    });

    test('the launcher keeps a request until the shell takes it (cold start)', () {
      final l = MorningCheckLauncher();
      expect(l.consume(), isFalse);
      l.request();
      expect(l.pending, isTrue);
      expect(l.consume(), isTrue);
      expect(l.consume(), isFalse);
    });

    // app.dart's handlers are closures over the OneSignal SDK and cannot be
    // driven in a unit test, so the placement is pinned in the source: the
    // morning branch must RETURN before the first thing an order push does.
    String handler(String src, String marker) {
      final i = src.indexOf(marker);
      expect(i, greaterThan(-1), reason: '$marker not found');
      return src.substring(i, src.indexOf('};', i));
    }

    test('foreground: no counter, no siren, no dialog for a morning push', () {
      final src = File('lib/app.dart').readAsStringSync();
      final h = handler(src, 'onForegroundNotification = (data) async {');
      final branch = h.indexOf('if (isMorningCheckPush(data))');
      expect(branch, greaterThan(-1));
      final ret = h.indexOf('return;', branch);
      for (final orderStep in ['_newOrderCounter.bump()', '_sound.ring()', 'showDialog(']) {
        expect(h.indexOf(orderStep), greaterThan(ret), reason: '$orderStep runs before the morning branch returns');
      }
      expect(h.substring(branch, ret), contains('_showMorningCheckBanner(data)'));
    });

    test('tap: opens the section, does not count an order', () {
      final src = File('lib/app.dart').readAsStringSync();
      final h = handler(src, 'onNotificationClick = (data) async {');
      final branch = h.indexOf('if (isMorningCheckPush(data))');
      expect(branch, greaterThan(-1));
      final ret = h.indexOf('return;', branch);
      expect(h.indexOf('_newOrderCounter.bump()'), greaterThan(ret));
      expect(h.indexOf('tryExtractOrderId'), greaterThan(ret));
      expect(h.substring(branch, ret), contains('_openMorningCheck()'));
    });

    // The tag is informational: OneSignal 5 tags are USER-level, so they
    // cannot tell builds apart. The gate is server-side (ops morning_push.py
    // filters on app_version, MORNING_CHECK_APP_VERSIONS); the in-app gate
    // is the branch above, which keeps a morning push from ever ringing.
    test('the morning_check tag is still set, next to the store tag', () {
      final src = File('lib/core/services/onesignal_service.dart').readAsStringSync();
      expect(src, contains('"store": storeId.toString(), "morning_check": "1"'));
    });
  });
}
