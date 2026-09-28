import 'dart:async';

import 'package:admin_fmart/features/promos/data/promo_models.dart';
import 'package:admin_fmart/features/promos/data/promo_repository.dart';
import 'package:admin_fmart/features/promos/presentation/promo_detail_page.dart';
import 'package:admin_fmart/features/promos/presentation/promo_edit_page.dart';
import 'package:admin_fmart/features/promos/state/promos_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart';

/// The Промокод detail and create screens must PAINT in every reachable state.
///
/// The list page got a render test first, because that is the screen the
/// Баннеры blank-body lesson applied to most obviously. But these two are the
/// screens MARKETING actually touches: detail is where they read a campaign's
/// numbers, edit is where they create one. A layout crash on either of them
/// looks exactly like Баннеры did — a normal AppBar over an empty body, no
/// error on screen — and neither had a render test.
///
/// The states worth pinning down are the ones the happy path never visits:
///   detail  -> still loading, load failed, no redemptions, 100+ (truncation hint)
///   edit    -> server sent no types (create is impossible, must SAY so)
///              vs the test-only type (must carry its warning)
class _StubPromoRepo implements PromoRepository {
  _StubPromoRepo({this.redemptionRows = const []});

  final List<PromoRedemption> redemptionRows;

  @override
  Future<List<AdminPromo>> list() async => const [];

  @override
  Future<List<String>> types() async => const ['FREE_DELIVERY_FIRST_ORDER'];

  @override
  Future<List<PromoRedemption>> redemptions(String code) async => redemptionRows;

  @override
  dynamic noSuchMethod(Invocation i) => NoopProxy().noSuchMethod(i);
}

/// Redemptions that never resolve, so the page is frozen in its loading state.
class _HangingPromoRepo extends _StubPromoRepo {
  @override
  Future<List<PromoRedemption>> redemptions(String code) =>
      Completer<List<PromoRedemption>>().future;
}

class _FailingPromoRepo extends _StubPromoRepo {
  @override
  Future<List<PromoRedemption>> redemptions(String code) async =>
      throw Exception('network down');
}

AdminPromo promo({
  String code = 'FREEORDER',
  String type = 'FREE_DELIVERY_FIRST_ORDER',
  bool enabled = true,
  DateTime? expiresAt,
  int redemptions = 119,
  int customers = 82,
  int committed = 100,
  int released = 19,
}) =>
    AdminPromo(
      id: 1,
      code: code,
      promoType: type,
      enabled: enabled,
      expiresAt: expiresAt,
      redemptions: redemptions,
      customers: customers,
      committed: committed,
      released: released,
    );

PromoRedemption redemption(
  int orderId, {
  String status = 'committed',
  double discount = 0,
  int userId = 7,
  DateTime? createdAt,
}) =>
    PromoRedemption(
      id: orderId,
      userId: userId,
      orderId: orderId,
      status: status,
      discountSum: discount,
      currency: 'KZT',
      createdAt: createdAt,
    );

/// A page plus the providers the real navigation supplies.
///
/// The detail page reads the cubit for its freshest copy of the code, and
/// fetches its redemption history with `context.read<PromoRepository>()` —
/// NOT through the cubit. Providing only the cubit leaves that read
/// unsatisfied, the history never loads, and every assertion about rows
/// silently fails against a page stuck on its spinner. So both are provided.
Widget detailScreen(PromoRepository repo, AdminPromo p) =>
    RepositoryProvider<PromoRepository>.value(
      value: repo,
      child: BlocProvider(
        create: (_) => PromosCubit(repo: repo),
        child: PromoDetailPage(promo: p),
      ),
    );

Widget editScreen(PromoRepository repo, List<String> types) =>
    RepositoryProvider<PromoRepository>.value(
      value: repo,
      child: BlocProvider(
        create: (_) => PromosCubit(repo: repo),
        child: PromoEditPage(availableTypes: types),
      ),
    );

/// The default test surface is 800x600. Both screens are ListViews, and a
/// ListView does not BUILD what is off-screen — so on the default surface a
/// passing test would only be proving the top 600px paint, and every
/// assertion about history rows or the bottom-of-page warnings would be
/// silently unfindable rather than actually checked. That is the same
/// "the assertion never ran" failure as a check that cannot fail.
///
/// The width is a REAL PHONE (390 x 1400 logical), not a comfortable desktop.
/// The first version of this helper used 400x1200 and still caught the
/// dropdown overflow; the bug is invisible at 744 and worse the narrower you
/// go, so the guard is only meaningful at a width someone actually holds.
Future<String?> probe(WidgetTester t, Widget page) async {
  t.view.physicalSize = const Size(1170, 4200); // 390 x 1400 logical
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  return renderProbe(t, page);
}

