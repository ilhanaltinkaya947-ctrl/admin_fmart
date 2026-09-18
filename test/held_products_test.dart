// The held-products screen is the only place a hidden product is visible to
// anyone, and the only way to undo a hold before the 21-day expiry. These pin
// the parsing and the two rules that would quietly mislead an operator.
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:admin_fmart/features/stock/data/held_products_repository.dart';

void main() {
  group('parsing the server response', () {
    test('a normal row parses', () {
      final p = HeldProduct.tryFromJson({
        'product_id': 777,
        'name': 'Кофе Jacobs monarch 300гр',
        'quantity_reported_by_1c': 54,
        'held_at': '2026-09-18T06:23:08.100204Z',
      })!;
      expect(p.productId, 777);
      expect(p.quantityReportedBy1c, 54);
      // Shown to a human in the shop, so it must be their clock.
      expect(p.heldAt.isUtc, isFalse);
    });

    test('a null 1C quantity is allowed', () {
      // A hold placed moments ago has no baseline yet — the first sync sets it.
      // Treating that as a parse failure would hide the newest holds, which are
      // exactly the ones someone is looking for.
      final p = HeldProduct.tryFromJson({
        'product_id': 1,
        'name': 'x',
        'quantity_reported_by_1c': null,
        'held_at': '2026-09-18T06:23:08Z',
      });
      expect(p, isNotNull);
      expect(p!.quantityReportedBy1c, isNull);
    });

    test('a string product_id still parses', () {
      expect(HeldProduct.tryFromJson({
        'product_id': '777',
        'name': 'x',
        'held_at': '2026-09-18T06:23:08Z',
      })?.productId, 777);
    });

    test('an unusable row is skipped, not thrown', () {
      // One bad row must not blank a screen whose whole job is to make hidden
      // products visible — that would hide them twice over.
      expect(HeldProduct.tryFromJson({'name': 'no id'}), isNull);
      expect(HeldProduct.tryFromJson({'product_id': 1, 'held_at': 'nonsense'}),
          isNull);
    });
  });

  group('the error message says something useful', () {
    test('403 names the real cause', () {
      // The server gates this to admin/manager. A generic "could not load"
      // sends someone chasing the network instead of their role.
      final e = _dio(403);
      expect(describeHeldProductsError(e), contains('сотрудник'));
    });

    test('401 tells them to sign in again', () {
      expect(describeHeldProductsError(_dio(401)), contains('Войдите'));
    });

    test('anything else falls back without leaking internals', () {
      final msg = describeHeldProductsError(_dio(500));
      expect(msg, 'Не удалось загрузить список');
    });
  });
}

DioException _dio(int code) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: code),
    );
