import 'package:admin_fmart/features/promos/data/promo_models.dart';
import 'package:admin_fmart/features/promos/data/promo_repository.dart';
import 'package:admin_fmart/features/promos/presentation/promos_list_page.dart';
import 'package:admin_fmart/features/promos/state/promos_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart';

/// The Промокоды screen must PAINT in every reachable state.
///
/// This is the lesson from Баннеры: a blank body under a normal AppBar came
/// from a layout crash, and it survived code review plus a state-machine test
/// file because nothing had ever rendered the widget. So the new screen gets a
/// render test from the start, and every state is exercised — including the
/// ones a manager is least likely to see and most likely to be confused by.
class _StubPromoRepo implements PromoRepository {
  _StubPromoRepo({this.items = const []});

  final List<AdminPromo> items;

  @override
  Future<List<AdminPromo>> list() async => items;

  @override
  Future<List<String>> types() async => const ['FREE_DELIVERY_FIRST_ORDER'];

  @override
  Future<List<PromoRedemption>> redemptions(String code) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => NoopProxy().noSuchMethod(i);
}

class _FailingPromoRepo extends _StubPromoRepo {
  @override
  Future<List<AdminPromo>> list() async => throw Exception('network down');
}

AdminPromo p(String code, {bool enabled = true, int r = 0, int c = 0, String type = 'FREE_DELIVERY_FIRST_ORDER'}) =>
    AdminPromo(
      id: 1,
      code: code,
      promoType: type,
      enabled: enabled,
      redemptions: r,
      customers: c,
    );

Widget screen(PromoRepository repo) => BlocProvider(
      create: (_) => PromosCubit(repo: repo)..load(),
      child: const PromosListPage(),
    );

void main() {
  testWidgets('loaded with codes -> tiles paint, no layout throw', (t) async {
    final err = await renderProbe(
      t,
      screen(_StubPromoRepo(items: [p('FREEORDER', r: 119, c: 82), p('TESTFREE', type: 'FREE_DELIVERY_TEST_UNLIMITED')])),
    );
    expect(err, isNull, reason: err ?? '');
    expect(find.text('Промокоды'), findsOneWidget, reason: 'AppBar renders');
    expect(find.text('FREEORDER'), findsOneWidget);
    expect(find.text('TESTFREE'), findsOneWidget);
    // Both numbers must be visible and distinguishable.
    expect(find.text('Применений'), findsNWidgets(2));
    expect(find.text('Клиентов'), findsNWidgets(2));
  });

  testWidgets('the test-only type is WARNED about on the list', (t) async {
    final err = await renderProbe(
      t,
      screen(_StubPromoRepo(items: [p('TESTFREE', type: 'FREE_DELIVERY_TEST_UNLIMITED')])),
    );
    expect(err, isNull, reason: err ?? '');
    expect(
      find.textContaining('Тестовый тип'),
      findsOneWidget,
      reason: 'a code only allowlisted ids can use must say so, or marketing '
          'will ship it and wonder why nobody redeems it',
    );
  });

  testWidgets('EMPTY -> an explicit message, never a blank body', (t) async {
    final err = await renderProbe(t, screen(_StubPromoRepo(items: const [])));
    expect(err, isNull, reason: err ?? '');
    expect(find.text('Промокодов пока нет'), findsOneWidget);
    expect(find.byType(ListView), findsNothing,
        reason: 'an empty list must not reach a widget that paints nothing');
  });

  testWidgets('failure -> the error is named and a retry is offered', (t) async {
    final err = await renderProbe(t, screen(_FailingPromoRepo()));
    expect(err, isNull, reason: err ?? '');
    expect(find.text('Не удалось загрузить промокоды'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('every reachable state paints content in the body', (t) async {
    for (final (label, repo) in <(String, PromoRepository)>[
      ('loaded', _StubPromoRepo(items: [p('A')])),
      ('empty', _StubPromoRepo(items: const [])),
      ('failure', _FailingPromoRepo()),
    ]) {
      final err = await renderProbe(t, screen(repo));
      expect(err, isNull, reason: '$label threw: ${err ?? ""}');
      final painted = find.byType(Center).evaluate().isNotEmpty ||
          find.byType(ListView).evaluate().isNotEmpty;
      expect(painted, isTrue, reason: '$label painted no content');
    }
  });
}
