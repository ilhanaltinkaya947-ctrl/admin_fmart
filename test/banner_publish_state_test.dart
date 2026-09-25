import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/banners/data/banner_models.dart';

/// The publish window decides what customers see on the storefront, so the
/// state machine is asserted directly rather than eyeballed in the UI.
///
/// The rule mirrors app/repositories/banner_repository.py `list_active()`,
/// which filters on:
///     starts_at IS NULL OR starts_at <= now
///     ends_at   IS NULL OR ends_at   >  now
/// plus `active`. If these two ever disagree, the admin list and the
/// storefront tell different stories — which is exactly the class of bug
/// that made a scheduled banner look live to the operator.
void main() {
  BannerItem banner({
    bool active = true,
    DateTime? startsAt,
    DateTime? endsAt,
  }) {
    final now = DateTime(2026, 6, 15, 12, 0);
    return BannerItem(
      id: 1,
      imageUrl: 'https://example.invalid/x.jpg',
      sortOrder: 0,
      active: active,
      startsAt: startsAt,
      endsAt: endsAt,
      createdAt: now,
      updatedAt: now,
    );
  }

  final now = DateTime.now();

  group('publishState', () {
    test('no window + active => live', () {
      expect(banner().publishState, BannerPublishState.live);
    });

    test('inactive => disabled, regardless of window', () {
      expect(banner(active: false).publishState, BannerPublishState.disabled);
      expect(
        banner(active: false, startsAt: now.subtract(const Duration(days: 1)))
            .publishState,
        BannerPublishState.disabled,
      );
    });

    test('start in the future => scheduled', () {
      expect(
        banner(startsAt: now.add(const Duration(days: 2))).publishState,
        BannerPublishState.scheduled,
      );
    });

    test('start in the past => live', () {
      expect(
        banner(startsAt: now.subtract(const Duration(days: 2))).publishState,
        BannerPublishState.live,
      );
    });

    test('end in the past => expired', () {
      expect(
        banner(endsAt: now.subtract(const Duration(minutes: 1))).publishState,
        BannerPublishState.expired,
      );
    });

    test('end in the future => live', () {
      expect(
        banner(endsAt: now.add(const Duration(days: 1))).publishState,
        BannerPublishState.live,
      );
    });

    test('window currently open => live', () {
      expect(
        banner(
          startsAt: now.subtract(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 1)),
        ).publishState,
        BannerPublishState.live,
      );
    });

    test('scheduled beats expired: a future start wins', () {
      // Degenerate window saved before validation existed (or set via SQL):
      // both dates in the past would be expired, but a future start must
      // read as scheduled so the operator knows it is waiting to run.
      expect(
        banner(startsAt: now.add(const Duration(days: 1))).publishState,
        BannerPublishState.scheduled,
      );
    });

    test('only startsAt set, in the past, no end => live forever', () {
      expect(
        banner(startsAt: now.subtract(const Duration(days: 365))).publishState,
        BannerPublishState.live,
      );
    });

    test('only endsAt set, no start => live until it ends', () {
      expect(
        banner(endsAt: now.add(const Duration(seconds: 30))).publishState,
        BannerPublishState.live,
      );
    });
  });

  group('fromJson', () {
    test('null window parses to nulls, not to now()', () {
      final b = BannerItem.fromJson({
        'id': 7,
        'image_url': 'https://example.invalid/a.jpg',
        'sort_order': 3,
        'active': true,
        'starts_at': null,
        'ends_at': null,
        'created_at': '2026-06-15T12:00:00Z',
        'updated_at': '2026-06-15T12:00:00Z',
      });
      expect(b.startsAt, isNull);
      expect(b.endsAt, isNull);
      expect(b.publishState, BannerPublishState.live);
    });

    test('absent window keys (older backend) do not throw', () {
      final b = BannerItem.fromJson({
        'id': 8,
        'image_url': 'https://example.invalid/b.jpg',
        'sort_order': 4,
        'active': true,
        'created_at': '2026-06-15T12:00:00Z',
        'updated_at': '2026-06-15T12:00:00Z',
      });
      expect(b.startsAt, isNull);
      expect(b.endsAt, isNull);
    });

    test('ISO window parsed and converted to local', () {
      final b = BannerItem.fromJson({
        'id': 9,
        'image_url': 'https://example.invalid/c.jpg',
        'sort_order': 5,
        'active': true,
        'starts_at': '2026-06-15T12:00:00Z',
        'ends_at': '2026-06-20T12:00:00Z',
        'created_at': '2026-06-15T12:00:00Z',
        'updated_at': '2026-06-15T12:00:00Z',
      });
      expect(b.startsAt!.toUtc(), DateTime.utc(2026, 6, 15, 12));
      expect(b.endsAt!.toUtc(), DateTime.utc(2026, 6, 20, 12));
    });

    test('garbage window string degrades to null, does not throw', () {
      final b = BannerItem.fromJson({
        'id': 10,
        'image_url': 'https://example.invalid/d.jpg',
        'sort_order': 6,
        'active': true,
        'starts_at': 'not-a-date',
        'ends_at': '',
        'created_at': '2026-06-15T12:00:00Z',
        'updated_at': '2026-06-15T12:00:00Z',
      });
      expect(b.startsAt, isNull);
      expect(b.endsAt, isNull);
    });
  });

  group('labels', () {
    test('every state has operator-facing Russian text', () {
      for (final s in BannerPublishState.values) {
        expect(s.label, isNotEmpty);
      }
      expect(BannerPublishState.live.label, 'На главной');
      expect(BannerPublishState.scheduled.label, 'Запланирован');
      expect(BannerPublishState.expired.label, 'Истёк');
      expect(BannerPublishState.disabled.label, 'Отключён');
    });
  });
}
