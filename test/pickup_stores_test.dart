import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/stores/data/pickup_stores_repository.dart';

/// Parsing for the screen that decides which shops hand orders over.
///
/// The asymmetry is the whole thing. A shop wrongly shown as NOT doing pickup
/// costs an admin one confused moment. A shop wrongly shown as doing it is a
/// switch an admin then trusts, at a branch with nobody on the counter, while
/// customers pay in the app and drive over.
void main() {
  Map<String, dynamic> row({
    Object? pickup,
    Object? active,
    Object? id = 4,
  }) => <String, dynamic>{
        'store_id': id,
        'store_name': 'F-Mart Адырбекова',
        'store_address': 'Адырбекова',
        if (active != null) 'is_active': active,
        if (pickup != null) 'pickup_available': pickup,
      };

  group('pickup_available', () {
    test('only a real true means collection', () {
      expect(AdminStore.tryFromJson(row(pickup: true))!.pickupAvailable, isTrue);
    });

    test('anything else is not consent', () {
      // Includes the case that matters most: an older catalog that does not
      // send the key at all. `== true` rather than a cast, so junk cannot
      // throw and take the screen down either.
      for (final v in <Object?>[null, 'true', 'yes', 1, 0, '', <int>[]]) {
        expect(
          AdminStore.tryFromJson(row(pickup: v))!.pickupAvailable,
          isFalse,
          reason: 'pickup_available=$v',
        );
      }
    });
  });

  group('is_active', () {
    test('defaults to visible when the key is missing', () {
      // Opposite default from pickup, deliberately. Treating an absent
      // is_active as "hidden" would tag every shop with a warning that is not
      // true, and the warning is what explains a real hidden shop.
      expect(AdminStore.tryFromJson(row())!.isActive, isTrue);
    });

    test('only an explicit false marks a shop hidden', () {
      expect(AdminStore.tryFromJson(row(active: false))!.isActive, isFalse);
      expect(AdminStore.tryFromJson(row(active: true))!.isActive, isTrue);
    });
  });

  group('tolerance', () {
    test('a row with no usable id is dropped, not fatal', () {
      // One bad row must not blank a screen whose whole job is to show state.
      expect(AdminStore.tryFromJson(row(id: null)), isNull);
      expect(AdminStore.tryFromJson(row(id: 'abc')), isNull);
    });

    test('a numeric id arriving as a string still parses', () {
      expect(AdminStore.tryFromJson(row(id: '4'))!.storeId, 4);
    });
  });

  test('copyWith changes only the flag', () {
    final s = AdminStore.tryFromJson(row(pickup: false, active: false))!;
    final flipped = s.copyWith(pickupAvailable: true);
    expect(flipped.pickupAvailable, isTrue);
    expect(flipped.storeId, s.storeId);
    expect(flipped.storeName, s.storeName);
    expect(flipped.isActive, isFalse);
  });

  test('403 names the right missing right', () {
    // This endpoint is admin-only while the hold screen allows managers, so
    // the generic "нужны права сотрудника" would send a manager looking for a
    // permission they already have.
    expect(
      describePickupStoresError(_dio(403)),
      'Нужны права администратора',
    );
    expect(describePickupStoresError(_dio(401)), 'Войдите заново');
    expect(describePickupStoresError(_dio(404)), 'Магазин не найден');
  });
}

DioException _dio(int code) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response:
          Response(requestOptions: RequestOptions(path: '/x'), statusCode: code),
    );
