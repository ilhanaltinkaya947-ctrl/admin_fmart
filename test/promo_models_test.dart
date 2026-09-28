import 'package:admin_fmart/features/promos/data/promo_models.dart';
import 'package:admin_fmart/features/promos/data/promo_repository.dart';
import 'package:admin_fmart/features/promos/state/promos_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Promo model + cubit rules and the payload the client is allowed to send.
///
/// The load-bearing claims here are the ones that are easy to get silently
/// wrong:
///   - `expires_at: null` means "no expiry", NOT "expired".
///   - redemptions and customers are different numbers.
///   - clearing an expiry is a distinct instruction from omitting it.
class _StubRepo implements PromoRepository {
  _StubRepo({this.items = const [], this.availableTypes = const []});

  final List<AdminPromo> items;
  final List<String> availableTypes;

  int createCalls = 0;
  Map<String, dynamic>? lastCreateBody;
  Map<String, dynamic>? lastUpdateBody;

  @override
  Future<List<AdminPromo>> list() async => items;

  @override
  Future<List<String>> types() async => availableTypes;

  @override
  Future<AdminPromo> create({
    required String code,
    required String promoType,
    bool enabled = true,
    DateTime? expiresAt,
  }) async {
    createCalls++;
    lastCreateBody = {
      'code': code,
      'promo_type': promoType,
      'enabled': enabled,
      if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
    };
    return AdminPromo(id: 99, code: code, promoType: promoType, enabled: enabled);
  }

