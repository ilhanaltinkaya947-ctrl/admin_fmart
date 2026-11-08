// 08.11 banner actions in the admin app: what the editor sends (stores,
// hours, badges, build floor, the action only when touched), the payload
// shapes the server expects, the server's refusal shown as is, the preview
// as the customer app draws it, and the list line.
import 'dart:convert';
import 'dart:io';

import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/storage/token_storage.dart';
import 'package:admin_fmart/features/banners/data/banner_action_draft.dart';
import 'package:admin_fmart/features/banners/data/banner_models.dart';
import 'package:admin_fmart/features/banners/data/banners_repository.dart';
import 'package:admin_fmart/features/banners/presentation/banner_edit_page.dart';
import 'package:admin_fmart/features/banners/presentation/banners_list_page.dart';
import 'package:admin_fmart/features/banners/presentation/widgets/banner_app_preview.dart';
import 'package:admin_fmart/features/banners/state/banners_cubit.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A repository whose transport answers from [answer] and records requests.
class _Wire {
  final List<RequestOptions> sent = [];
  Response<dynamic> Function(RequestOptions o)? answer;

  BannersRepository repo() {
    final api = ApiClient(baseUrl: 'http://localhost', tokenStorage: TokenStorage(), onUnauthorized: () {});
    api.dio.interceptors.insert(
      0,
      InterceptorsWrapper(onRequest: (o, h) {
        sent.add(o);
        final a = answer?.call(o) ??
            Response<dynamic>(requestOptions: o, statusCode: 200, data: <String, dynamic>{
              'id': 1,
              'image_url': 'https://example.invalid/x.jpg',
              'sort_order': 0,
              'active': true,
              'created_at': '2026-11-08T10:00:00Z',
              'updated_at': '2026-11-08T10:00:00Z',
            });
        if ((a.statusCode ?? 200) >= 400) {
          h.reject(DioException(requestOptions: o, response: a, type: DioExceptionType.badResponse));
        } else {
          h.resolve(a);
        }
      }),
    );
    return BannersRepository(api: api);
  }
}

String? field(Object? data, String key) {
  if (data is! FormData) return null;
  for (final f in data.fields) {
    if (f.key == key) return f.value;
  }
  return null;
}

List<String> keys(Object? data) => data is FormData ? data.fields.map((f) => f.key).toList() : const [];

File tmpImage() {
  final f = File('${Directory.systemTemp.path}/banner_actions_admin_test.jpg');
  f.writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
  return f;
}

