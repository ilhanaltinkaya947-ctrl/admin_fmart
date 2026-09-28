import 'package:admin_fmart/features/banners/data/banner_models.dart';
import 'package:admin_fmart/features/banners/data/banners_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// `reorder()` on the server numbers each id by its index in the list it
/// receives, and orders the table with a flat `ORDER BY sort_order ASC, id ASC`.
/// The admin list holds 35 rows; the storefront shows 13. Sending everything
/// renumbers banners the operator never touched, so these tests pin the payload
/// the client is allowed to produce — and the cases it must refuse.
void main() {
  BannerItem banner(int id, int sortOrder, {bool active = true}) => BannerItem(
        id: id,
        imageUrl: 'https://example.test/$id.jpg',
        sortOrder: sortOrder,
        active: active,
        createdAt: DateTime(2026, 9, 25),
        updatedAt: DateTime(2026, 9, 25),
      );

  /// The exact prod table, read from catalog_db on 2026-09-28:
  /// 35 rows, 13 active at 0..12, inactive placeholders sharing those values
  /// (5 at 3 with 31, 6 at 4 with 32, … 14 at 12 with 40), then 15..26 at 13..24.
  List<BannerItem> prodShape() => [
        banner(28, 0), banner(29, 1), banner(30, 2),
        banner(5, 3, active: false), banner(31, 3),
        banner(6, 4, active: false), banner(32, 4),
        banner(7, 5, active: false), banner(33, 5),
        banner(8, 6, active: false), banner(34, 6),
        banner(9, 7, active: false), banner(35, 7),
        banner(10, 8, active: false), banner(36, 8),
        banner(11, 9, active: false), banner(37, 9),
        banner(12, 10, active: false), banner(38, 10),
        banner(13, 11, active: false), banner(39, 11),
        banner(14, 12, active: false), banner(40, 12),
        banner(15, 13, active: false), banner(16, 14, active: false),
        banner(17, 15, active: false), banner(18, 16, active: false),
        banner(19, 17, active: false), banner(20, 18, active: false),
        banner(21, 19, active: false), banner(22, 20, active: false),
        banner(23, 21, active: false), banner(27, 22, active: false),
        banner(25, 23, active: false), banner(26, 24, active: false),
      ];

  group('compare — total order mirrors the server', () {
    test('sort_order first, then id as the tiebreak', () {
      expect(BannersRepository.compare(banner(31, 3), banner(32, 4)), lessThan(0));
      expect(BannersRepository.compare(banner(32, 4), banner(31, 3)), greaterThan(0));
      // Same sort_order 3: id 5 must sort before id 31, matching `id ASC`.
      expect(BannersRepository.compare(banner(5, 3), banner(31, 3)), lessThan(0));
    });

    test('prod shape sorts to a fixed point, ties broken by id', () {
      final items = prodShape()..sort(BannersRepository.compare);
      final order = items.map((b) => b.id).toList();

      // The tie at sort_order 3 is between id 5 (inactive) and id 31 (active).
      // The server's tiebreak is `id ASC`, NOT active-first, so 5 comes first.
      // The client must match the server, not "improve" on it — otherwise the
      // tiles shuffle the moment the list is reloaded from the API.
      expect(order.indexOf(5), lessThan(order.indexOf(31)));
      expect(order.indexOf(6), lessThan(order.indexOf(32)));
      expect(order.indexOf(14), lessThan(order.indexOf(40)));
      // 28,29,30 have no tie and come first.
      expect(order.take(3).toList(), [28, 29, 30]);

      // Re-sorting changes nothing: the order is a fixed point.
      final again = [...items]..sort(BannersRepository.compare);
      expect(again.map((b) => b.id).toList(), order);
    });
  });

  group('reorderPayload — the safe subset rule', () {
    test('values are a permutation of 0..n-1 -> ids in the given order', () {
      // Post-drag sequence: 31 moved to the front. Values 3,0,1,2 are a
      // permutation of 0..3, so renumbering the same 4 slots is faithful.
      final items = [banner(31, 3), banner(28, 0), banner(29, 1), banner(30, 2)];
      expect(BannersRepository.reorderPayload(items), [31, 28, 29, 30]);
    });

    test('a value >= n -> null', () {
      // Ids 5,6 sit at 3,4. Writing index 0 to id 5 would put it in front of
      // the banners at 0..2 that are not in the payload — the corruption this
      // guards against.
      expect(BannersRepository.reorderPayload([
        banner(5, 3),
        banner(6, 4),
      ]), isNull);
    });

    test('a duplicate value -> null', () {
      // Two rows claiming slot 3. The server would tiebreak by id and silently
      // reorder against what the operator saw.
      expect(BannersRepository.reorderPayload([
        banner(5, 3),
        banner(31, 3),
        banner(28, 0),
      ]), isNull);
    });

    test('a gap -> null', () {
      expect(BannersRepository.reorderPayload([
        banner(28, 0),
        banner(30, 2),
      ]), isNull);
    });

    test('the full prod table -> null (35 rows, 13 duplicated values)', () {
      expect(BannersRepository.reorderPayload(prodShape()), isNull);
    });

    test('empty -> null (the server 422s on min_length=1)', () {
      expect(BannersRepository.reorderPayload(const []), isNull);
    });

    test('a single banner at slot 0 is a valid one-item payload', () {
      expect(BannersRepository.reorderPayload([banner(28, 0)]), [28]);
    });
  });

  group('movedOrder — the drag the UI actually performs', () {
    /// The live set alone: 13 active banners, 0..12, no ties. This is what the
    /// admin reorders in the normal case.
    List<BannerItem> live() =>
        List.generate(13, (i) => banner(28 + i, i));

    test('drag the last tile to the front renumbers the others up', () {
      expect(BannersRepository.movedOrder(live(), 12, 0), [
        40, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
      ]);
    });

    test('drag the first tile to the end (newIndex is post-removal)', () {
      // Flutter reports newIndex as the index the tile would land at once it
      // has been lifted out, so moving index 0 to the end arrives as (0, 13).
      final result = BannersRepository.movedOrder(live(), 0, 13);
      expect(result, [29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 28]);
    });

    test('moving DOWN applies the same post-removal convention', () {
      // Index 0 dropped at reported index 3 lands after 29 and 30.
      expect(BannersRepository.movedOrder(live(), 0, 3), [
        29, 30, 28, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
      ]);
    });

    test('a swap of adjacent tiles', () {
      expect(BannersRepository.movedOrder(live(), 1, 3), [
        28, 30, 29, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
      ]);
    });

    test('out-of-range indices are refused rather than clamped', () {
      expect(BannersRepository.movedOrder(live(), 99, 0), isNull);
      expect(BannersRepository.movedOrder(live(), 0, 99), isNull);
      expect(BannersRepository.movedOrder(live(), -1, 0), isNull);
    });

    test('the full prod list refuses a drag instead of corrupting 11 banners',
        () {
      // Regression guard for the measured production defect: passing the whole
      // 35-row admin list sent 35 ids and moved 11 of the 13 live banners to
      // storefront positions 0,2,4,6,8,10,12,14,16,18,20,22.
      final items = prodShape()..sort(BannersRepository.compare);
      final last = items.length - 1;
      expect(BannersRepository.movedOrder(items, last, 2), isNull);
      expect(BannersRepository.movedOrder(items, 0, last), isNull);
      expect(BannersRepository.movedOrder(items, 5, 0), isNull);
    });
  });
}
