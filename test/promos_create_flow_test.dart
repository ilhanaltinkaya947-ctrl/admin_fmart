import 'package:admin_fmart/features/promos/data/promo_models.dart';
import 'package:admin_fmart/features/promos/data/promo_repository.dart';
import 'package:admin_fmart/features/promos/presentation/promo_edit_page.dart';
import 'package:admin_fmart/features/promos/state/promos_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart';

/// The CREATE path: what the code field sends, and what the operator is told
/// when the server refuses.
///
/// The render tests prove the screen paints. These prove it does the right
/// thing when tapped — which is where a promo code that looks saved but is
/// not, or a code saved under the wrong name, would come from.
///
/// Three things are load-bearing and all three are silent when wrong:
///   1. the code is TRIMMED and UPPERCASED before it is sent, because the
///      customer types it at checkout and the engine matches exactly
///   2. client validation mirrors the server's rules, so the operator learns
///      about a bad code before a round trip
///   3. a refusal is SHOWN. A create that fails silently leaves the manager
///      believing a campaign is live.
///
/// Records what the page asks for, and can be told to refuse.
///
/// `implements`, not `extends`: `PromoRepository`'s constructor requires an
/// `ApiClient`, and a test has no business constructing one. Implementing the
/// interface lets the stub stand in without an HTTP stack at all.
class _RecordingRepo implements PromoRepository {
  _RecordingRepo({this.onCreate});

  /// Records exactly what the page asked the repo to create.
  String? sentCode;
  String? sentType;
  bool? sentEnabled;
  DateTime? sentExpiresAt;
  int createCalls = 0;

  /// Lets a test make create() refuse.
  final Future<AdminPromo> Function(String code)? onCreate;

  @override
  Future<List<AdminPromo>> list() async => const [];

  @override
  Future<List<String>> types() async => const ['FREE_DELIVERY_FIRST_ORDER'];

  @override
  Future<List<PromoRedemption>> redemptions(String code) async => const [];

  @override
  Future<AdminPromo> create({
    required String code,
    required String promoType,
    bool enabled = true,
    DateTime? expiresAt,
  }) async {
    createCalls++;
    sentCode = code;
    sentType = promoType;
    sentEnabled = enabled;
    sentExpiresAt = expiresAt;
    if (onCreate != null) return onCreate!(code);
    return AdminPromo(id: 1, code: code, promoType: promoType, enabled: enabled);
  }

  @override
  dynamic noSuchMethod(Invocation i) => NoopProxy().noSuchMethod(i);
}

class _RevalidatingRepo extends _RecordingRepo {
  _RevalidatingRepo() : super(onCreate: _refuse);

  static Future<AdminPromo> _refuse(String code) async =>
      throw PromoValidationException('Такой код уже существует');
}

class _BrokenRepo extends _RecordingRepo {
  _BrokenRepo() : super(onCreate: _explode);

  static Future<AdminPromo> _explode(String code) async =>
      throw Exception('connection reset');
}

Widget screen(PromoRepository repo, {List<String>? types}) => harness(
      child: RepositoryProvider<PromoRepository>.value(
        value: repo,
        child: BlocProvider(
          create: (_) => PromosCubit(repo: repo),
          child: PromoEditPage(
            availableTypes: types ?? const ['FREE_DELIVERY_FIRST_ORDER'],
          ),
        ),
      ),
    );

/// Tap "Создать" and let the async path settle.
Future<void> tapCreate(WidgetTester t) async {
  await t.tap(find.text('Создать'));
  await t.pumpAndSettle();
}

/// Type a code into the field.
Future<void> enterCode(WidgetTester t, String code) async {
  await t.enterText(find.byType(TextField), code);
  await t.pump();
}