void main() {
  group('PromoDetailPage', () {
    testWidgets('it paints at all — header, numbers, section titles', (t) async {
      final err = await probe(
        t,
        detailScreen(_StubPromoRepo(), promo()),
      );
      expect(err, isNull, reason: err ?? '');
      expect(find.text('FREEORDER'), findsWidgets);
      expect(find.text('Использование'), findsOneWidget);
      expect(find.text('История применений'), findsOneWidget);
      // The four usage cells are the numbers marketing came for.
      expect(find.text('Применений'), findsOneWidget);
      expect(find.text('Клиентов'), findsOneWidget);
      expect(find.text('Применён'), findsOneWidget);
      expect(find.text('Освобождён'), findsOneWidget);
    });

    testWidgets('the redemptions!=customers distinction is stated on screen',
        (t) async {
      final err = await probe(t, detailScreen(_StubPromoRepo(), promo()));
      expect(err, isNull, reason: err ?? '');
      // 119 rows vs 82 customers is the exact prod numbers that were misread
      // as reach. The screen must say why the two differ.
      expect(
        find.textContaining('Один клиент может дать'),
        findsOneWidget,
        reason: 'without this line 119 reads as 119 customers — a ~45% overstatement',
      );
      expect(find.text('119'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
    });

    testWidgets('loading -> a spinner, not a blank gap under the title',
        (t) async {
      final err = await probe(t, detailScreen(_HangingPromoRepo(), promo()));
      expect(err, isNull, reason: err ?? '');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('load failure -> the error is named and a retry offered',
        (t) async {
      final err = await probe(t, detailScreen(_FailingPromoRepo(), promo()));
      expect(err, isNull, reason: err ?? '');
      expect(find.text('Не удалось загрузить историю'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
    });

    testWidgets('no redemptions -> an explicit message', (t) async {
      final err = await probe(
        t,
        detailScreen(_StubPromoRepo(redemptionRows: const []), promo(redemptions: 0)),
      );
      expect(err, isNull, reason: err ?? '');
      expect(find.textContaining('ещё не было применений'), findsOneWidget);
    });

    testWidgets('redemptions paint with order id, status and discount',
        (t) async {
      final err = await probe(
        t,
        detailScreen(
          _StubPromoRepo(redemptionRows: [
            redemption(101, discount: 1500, createdAt: DateTime(2026, 5, 4, 10, 30)),
            redemption(102, status: 'reserved', discount: 900),
            redemption(103, status: 'released'),
          ]),
          promo(),
        ),
      );
      expect(err, isNull, reason: err ?? '');
      expect(find.text('Заказ №101'), findsOneWidget);
      expect(find.text('Заказ №103'), findsOneWidget);
      expect(find.text('Применён'), findsWidgets);
      expect(find.text('Зарезервирован'), findsOneWidget);
      expect(find.text('Освобождён'), findsWidgets);
      expect(find.textContaining('1500'), findsOneWidget);
    });

    testWidgets('a released row with no discount paints no stray "0 KZT"',
        (t) async {
      final err = await probe(
        t,
        detailScreen(
          _StubPromoRepo(redemptionRows: [redemption(103, status: 'released')]),
          promo(),
        ),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.textContaining('0 KZT'),
        findsNothing,
        reason: 'a zero discount is deliberately hidden, not printed as 0',
      );
    });

    testWidgets('100+ redemptions -> the truncation is admitted', (t) async {
      final many = List.generate(100, (i) => redemption(1000 + i, discount: 100));
      final err = await probe(
        t,
        detailScreen(_StubPromoRepo(redemptionRows: many), promo()),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.textContaining('Показаны последние 100'),
        findsOneWidget,
        reason: 'a silently clipped history reads as the whole history',
      );
    });

    testWidgets('the test-only type is WARNED about on detail too', (t) async {
      final err = await probe(
        t,
        detailScreen(_StubPromoRepo(), promo(code: 'TESTFREE', type: 'FREE_DELIVERY_TEST_UNLIMITED')),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.textContaining('Тестовый тип'),
        findsOneWidget,
        reason: 'someone reading this screen alone must learn the code is dead '
            'for real customers',
      );
    });

    testWidgets('a disabled code shows a state chip, not a live one', (t) async {
      final err = await probe(
        t,
        detailScreen(_StubPromoRepo(), promo(enabled: false)),
      );
      expect(err, isNull, reason: err ?? '');
      expect(find.text('Отключён'), findsOneWidget);
      expect(find.text('Активен'), findsNothing);
    });

    testWidgets('an expiry offers "Снять", no expiry does not', (t) async {
      final withExpiry = await probe(
        t,
        detailScreen(_StubPromoRepo(), promo(expiresAt: DateTime(2027, 1, 1))),
      );
      expect(withExpiry, isNull, reason: withExpiry ?? '');
      expect(find.text('Снять'), findsOneWidget);
      expect(find.textContaining('Действует до'), findsOneWidget);

      final noExpiry = await probe(
        t,
        detailScreen(_StubPromoRepo(), promo()),
      );
      expect(noExpiry, isNull, reason: noExpiry ?? '');
      expect(find.text('Без ограничения по сроку'), findsOneWidget);
      expect(
        find.text('Снять'),
        findsNothing,
        reason: 'clearing a date that does not exist is a dead control',
      );
    });

    testWidgets('every reachable state paints content in the body', (t) async {
      for (final (label, repo, p) in <(String, PromoRepository, AdminPromo)>[
        ('loaded', _StubPromoRepo(redemptionRows: [redemption(1)]), promo()),
        ('loading', _HangingPromoRepo(), promo()),
        ('failure', _FailingPromoRepo(), promo()),
        ('empty history', _StubPromoRepo(), promo(redemptions: 0)),
        ('disabled', _StubPromoRepo(), promo(enabled: false)),
      ]) {
        final err = await probe(t, detailScreen(repo, p));
        expect(err, isNull, reason: '$label threw: ${err ?? ""}');
        expect(
          find.byType(ListView).evaluate().isNotEmpty,
          isTrue,
          reason: '$label painted no body',
        );
      }
    });
  });

  group('PromoEditPage', () {
    testWidgets('it paints at all — code field, type picker, switch, save',
        (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const ['FREE_DELIVERY_FIRST_ORDER']),
      );
      expect(err, isNull, reason: err ?? '');
      expect(find.text('Новый промокод'), findsOneWidget);
      expect(find.text('Создать'), findsOneWidget);
      expect(find.text('Код'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Включён'), findsOneWidget);
      expect(find.text('Действует до'), findsOneWidget);
    });

    testWidgets('nothing else is invented: only the server types are offered',
        (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const [
          'FREE_DELIVERY_FIRST_ORDER',
          'FREE_DELIVERY_TEST_UNLIMITED',
        ]),
      );
      expect(err, isNull, reason: err ?? '');
      // Assert on the menu's ITEMS after opening it. isExpanded + ellipsis
      // clips a long label on a 390pt phone, so find.text is the wrong
      // instrument for a CLOSED dropdown; the open menu is what proves the
      // picker came from the server list rather than a local constant.
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      final values = t
          .widgetList<DropdownMenuItem<String>>(find.byType(DropdownMenuItem<String>))
          .map((i) => i.value)
          .toSet();
      expect(
        values,
        {'FREE_DELIVERY_FIRST_ORDER', 'FREE_DELIVERY_TEST_UNLIMITED'},
        reason: 'the picker is built from the server list, in the server order',
      );
    });

    testWidgets('NO types from the server -> says create is impossible',
        (t) async {
      final err = await probe(t, editScreen(_StubPromoRepo(), const []));
      expect(err, isNull, reason: err ?? '');
      expect(
        find.textContaining('создать код нельзя'),
        findsOneWidget,
        reason: 'a picker with zero options is an unusable control; the screen '
            'must explain why rather than show an empty dropdown',
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('the first order type explains its once-only rule', (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const ['FREE_DELIVERY_FIRST_ORDER']),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.textContaining('уже использован'),
        findsOneWidget,
        reason: 'the single-use rule is engine semantics, not marketing copy',
      );
    });

    testWidgets('the test type carries its warning wherever it is selected',
        (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const ['FREE_DELIVERY_TEST_UNLIMITED']),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.textContaining('ТЕСТОВЫЙ ТИП'),
        findsOneWidget,
        reason: 'creating this code is the mistake this warning exists to stop',
      );
      expect(find.textContaining('не подходит'), findsNothing,
          reason: 'the wording now names the consequence instead of "не подходит"');
    });

    testWidgets('an unknown type falls back to its raw value, never blank',
        (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const ['PERCENT_OFF_SOMETHING_NEW']),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.text('PERCENT_OFF_SOMETHING_NEW'),
        findsWidgets,
        reason: 'a type the app has no label for must still render as something',
      );
    });

    testWidgets('survives every phone width without an overflow stripe',
        (t) async {
      // The regression this file was written to catch: the dropdown laid its
      // label out at intrinsic width and overflowed by 254px on a 375pt phone.
      // Two IconButtons in the ListTile trailing are fine; the dropdown was not.
      for (final w in <double>[320, 375, 390, 430]) {
        t.view.physicalSize = Size(w * 3, 1400 * 3);
        t.view.devicePixelRatio = 3.0;
        addTearDown(t.view.reset);
        final err = await renderProbe(
          t,
          editScreen(
            _StubPromoRepo(),
            const ['FREE_DELIVERY_FIRST_ORDER', 'FREE_DELIVERY_TEST_UNLIMITED'],
          ),
        );
        expect(err, isNull, reason: 'width $w overflowed: ${err ?? ""}');
      }
    });

    testWidgets('opens on the REAL campaign type, not the test type', (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const [
          // Deliberately the order the SERVER could return tomorrow: test type
          // first. `availableTypes.first` would open the screen on a code that
          // is dead for every real customer.
          'FREE_DELIVERY_TEST_UNLIMITED',
          'FREE_DELIVERY_FIRST_ORDER',
        ]),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.textContaining('ТЕСТОВЫЙ ТИП'),
        findsNothing,
        reason: 'opening on the test type would tell a manager their campaign '
            'is a QA code before they have chosen anything',
      );
      expect(
        find.textContaining('Бесплатная доставка для первого заказа'),
        findsWidgets,
        reason: 'the safe default is the real campaign type, regardless of '
            'the order the server happens to send',
      );
    });

    testWidgets('an unknown-only type list still selects something', (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const ['SOME_FUTURE_TYPE']),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.text('SOME_FUTURE_TYPE'),
        findsWidgets,
        reason: 'a type added to the engine ahead of an app release must be '
            'selectable rather than leaving an empty picker',
      );
    });

    testWidgets('the test type says it is refused by real customers',
        (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const ['FREE_DELIVERY_TEST_UNLIMITED']),
      );
      expect(err, isNull, reason: err ?? '');
      // The consequence, not the mechanism: an operator must learn that the
      // code they are creating will be refused by everyone they care about.
      expect(find.textContaining('НЕ ДЛЯ КАМПАНИЙ'), findsOneWidget);
      expect(find.textContaining('реальные клиенты'), findsOneWidget);
      expect(
        find.textContaining('Бесплатная доставка (первый заказ)'),
        findsOneWidget,
        reason: 'a warning that does not say what to do instead is only noise',
      );
    });

    testWidgets('the real type states the delivery-only limit', (t) async {
      final err = await probe(
        t,
        editScreen(_StubPromoRepo(), const ['FREE_DELIVERY_FIRST_ORDER']),
      );
      expect(err, isNull, reason: err ?? '');
      expect(
        find.textContaining('самовывоз'),
        findsOneWidget,
        reason: 'cart-service silently drops the code at pickup because there '
            'is no delivery fee to discount; the operator must be told, or the '
            'customer hits a code that appears to do nothing',
      );
      expect(find.textContaining('первый заказ'), findsWidgets);
    });

    testWidgets('every reachable state paints content in the body', (t) async {
      // Each state gets its OWN test body. Reusing one tester across states
      // keeps the first state's PromoEditPage alive, so initState would hold a
      // type from an earlier list and the dropdown would assert on a value its
      // items no longer contain — a harness artefact, not an app defect.
      for (final (label, types) in <(String, List<String>)>[
        ('one type', ['FREE_DELIVERY_FIRST_ORDER']),
        ('two types', ['FREE_DELIVERY_FIRST_ORDER', 'FREE_DELIVERY_TEST_UNLIMITED']),
        ('no types', <String>[]),
        ('unknown type', ['SOMETHING_ELSE']),
      ]) {
        await t.pumpWidget(const SizedBox());
        final err = await probe(t, editScreen(_StubPromoRepo(), types));
        expect(err, isNull, reason: '$label threw: ${err ?? ""}');
        expect(
          find.byType(ListView).evaluate().isNotEmpty,
          isTrue,
          reason: '$label painted no body',
        );
      }
    });
  });
}