  @override
  Future<AdminPromo> update(
    String code, {
    bool? enabled,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) async {
    lastUpdateBody = {
      if (enabled != null) 'enabled': enabled,
      if (clearExpiry) 'clear_expires_at': true,
      if (!clearExpiry && expiresAt != null)
        'expires_at': expiresAt.toUtc().toIso8601String(),
    };
    return AdminPromo(id: 1, code: code, promoType: 't', enabled: enabled ?? true);
  }

  @override
  Future<List<PromoRedemption>> redemptions(String code) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

AdminPromo promo(
  String code, {
  bool enabled = true,
  DateTime? expiresAt,
  int redemptions = 0,
  int customers = 0,
  String type = 'FREE_DELIVERY_FIRST_ORDER',
}) =>
    AdminPromo(
      id: 1,
      code: code,
      promoType: type,
      enabled: enabled,
      expiresAt: expiresAt,
      redemptions: redemptions,
      customers: customers,
    );

void main() {
  group('AdminPromo.fromJson', () {
    test('null expires_at means NO EXPIRY, not expired', () {
      final p = AdminPromo.fromJson({
        'id': 1,
        'code': 'FREEORDER',
        'promo_type': 'FREE_DELIVERY_FIRST_ORDER',
        'enabled': true,
        'expires_at': null,
      });
      expect(p.expiresAt, isNull);
      expect(p.isExpired, isFalse,
          reason: 'falling back to now() here would mark every code expired');
      expect(p.state, AdminPromoState.live);
    });

    test('absent keys do not throw (older backend)', () {
      final p = AdminPromo.fromJson({'id': 2, 'code': 'X'});
      expect(p.code, 'X');
      expect(p.enabled, isFalse, reason: 'default must be the safe one');
      expect(p.redemptions, 0);
      expect(p.customers, 0);
    });

    test('a past expires_at is EXPIRED', () {
      final p = AdminPromo.fromJson({
        'id': 1,
        'code': 'OLD',
        'promo_type': 'FREE_DELIVERY_FIRST_ORDER',
        'enabled': true,
        'expires_at': '2020-01-01T00:00:00Z',
      });
      expect(p.isExpired, isTrue);
      expect(p.state, AdminPromoState.expired);
    });

    test('disabled outranks expired in the state chip', () {
      final p = AdminPromo.fromJson({
        'id': 1,
        'code': 'OFF',
        'promo_type': 'FREE_DELIVERY_FIRST_ORDER',
        'enabled': false,
        'expires_at': '2020-01-01T00:00:00Z',
      });
      expect(p.state, AdminPromoState.disabled,
          reason: 'the switch is the operator-visible fact; report it first');
    });

    test('an unknown promo_type is shown raw, never guessed', () {
      final p = AdminPromo.fromJson({
        'id': 1,
        'code': 'X',
        'promo_type': 'SOME_FUTURE_TYPE',
      });
      expect(p.typeLabel, 'SOME_FUTURE_TYPE',
          reason: 'an unmapped type must be visible, not silently relabelled');
    });

    test('the TEST type is flagged as test-only', () {
      final p = promo('T', type: 'FREE_DELIVERY_TEST_UNLIMITED');
      expect(p.isTestOnly, isTrue);
      expect(promo('F').isTestOnly, isFalse);
    });
  });

  group('PromosCubit', () {
    test('orders live codes first, then by code', () async {
      final cubit = PromosCubit(
        repo: _StubRepo(items: [
          promo('ZZZ'),
          promo('AAA', enabled: false),
          promo('BBB'),
        ]),
      );
      await cubit.load();
      final s = cubit.state as PromosLoaded;
      expect(s.items.map((p) => p.code).toList(), ['BBB', 'ZZZ', 'AAA'],
          reason: 'a disabled code must not bury a live campaign');
    });

    test('a types failure does NOT blank the list', () async {
      // Repo where types() throws but list() works.
      final cubit = PromosCubit(repo: _TypesFailingRepo([promo('A')]));
      await cubit.load();
      expect(cubit.state, isA<PromosLoaded>(),
          reason: 'the picker is secondary; losing it must not hide the codes');
      expect((cubit.state as PromosLoaded).items.length, 1);
      expect((cubit.state as PromosLoaded).types, isEmpty);
    });

    test('a list failure becomes a named Failure, not a blank', () async {
      final cubit = PromosCubit(repo: _ListFailingRepo());
      await cubit.load();
      expect(cubit.state, isA<PromosFailure>());
      expect((cubit.state as PromosFailure).message, isNotEmpty);
    });

    test('toggle OFF sends enabled:false', () async {
      final repo = _StubRepo(items: [promo('A')]);
      final cubit = PromosCubit(repo: repo);
      await cubit.load();
      await cubit.update('A', enabled: false);
      expect(repo.lastUpdateBody, {'enabled': false});
    });

    test('toggling does NOT send an expiry it was not asked to change', () async {
      final repo = _StubRepo(items: [promo('A')]);
      final cubit = PromosCubit(repo: repo);
      await cubit.load();
      await cubit.update('A', enabled: true);
      expect(repo.lastUpdateBody!.containsKey('expires_at'), isFalse);
      expect(repo.lastUpdateBody!.containsKey('clear_expires_at'), isFalse,
          reason: 'a plain toggle must not silently wipe a scheduled expiry');
    });

    test('clearExpiry sends the explicit clear flag, not a null date', () async {
      final repo = _StubRepo(items: [promo('A')]);
      final cubit = PromosCubit(repo: repo);
      await cubit.load();
      await cubit.update('A', clearExpiry: true);
      expect(repo.lastUpdateBody, {'clear_expires_at': true},
          reason: 'null is indistinguishable from absent over JSON');
    });

    test('setting an expiry sends it in UTC ISO-8601', () async {
      final repo = _StubRepo(items: [promo('A')]);
      final cubit = PromosCubit(repo: repo);
      await cubit.load();
      final when = DateTime.utc(2027, 1, 15, 12, 0);
      await cubit.update('A', expiresAt: when);
      expect(repo.lastUpdateBody!['expires_at'], '2027-01-15T12:00:00.000Z');
    });

    test('an update rejection keeps the list AND reports the error', () async {
      final repo = _UpdateFailingRepo([promo('A')]);
      final cubit = PromosCubit(repo: repo);
      await cubit.load();
      expect(cubit.state, isA<PromosLoaded>());
      await cubit.update('A', enabled: false);

      // The optimistic flip must not survive a rejected write...
      final s = cubit.state;
      expect(s, isA<PromosLoaded>(),
          reason: 'one refused toggle must not replace the whole list with an '
              'error page — the codes are still right there');
      expect((s as PromosLoaded).items.first.enabled, isTrue,
          reason: 'the list snapped back to what the server holds');
      // ...and the operator must be TOLD, not left watching the switch revert.
      expect(s.writeError, isNotNull,
          reason: 'a silent revert makes the UI lie about what happened');
      expect(repo.listCalls, greaterThan(1),
          reason: 'must reload so the list shows the server truth');
    });

    test('a successful write leaves no error behind', () async {
      final repo = _StubRepo(items: [promo('A')]);
      final cubit = PromosCubit(repo: repo);
      await cubit.load();
      await cubit.update('A', enabled: false);
      expect((cubit.state as PromosLoaded).writeError, isNull);
    });

    test('reset() wipes state for the next operator', () async {
      final cubit = PromosCubit(repo: _StubRepo(items: [promo('A')]));
      await cubit.load();
      expect(cubit.state, isA<PromosLoaded>());
      cubit.reset();
      expect(cubit.state, isA<PromosInitial>());
    });
  });
}

class _TypesFailingRepo extends _StubRepo {
  _TypesFailingRepo(List<AdminPromo> items) : super(items: items);

  @override
  Future<List<String>> types() async => throw Exception('types unavailable');
}

class _ListFailingRepo extends _StubRepo {
  @override
  Future<List<AdminPromo>> list() async => throw Exception('network down');
}

class _UpdateFailingRepo extends _StubRepo {
  _UpdateFailingRepo(List<AdminPromo> items) : super(items: items);
  int listCalls = 0;

  @override
  Future<List<AdminPromo>> list() async {
    listCalls++;
    return items;
  }

  @override
  Future<AdminPromo> update(
    String code, {
    bool? enabled,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) async =>
      throw Exception('409 conflict');
}