void main() {
  group('what the editor sends', () {
    test('update: every extra field is sent; empty = the server\'s "null" clear token', () async {
      final w = _Wire();
      await w.repo().update(id: 1, extras: const BannerExtras());
      final d = w.sent.single.data;
      for (final k in ['store_ids', 'daily_from', 'daily_to', 'badge_ru', 'badge_kk', 'min_app_build']) {
        expect(field(d, k), 'null', reason: k);
      }
      expect(keys(d), isNot(contains('action_type')), reason: 'untouched action is never re-sent');
      expect(keys(d), isNot(contains('link_url')), reason: 'links are actions now; a script-set link stays');
    });

    test('update: values, sorted stores, the action as JSON when touched', () async {
      final w = _Wire();
      await w.repo().update(
        id: 1,
        extras: const BannerExtras(
          storeIds: [5, 3],
          dailyFrom: '19:00',
          badgeRu: ' −20% ',
          minAppBuild: 265,
          sendAction: true,
          actionType: 'search',
          action: {'query': 'мороженое'},
        ),
      );
      final d = w.sent.single.data;
      expect(field(d, 'store_ids'), '3,5');
      expect(field(d, 'daily_from'), '19:00');
      expect(field(d, 'daily_to'), 'null');
      expect(field(d, 'badge_ru'), '−20%');
      expect(field(d, 'min_app_build'), '265');
      expect(field(d, 'action_type'), 'search');
      expect(jsonDecode(field(d, 'action')!), {'query': 'мороженое'});
    });

    test('create: empty extras are simply not sent', () async {
      final w = _Wire();
      await w.repo().create(imageFile: tmpImage(), extras: const BannerExtras(sendAction: true));
      final d = w.sent.single.data;
      for (final k in ['store_ids', 'daily_from', 'badge_ru', 'min_app_build', 'link_url']) {
        expect(keys(d), isNot(contains(k)), reason: k);
      }
      expect(field(d, 'action_type'), 'none');
    });

    test('a refusal carries the server\'s own sentence', () async {
      final w = _Wire()
        ..answer = (o) => Response<dynamic>(
            requestOptions: o, statusCode: 400, data: {'detail': 'Товар не найден или выключен: 9'});
      await expectLater(
        w.repo().checkAction('product', {'product_id': 9}),
        throwsA(isA<BannerValidationException>()
            .having((e) => e.message, 'message', 'Товар не найден или выключен: 9')),
      );
    });

    test('check-action: per shop counts', () async {
      final w = _Wire()
        ..answer = (o) => Response<dynamic>(requestOptions: o, statusCode: 200, data: {
              'ok': true,
              'checked': 'action',
              'stores': [
                {'store_id': 3, 'store_name': 'Фиркан Сити', 'orderable': 3, 'total': 12},
                {'store_id': 4, 'store_name': 'Нурсат', 'orderable': 0, 'total': 12},
              ],
            });
      final r = await w.repo().checkAction('collection', {'product_ids': {'all': [1]}});
      expect(w.sent.single.path, endsWith('/admin/banners/check-action'));
      expect(r.stores.map((s) => '${s.storeName} ${s.orderable}/${s.total}'), ['Фиркан Сити 3/12', 'Нурсат 0/12']);
    });
  });

  group('payloads', () {
    test('collection: all + store lists, titles trimmed, empty lists dropped', () {
      final t = BannerTarget(kind: BannerActionKind.collection, collectionTitleRu: ' Подарки ')
        ..lists = {
          'all': [const PickedProduct(id: 1), const PickedProduct(id: 2)],
          '3': [const PickedProduct(id: 9)],
          '4': [],
        };
      expect(t.payload(), {
        'title_ru': 'Подарки',
        'product_ids': {'all': [1, 2], '3': [9]},
      });
      expect(t.localError(), isNull);
      expect(BannerTarget(kind: BannerActionKind.collection).localError(), 'Добавьте товары в подборку');
    });

    test('info page with a button, round trip through what the server returns', () {
      final info = BannerInfoDraft(
        titleRu: 'Как работает доставка',
        blocks: [
          InfoBlockDraft(InfoBlockKind.heading, textRu: 'Сроки', textKk: 'Мерзімі'),
          InfoBlockDraft(InfoBlockKind.bullets, textRu: 'Один\n\n Два '),
        ],
        ctaOn: true,
        ctaLabelRu: 'Смотреть акции',
        cta: BannerTarget(kind: BannerActionKind.deals),
      );
      final json = info.toJson();
      expect(json['blocks'], [
        {'type': 'heading', 'text_ru': 'Сроки', 'text_kk': 'Мерзімі'},
        {'type': 'bullets', 'items_ru': ['Один', 'Два']},
      ]);
      expect(json['cta'], {'label_ru': 'Смотреть акции', 'action_type': 'deals', 'action': <String, dynamic>{}});
      final back = BannerActionDraft.fromJson('info', json);
      expect(back.kind, BannerActionKind.info);
      expect(back.payload(), json);
    });

    test('local checks before the round trip', () {
      expect(BannerTarget(kind: BannerActionKind.product).localError(), 'Выберите товар');
      expect(BannerTarget(kind: BannerActionKind.search, query: 'a').localError(), contains('минимум 2'));
      expect(BannerTarget(kind: BannerActionKind.shelf, shelfKey: 'New Year').localError(), contains('ключ'));
      expect(BannerInfoDraft().localError(), 'Страница: заполните заголовок');
      expect(BannerInfoDraft(titleRu: 'X').localError(), 'Страница: блок 1 пустой');
    });

    test('a row with the gift banner\'s legacy link reads as the shelf', () {
      final b = BannerItem.fromJson({
        'id': 7,
        'image_url': 'x',
        'sort_order': 0,
        'active': true,
        'created_at': '2026-11-08T10:00:00Z',
        'updated_at': '2026-11-08T10:00:00Z',
        'action_type': 'shelf',
        'action': {'key': 'new_year_2027'},
        'store_ids': [3],
        'daily_from': '19:00:00',
        'min_app_build': 265,
      });
      expect(b.actionKind, BannerActionKind.shelf);
      expect(b.storeIds, [3]);
      expect((b.dailyFrom, b.dailyTo, b.minAppBuild), ('19:00', null, 265));
      expect(bannerActionSummary(b), 'Полка new_year_2027 · магазины 3 · 19:00 до 24:00 · с 265');
      expect(bannerStatsLine(const BannerStats(impressions: 12345, taps: 617)),
          'За 30 дней: показы 12 345 · нажатия 617 · 5,0 %');
    });
  });

  group('the editor', () {
    Widget app(Widget child, BannersRepository repo) => BlocProvider(
          create: (_) => BannersCubit(repo: repo),
          child: MaterialApp(home: child),
        );

    testWidgets('picking an action turns on «Только новые версии» and the badge; «Проверить» shows the server text',
        (t) async {
      t.view.physicalSize = const Size(1200, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final w = _Wire()
        ..answer = (o) => Response<dynamic>(
            requestOptions: o, statusCode: 400, data: {'detail': 'Текст поиска: минимум 2 символа'});
      await t.pumpWidget(app(const BannerEditPage(), w.repo()));
      expect(find.text('Только новые версии приложения'), findsNothing);
      await t.tap(find.byKey(const ValueKey('banner-kind-search')));
      await t.pump();
      expect(find.text('Только новые версии приложения'), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey('banner-only-new'))).value, isTrue);
      await t.enterText(find.widgetWithText(TextField, 'Текст поиска'), 'ab');
      await t.tap(find.byKey(const ValueKey('banner-check')));
      await t.pumpAndSettle();
      expect(find.text('Текст поиска: минимум 2 символа'), findsOneWidget);
      expect(w.sent.single.data, {'action_type': 'search', 'action': {'query': 'ab'}});
    });

    testWidgets('an existing banner\'s action is not re-sent when only the title changes', (t) async {
      t.view.physicalSize = const Size(1200, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final w = _Wire();
      final b = BannerItem(
        id: 7,
        imageUrl: '',
        sortOrder: 0,
        active: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        actionType: 'product',
        action: const {'product_id': 9},
        minAppBuild: 265,
      );
      await t.pumpWidget(app(BannerEditPage(banner: b), w.repo()));
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('banner-kind-product'))).selected, isTrue);
      await t.enterText(find.widgetWithText(TextField, 'Название (для админки)'), 'Сыр');
      await t.ensureVisible(find.byKey(const ValueKey('banner-save')));
      await t.tap(find.byKey(const ValueKey('banner-save')));
      await t.pumpAndSettle();
      final patch = w.sent.firstWhere((o) => o.method == 'PATCH');
      expect(keys(patch.data), isNot(contains('action_type')));
      expect(field(patch.data, 'title'), 'Сыр');
      expect(field(patch.data, 'min_app_build'), '265');
    });

    testWidgets('preview: «Смотреть» on a sell banner, «Подробнее» on a page, nothing without an action', (t) async {
      Widget slide(BannerActionKind k, {String badge = ''}) =>
          MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: BannerSlidePreview(kind: k, badge: badge))));
      await t.pumpWidget(slide(BannerActionKind.collection, badge: 'Новинка'));
      expect(find.text('Смотреть'), findsOneWidget);
      expect(find.text('Новинка'), findsOneWidget);
      await t.pumpWidget(slide(BannerActionKind.info));
      expect(find.text('Подробнее'), findsOneWidget);
      await t.pumpWidget(slide(BannerActionKind.none, badge: 'Новинка'));
      expect(find.text('Смотреть'), findsNothing);
      expect(find.text('Подробнее'), findsNothing);
      expect(find.text('Новинка'), findsNothing);
    });
  });
}
