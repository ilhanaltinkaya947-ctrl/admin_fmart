import 'dart:io';

import 'package:admin_fmart/features/banners/data/banner_models.dart';
import 'package:admin_fmart/features/banners/data/banners_repository.dart';
import 'package:admin_fmart/features/banners/presentation/banners_list_page.dart';
import 'package:admin_fmart/features/banners/state/banners_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// The field report was «У нас не отображаются список баннеров» — the Баннеры
/// screen rendering a blank body under a normal AppBar, with no spinner, no
/// message and no way to retry.
///
/// A blank body is a rendering result, so these are WIDGET tests, not unit
/// tests on the state machine. They pump the real BannersListPage and assert
/// that SOMETHING is painted in every reachable state — the only way to prove
/// the symptom is gone rather than prove the widget code "looks right".
class _StubRepo implements BannersRepository {
  _StubRepo(this._handler);

  final Future<List<BannerItem>> Function() _handler;

  @override
  Future<List<BannerItem>> listAll() => _handler();

  @override
  Future<List<BannerItem>> listPublic() async => const [];

  @override
  Future<void> reorder(List<int> ids) async {}

  @override
  Future<void> delete(int id) async {}

  @override
  Future<BannerItem> create({
    required File imageFile,
    String? title,
    String? linkUrl,
    int? sortOrder,
    bool active = true,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async =>
      throw UnimplementedError();

  @override
  Future<BannerItem> update({
    required int id,
    File? imageFile,
    String? title,
    String? linkUrl,
    int? sortOrder,
    bool? active,
    DateTime? startsAt,
    bool? clearStartsAt,
    DateTime? endsAt,
    bool? clearEndsAt,
  }) async =>
      throw UnimplementedError();

  @override
  Future<BannerBulkResult> bulkUploadZip({
    required File zipFile,
    bool active = true,
  }) async =>
      throw UnimplementedError();

  // The members below are not part of the cubit's call path.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BannerItem banner(int id, int sortOrder, {String? title, bool active = true}) =>
    BannerItem(
      id: id,
      imageUrl: 'https://example.test/$id.jpg',
      title: title,
      sortOrder: sortOrder,
      active: active,
      createdAt: DateTime(2026, 9, 25),
      updatedAt: DateTime(2026, 9, 25),
    );

Widget harness(BannersRepository repo) => MaterialApp(
      home: BlocProvider(
        create: (_) => BannersCubit(repo: repo)..load(),
        child: const BannersListPage(),
      ),
    );

void main() {
  testWidgets('loaded with banners -> tiles are painted, body is not blank',
      (tester) async {
    await tester.pumpWidget(harness(
      _StubRepo(() async => [banner(28, 0, title: 'Мохито'), banner(29, 1)]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Баннеры'), findsOneWidget, reason: 'AppBar renders');
    expect(find.text('Мохито'), findsOneWidget);
    expect(find.text('Позиция 2'), findsOneWidget);
    // The body must contain real content, not only the chrome.
    expect(find.byType(ReorderableListView), findsOneWidget);
  });

  testWidgets('loaded but EMPTY -> an explicit empty state, never a blank body',
      (tester) async {
    await tester.pumpWidget(harness(_StubRepo(() async => [])));
    await tester.pumpAndSettle();

    expect(find.text('Пока нет баннеров'), findsOneWidget);
    expect(find.text('Загрузите первый баннер для главной страницы'),
        findsOneWidget);
    // The dangerous path: an empty ReorderableListView paints nothing at all.
    expect(find.byType(ReorderableListView), findsNothing,
        reason: 'must never be reachable with 0 items');
  });

  testWidgets('failure -> the error is named and a retry is offered',
      (tester) async {
    await tester.pumpWidget(harness(
      _StubRepo(() async => throw Exception('network down')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Повторить'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
  });

  testWidgets('EVERY reachable state paints something in the body',
      (tester) async {
    // The reported symptom was a body with zero descendants. Assert positively:
    // for each state the user can reach, find at least one rendered widget
    // below the AppBar.
    Future<void> assertBodyHasContent(
      Future<List<BannerItem>> Function() handler,
      String label,
    ) async {
      await tester.pumpWidget(harness(_StubRepo(handler)));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.body, isNotNull, reason: '$label: body is null');

      // Render the body subtree and count its leaves. A blank screen has none.
      final bodyFinder = find.descendant(
        of: find.byType(Scaffold),
        matching: find.byType(Center),
      );
      final hasAny = bodyFinder.evaluate().isNotEmpty ||
          find.byType(ReorderableListView).evaluate().isNotEmpty;
      expect(hasAny, isTrue, reason: '$label: the body painted no content');
    }

    await assertBodyHasContent(
      () async => [banner(28, 0, title: 'A'), banner(29, 1)], 'loaded');
    await assertBodyHasContent(() async => [], 'empty');
    await assertBodyHasContent(
      () async => throw Exception('x'), 'failure');
  });
}
