// «Проверьте наличие ▾» (26.10): the dropdown on every order line.
//
// Pins the three things a picker relies on: the chip says what the server
// knows, «В наличии» / «Сбросить ответ» send the right body (and come back
// when the server refuses), and «Нет в наличии» is the out-of-stock removal,
// never a bare POST. A line without a verdict (older server) keeps the old
// badge and nothing else.
import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/storage/token_storage.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/widgets/order_item_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weight_page_harness.dart';

Map<String, dynamic> _line({int id = 8423, bool inStock = true, Object? check}) => {
      'id': id,
      'product_id': 66000 + id,
      'qty': 1,
      'price': '1775.00',
      'total': '1775.00',
      'product': {'name': 'Яйцо Аймар 30шт $id', 'sku': '4870', 'image_url': null, 'in_stock': inStock, 'on_sale': false},
      if (check != null) 'stock_check': check,
    };

Future<void> _pumpCard(WidgetTester t, OrderItem item,
        {ValueChanged<StockAnswer>? onAnswer, bool canMarkMissing = true}) =>
    t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OrderItemCard(
            item: item,
            onStockAnswer: onAnswer,
            canMarkMissing: canMarkMissing,
          ),
        ),
      ),
    ));

/// Records what the page sends; the server state lives in [detail].
class _StockRepo extends FakeOrdersRepository {
  _StockRepo({required super.api, required super.detail});

  final List<(int, bool?)> answers = [];
  final List<bool> removeOutOfStock = [];
  Object? answerError;

  @override
  Future<StockCheck?> setItemStockAnswer({
    required int orderId,
    required int itemId,
    required bool? present,
  }) async {
    answers.add((itemId, present));
    final e = answerError;
    if (e != null) throw e;
    for (final it in (detail['items'] as List).cast<Map<String, dynamic>>()) {
      if (it['id'] == itemId) {
        it['stock_check'] = present == true
            ? {'level': 'confirmed', 'reasons': (it['stock_check'] as Map)['reasons']}
            : {'level': 'check', 'reasons': (it['stock_check'] as Map)['reasons']};
      }
    }
    return present == true ? const StockCheck(level: 'confirmed') : null;
  }

  @override
  Future<OrderItemEditResult> removeItem({
    required int orderId,
    required int itemId,
    bool outOfStock = false,
  }) {
    removeOutOfStock.add(outOfStock);
    return super.removeItem(orderId: orderId, itemId: itemId, outOfStock: outOfStock);
  }
}

_StockRepo _repo({String status = 'processing'}) {
  final base = fakeRepo(weighedOrderJson(status: status, items: [
    _line(id: 1, check: {'level': 'check', 'reasons': ['в 1С было 1 шт']}),
    _line(id: 2, check: {'level': 'ok', 'reasons': []}),
  ]));
  return _StockRepo(api: base.api, detail: base.detail);
}

