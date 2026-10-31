// «Если товара нет в наличии» (257) in the store app: the customer's choice is
// shown on the order and in the picker; «Убрать товар» skips the picker; the
// «Не дозвонился» flag reaches the server.
import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/feature_flags.dart';
import 'package:admin_fmart/core/storage/token_storage.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/missing_item_choice_banner.dart';
import 'package:admin_fmart/features/orders/presentation/substitution_sheets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

Map<String, dynamic> _line(int id) => {
      'id': id,
      'product_id': 66000 + id,
      'qty': 1,
      'price': '1775.00',
      'total': '1775.00',
      'product': {'name': 'Яйцо Аймар 30шт $id', 'sku': '4870', 'image_url': null, 'in_stock': true, 'on_sale': false},
      'stock_check': {'level': 'check', 'reasons': <String>[]},
    };

FakeOrdersRepository _repo(String? choice) {
  final json = weighedOrderJson(items: [_line(1), _line(2)]);
  if (choice != null) json['missing_item_choice'] = choice;
  return fakeRepo(json);
}

(OrdersRepository, List<RequestOptions>) _capturing(Map<String, dynamic> reply) {
  final sent = <RequestOptions>[];
  final api = ApiClient(baseUrl: 'http://localhost', tokenStorage: TokenStorage(), onUnauthorized: () {});
  api.dio.interceptors.insert(
    0,
    InterceptorsWrapper(onRequest: (o, h) {
      sent.add(o);
      h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: reply));
    }),
  );
  return (OrdersRepository(api: api), sent);
}

void main() {
  tearDown(() => AdminFeatureFlags.instance.set(const {}));
  weighedPickerTests();

  group('labels', () {
    test('three choices, none for older orders', () {
      expect(MissingItemChoice.label('call_then_replace'),
          'Позвонить. Если не дозвонитесь, заменить на похожий');
      expect(MissingItemChoice.label('replace'), 'Заменить на похожий без звонка');
      expect(MissingItemChoice.label('remove'), 'Не звонить и не заменять: убрать товар');
      expect(MissingItemChoice.label(null), isNull);
      expect(MissingItemChoice.label('something_new'), isNull);
    });
  });

  test('the order model reads it', () {
    final j = weighedOrderJson()..['missing_item_choice'] = 'replace';
    expect(Order.fromJson(j).missingItemChoice, 'replace');
    expect(Order.fromJson(weighedOrderJson()).missingItemChoice, isNull);
  });

  group('repository body', () {
    test('«Не дозвонился» sends customer_unreachable; a normal proposal does not', () async {
      final (repo, sent) = _capturing({'ok': true, 'substitution_id': 5, 'auto_accepted': true, 'status': 'accepted'});
      final r = await repo.proposeSubstitution(
          orderId: 1, itemId: 2, substituteProductId: 777, customerUnreachable: true);
      await repo.proposeSubstitution(orderId: 1, itemId: 2, substituteProductId: 777);
      expect((sent[0].data as Map)['customer_unreachable'], true);
      expect((sent[1].data as Map).containsKey('customer_unreachable'), isFalse);
      expect(r['auto_accepted'], true);
    });
  });

  group('on the order page', () {
    Future<void> pickMissing(WidgetTester t, int itemId) async {
      final menu = find.descendant(
        of: find.byKey(ValueKey(itemId)),
        matching: find.byKey(const ValueKey('stock-check-menu')),
      );
      await scrollTo(t, menu);
      await t.tap(menu);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Нет в наличии').last);
      await settle(t);
    }

    testWidgets('the choice is shown on the order', (t) async {
      final repo = _repo('call_then_replace');
      await pumpOrderPage(t, repo);
      expect(find.byKey(const ValueKey('missing-item-choice-banner')), findsOneWidget);
      expect(find.textContaining('Позвонить. Если не дозвонитесь'), findsOneWidget);
      await disposePage(t);
    });

    testWidgets('an older order shows no banner', (t) async {
      final repo = _repo(null);
      await pumpOrderPage(t, repo);
      expect(find.byKey(const ValueKey('missing-item-choice-banner')), findsNothing);
      await disposePage(t);
    });

    testWidgets('«Убрать товар»: «Нет в наличии» goes straight to removal, even with substitutions on',
        (t) async {
      AdminFeatureFlags.instance.set(const {'substitution': true});
      final repo = _repo('remove');
      await pumpOrderPage(t, repo);
      await pickMissing(t, 2);
      expect(find.text('Убрать товар из заказа?'), findsOneWidget);
      await t.tap(find.textContaining('Убрать и вернуть'));
      await settle(t);
      expect(repo.removeCalls, [2]);
      await disposePage(t);
    });
  });
}