void main() {
  setUp(() {
    // The page is a full-height ListView; a phone-shaped surface keeps every
    // control built (see the render test file for why 800x600 is not enough).
  });

  group('what actually gets sent', () {
    testWidgets('the code is trimmed and uppercased', (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      // A manager will type it in whatever case and with a stray space —
      // the customer types it at checkout and the engine matches exactly.
      await enterCode(t, '  firstorder  ');
      await tapCreate(t);

      expect(repo.createCalls, 1, reason: 'create was actually called');
      expect(repo.sentCode, 'FIRSTORDER',
          reason: 'sent trimmed + uppercased, not as typed');
    });

    testWidgets('the selected type and the enabled switch are sent', (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      await enterCode(t, 'SUMMER24');
      await tapCreate(t);

      expect(repo.sentType, 'FREE_DELIVERY_FIRST_ORDER');
      expect(repo.sentEnabled, isTrue, reason: 'switch defaults to on');
      expect(repo.sentExpiresAt, isNull, reason: 'no date chosen = no expiry');
    });

    testWidgets('a successful create closes the page reporting success',
        (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      bool? popped;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(ctx).push<bool>(
                MaterialPageRoute(
                  builder: (_) => RepositoryProvider<PromoRepository>.value(
                    value: repo,
                    child: BlocProvider(
                      create: (_) => PromosCubit(repo: repo),
                      child: const PromoEditPage(
                        availableTypes: ['FREE_DELIVERY_FIRST_ORDER'],
                      ),
                    ),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      await enterCode(t, 'LAUNCH');
      await tapCreate(t);

      expect(popped, isTrue,
          reason: 'the caller needs to know it worked so it can refresh');
      expect(find.text('Создать'), findsNothing, reason: 'page was popped');
    });
  });

  group('client validation happens before any round trip', () {
    testWidgets('a code shorter than 3 characters is refused locally',
        (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      await enterCode(t, 'AB');
      await tapCreate(t);

      expect(find.text('Код должен быть не короче 3 символов'), findsOneWidget);
      expect(
        repo.createCalls,
        0,
        reason: 'no round trip for an input the server would reject anyway',
      );
    });

    testWidgets('a code longer than 64 characters is refused locally',
        (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      await enterCode(t, 'A' * 65);
      await tapCreate(t);

      expect(find.text('Код слишком длинный (максимум 64)'), findsOneWidget);
      expect(repo.createCalls, 0);
    });

    testWidgets('exactly 64 characters is accepted (boundary)',
        (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      final code = 'B' * 64;
      await enterCode(t, code);
      await tapCreate(t);

      expect(repo.createCalls, 1,
          reason: '64 is the maximum, not one past it — the boundary must '
              'pass or the limit is off by one');
      expect(repo.sentCode, code);
    });

    testWidgets('exactly 3 characters is accepted (lower boundary)',
        (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      await enterCode(t, 'ABC');
      await tapCreate(t);

      expect(repo.createCalls, 1, reason: '3 is allowed; 2 is not');
    });

    testWidgets('Cyrillic is refused with the reason, not silently',
        (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      // A very likely operator mistake in a Russian-language app.
      await enterCode(t, 'ЛЕТО2026');
      await tapCreate(t);

      expect(
        find.text('Только латинские буквы, цифры, дефис и подчёркивание'),
        findsOneWidget,
      );
      expect(repo.createCalls, 0);
    });

    testWidgets('spaces inside the code are refused', (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      await enterCode(t, 'SUMMER 24');
      await tapCreate(t);

      expect(find.textContaining('Только латинские буквы'), findsOneWidget);
      expect(repo.createCalls, 0);
    });

    testWidgets('hyphen and underscore are allowed in a code', (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _RecordingRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      await enterCode(t, 'FREE_DELIVERY-2024');
      await tapCreate(t);

      expect(repo.createCalls, 1, reason: '_-  are valid code characters');
      expect(repo.sentCode, 'FREE_DELIVERY-2024');
    });
  });

  group('a refusal is shown, never swallowed', () {
    testWidgets('a server rejection shows the server\'s own message',
        (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(screen(_RevalidatingRepo()));
      await t.pump();

      await enterCode(t, 'DUPLICATE');
      await tapCreate(t);

      expect(
        find.text('Такой код уже существует'),
        findsOneWidget,
        reason: 'the backend writes these in Russian for the operator — '
            'showing it is the whole point of the typed exception',
      );
      expect(find.text('Создать'), findsWidgets,
          reason: 'the page stays open so they can fix the code');
    });

    testWidgets('an unexpected failure is reported and the page stays open',
        (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(screen(_BrokenRepo()));
      await t.pump();

      await enterCode(t, 'WILLFAIL');
      await tapCreate(t);

      expect(
        find.textContaining('Не удалось создать'),
        findsOneWidget,
        reason: 'a failed create that says nothing leaves the manager '
            'believing the campaign is live',
      );
      expect(find.text('Создать'), findsWidgets, reason: 'page not popped');
    });

    testWidgets('after a failure the button is usable again', (t) async {
      t.view.physicalSize = const Size(1170, 4200);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);

      final repo = _BrokenRepo();
      await t.pumpWidget(screen(repo));
      await t.pump();

      await enterCode(t, 'WILLFAIL');
      await tapCreate(t);
      expect(repo.createCalls, 1);

      // _saving must be reset in the catch, or the operator is left with a
      // dead button and no way to retry after fixing the network.
      await t.tap(find.text('Создать'));
      await t.pumpAndSettle();
      expect(repo.createCalls, 2, reason: 'the retry actually reached the repo');
    });
  });
}