/// A repository whose transport captures the request and answers [reply].
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
  group('the chip says what the server knows', () {
    testWidgets('unanswered: orange «Проверьте наличие» and the ⚠ reasons', (t) async {
      await _pumpCard(t, OrderItem.fromJson(_line(check: {'level': 'check', 'reasons': ['в 1С было 1 шт', 'своё производство: проверьте выпуск']})),
          onAnswer: (_) {});
      expect(find.byKey(const ValueKey('stock-check-Проверьте наличие')), findsOneWidget);
      expect(find.text('⚠ в 1С было 1 шт · своё производство: проверьте выпуск'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets('ok is unanswered too, with no hint when there are no reasons', (t) async {
      await _pumpCard(t, OrderItem.fromJson(_line(check: {'level': 'ok', 'reasons': []})), onAnswer: (_) {});
      expect(find.text('Проверьте наличие'), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-check-reasons')), findsNothing);
    });

    testWidgets('confirmed: green «В наличии», reasons hidden', (t) async {
      await _pumpCard(t, OrderItem.fromJson(_line(check: {'level': 'confirmed', 'reasons': ['в 1С было 1 шт']})),
          onAnswer: (_) {});
      expect(find.byKey(const ValueKey('stock-check-В наличии')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-check-reasons')), findsNothing);
    });

    testWidgets('missing: red «Нет в наличии», read-only', (t) async {
      await _pumpCard(t, OrderItem.fromJson(_line(check: {'level': 'missing', 'reasons': []})), onAnswer: (_) {});
      expect(find.byKey(const ValueKey('stock-check-Нет в наличии')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-check-menu')), findsNothing);
    });

    testWidgets('past picking (no callback): the verdict, no menu', (t) async {
      await _pumpCard(t, OrderItem.fromJson(_line(check: {'level': 'check', 'reasons': []})));
      expect(find.text('Проверьте наличие'), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-check-menu')), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });
  });

  group('the menu', () {
    testWidgets('unanswered offers «В наличии» and «Нет в наличии»', (t) async {
      final got = <StockAnswer>[];
      await _pumpCard(t, OrderItem.fromJson(_line(check: {'level': 'check', 'reasons': []})), onAnswer: got.add);
      await t.tap(find.byKey(const ValueKey('stock-check-menu')));
      await t.pumpAndSettle();
      expect(find.text('Сбросить ответ'), findsNothing);
      await t.tap(find.text('В наличии').last);
      await t.pumpAndSettle();
      expect(got, [StockAnswer.present]);
    });

    testWidgets('answered offers «Сбросить ответ», not «В наличии» again', (t) async {
      final got = <StockAnswer>[];
      await _pumpCard(t, OrderItem.fromJson(_line(check: {'level': 'confirmed', 'reasons': []})), onAnswer: got.add);
      await t.tap(find.byKey(const ValueKey('stock-check-menu')));
      await t.pumpAndSettle();
      expect(find.text('Нет в наличии'), findsOneWidget);
      await t.tap(find.text('Сбросить ответ'));
      await t.pumpAndSettle();
      expect(got, [StockAnswer.reset]);
    });

    testWidgets('an open substitution hides «Нет в наличии»', (t) async {
      await _pumpCard(t, OrderItem.fromJson(_line(check: {'level': 'check', 'reasons': []})),
          onAnswer: (_) {}, canMarkMissing: false);
      await t.tap(find.byKey(const ValueKey('stock-check-menu')));
      await t.pumpAndSettle();
      expect(find.text('Нет в наличии'), findsNothing);
      expect(find.text('В наличии'), findsWidgets);
    });
  });

  testWidgets('older server (no stock_check): the old yes/no badge, no dropdown', (t) async {
    await _pumpCard(t, OrderItem.fromJson(_line(inStock: false)), onAnswer: (_) {});
    expect(find.byKey(const ValueKey('stock-badge-Нет')), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-check-menu')), findsNothing);
    await _pumpCard(t, OrderItem.fromJson(_line(inStock: true)), onAnswer: (_) {});
    expect(find.byKey(const ValueKey('stock-badge-В наличии')), findsOneWidget);
  });

  group('repository bodies', () {
    test('«В наличии» posts present: true and reads the verdict', () async {
      final (repo, sent) = _capturing({'ok': true, 'stock_check': {'level': 'confirmed', 'confirmed_at': null}});
      final c = await repo.setItemStockAnswer(orderId: 1382, itemId: 8423, present: true);
      expect(sent.single.method, 'POST');
      expect(sent.single.path, '/gw/order/admin/orders/1382/items/8423/stock-answer');
      expect(sent.single.data, {'present': true});
      expect(c?.confirmed, isTrue);
    });

    test('«Сбросить ответ» posts present: null and reads null', () async {
      final (repo, sent) = _capturing({'ok': true, 'stock_check': null});
      final c = await repo.setItemStockAnswer(orderId: 1382, itemId: 8423, present: null);
      expect(sent.single.data, {'present': null});
      expect((sent.single.data as Map).containsKey('present'), isTrue);
      expect(c, isNull);
    });

    test('an out-of-stock removal says so; any other removal does not', () async {
      final reply = {'ok': true, 'order_id': 1, 'item_id': 2, 'removed': true, 'total_amount': 0};
      final (repo, sent) = _capturing(reply);
      await repo.removeItem(orderId: 1, itemId: 2, outOfStock: true);
      await repo.removeItem(orderId: 1, itemId: 2);
      expect(sent[0].method, 'DELETE');
      expect(sent[0].queryParameters, {'out_of_stock': true});
      expect(sent[1].queryParameters, isEmpty);
    });
  });

  group('on the order page', () {
    Future<void> openMenu(WidgetTester t, int itemId) async {
      final menu = find.descendant(
        of: find.byKey(ValueKey(itemId)),
        matching: find.byKey(const ValueKey('stock-check-menu')),
      );
      await scrollTo(t, menu);
      await t.tap(menu);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('«В наличии» sends present: true and the chip turns green', (t) async {
      final repo = _repo();
      await pumpOrderPage(t, repo);
      await openMenu(t, 1);
      await t.tap(find.text('В наличии').last);
      await settle(t);
      expect(repo.answers, [(1, true)]);
      expect(find.byKey(const ValueKey('stock-check-В наличии')), findsOneWidget);
      await disposePage(t);
    });

    testWidgets('a refused answer comes back and says so', (t) async {
      final repo = _repo()..answerError = Exception('502');
      await pumpOrderPage(t, repo);
      await openMenu(t, 1);
      await t.tap(find.text('В наличии').last);
      await settle(t);
      expect(repo.answers, [(1, true)]);
      expect(find.text('Не удалось сохранить ответ'), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-check-В наличии')), findsNothing);
      expect(find.byKey(const ValueKey('stock-check-Проверьте наличие')), findsNWidgets(2));
      await disposePage(t);
    });

    testWidgets('«Нет в наличии» is the out-of-stock removal, with its confirmation', (t) async {
      final repo = _repo();
      await pumpOrderPage(t, repo);
      await openMenu(t, 2);
      await t.tap(find.text('Нет в наличии').last);
      await settle(t);
      // No POST: the «нет» is the hold the removal places.
      expect(repo.answers, isEmpty);
      expect(find.text('Убрать товар из заказа?'), findsOneWidget);
      expect(find.textContaining('Товар скроем у покупателей'), findsOneWidget);
      await t.tap(find.textContaining('Убрать и вернуть'));
      await settle(t);
      expect(repo.removeCalls, [2]);
      expect(repo.removeOutOfStock, [true]);
      await disposePage(t);
    });

    testWidgets('a settled-status order shows the verdict read-only', (t) async {
      final repo = _repo(status: 'delivering');
      await pumpOrderPage(t, repo);
      expect(find.byKey(const ValueKey('stock-check-menu')), findsNothing);
      expect(find.text('Проверьте наличие'), findsNWidgets(2));
      await disposePage(t);
    });
  });
}