class _SimilarRepo extends FakeOrdersRepository {
  _SimilarRepo({required super.api, required super.detail, required this.similar});
  final List<Map<String, dynamic>> similar;
  @override
  Future<List<SimilarProduct>> getSimilarProducts({
    required int storeId,
    required int productId,
    required double maxPrice,
  }) async =>
      similar.map(SimilarProduct.fromJson).toList();
}

Map<String, dynamic> _sim(int id, String name, num price, {String? sellBy, int? unitG, num? ppk}) => {
      'id': id, 'name': name, 'price': price, 'on_sale': false, 'in_stock': true,
      if (sellBy != null) 'sell_by': sellBy, if (unitG != null) 'unit_g': unitG, if (ppk != null) 'price_per_kg': ppk,
    };

final _mixed = [
  _sim(501, 'Сыр Дони весовой', 150, sellBy: 'weight', unitG: 50, ppk: 3000),        // ok
  _sim(502, 'Сыр кусками 100 г шаг', 150, sellBy: 'weight', unitG: 100, ppk: 1500),  // other step
  _sim(503, 'Сыр дороже за кг', 150, sellBy: 'weight', unitG: 50, ppk: 3200),        // dearer per kg
  _sim(504, 'Сыр нарезка 150 г', 140),                                               // piece
];

Future<void> _openPicker(WidgetTester t, Map<String, dynamic> line, List<Map<String, dynamic>> similar) async {
  t.view.physicalSize = const Size(1024, 1366);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  final json = weighedOrderJson(items: [line])..['missing_item_choice'] = 'replace';
  final base = fakeRepo(json);
  final repo = _SimilarRepo(api: base.api, detail: json, similar: similar);
  final order = Order.fromJson(json);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (c) => TextButton(
          onPressed: () => showSubstitutePickerSheet(c, repo: repo, order: order, item: order.items.first),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await settle(t);
}

void weighedPickerTests() {
  group('weighed lines in the picker (Ilhan 31.10)', () {
    testWidgets('a cheese line offers only weighed, same step, same-or-cheaper per kg, priced per kg',
        (t) async {
      await _openPicker(t, cheeseLine(), _mixed);
      expect(find.text('Сыр Дони весовой'), findsOneWidget);
      expect(find.text('Сыр кусками 100 г шаг'), findsNothing);
      expect(find.text('Сыр дороже за кг'), findsNothing);
      expect(find.text('Сыр нарезка 150 г'), findsNothing);
      expect(find.textContaining('300 г'), findsWidgets);
      expect(find.textContaining('/кг'), findsWidgets);
      await t.tap(find.text('Сыр Дони весовой'));
      await settle(t);
      await t.tap(find.text('Заменить сразу'));
      await t.pump();
      // (155 − 150) × 6 + (46 − floor(46 × 150 / 155) = 44) = 32, as order-service.
      expect(find.textContaining('вернём 32'), findsWidgets);
    });

    testWidgets('a piece line never offers a weighed product', (t) async {
      final piece = {
        'id': 9, 'product_id': 66009, 'qty': 1, 'price': '1775.00', 'total': '1775.00',
        'product': {'name': 'Яйцо Аймар 30шт', 'in_stock': true},
      };
      await _openPicker(t, piece, _mixed);
      expect(find.text('Сыр нарезка 150 г'), findsOneWidget);
      expect(find.text('Сыр Дони весовой'), findsNothing);
    });
  });

  test('similar products are asked weight-aware (X-App-Build)', () async {
    final (repo, sent) = _capturing(const {});
    sent.clear();
    final api = ApiClient(baseUrl: 'http://localhost', tokenStorage: TokenStorage(), onUnauthorized: () {});
    final seen = <RequestOptions>[];
    api.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      seen.add(o);
      h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: const []));
    }));
    await OrdersRepository(api: api).getSimilarProducts(storeId: 3, productId: 47, maxPrice: 155);
    expect(seen.single.headers['X-App-Build'], '9999');
    expect(repo, isNotNull);
  });
}
