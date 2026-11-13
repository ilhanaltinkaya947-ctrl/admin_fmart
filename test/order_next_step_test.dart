import 'package:admin_fmart/core/services/order_watcher.dart' show OpenOrderScreens;
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Store app 1.3.0 S1: one big next-step button per order state.
Order _o(String status, {String fulfillment = 'delivery', bool pendingSub = false}) => Order.fromJson({
      'id': 100090,
      'customer_id': 2,
      'status': status,
      'total_amount': '8690',
      'delivery_sum': '0',
      'store_id': 3,
      'store_name': 'F-Mart Фиркан Сити',
      'delivery_address': 'ул. Тест 1',
      'fulfillment_type': fulfillment,
      'customer_comment': '',
      'payment_method': 'epay',
      'is_promo': false,
      'created_at': '2026-11-13T06:00:00Z',
      'updated_at': '2026-11-13T06:00:00Z',
      'items': <dynamic>[],
      'has_pending_substitution': pendingSub,
    });

void main() {
  test('paid: «Принять заказ», no confirmation, for delivery and pickup', () {
    for (final f in ['delivery', 'pickup']) {
      final s = orderNextStep(_o('paid', fulfillment: f))!;
      expect((s.toStatus, s.label, s.confirmTitle), ('processing', 'Принять заказ', ''));
    }
  });

  test('delivery being picked: «Заказ собран, вызвать курьера», confirmed (it books a courier)', () {
    final s = orderNextStep(_o('processing'))!;
    expect(s.toStatus, 'ready-for-delivery');
    expect(s.label, 'Заказ собран, вызвать курьера');
    expect(s.confirmTitle, 'Вызвать курьера?');
    expect(s.successText, 'Курьер вызывается');
  });

  test('pickup keeps exactly its own steps', () {
    for (final st in ['processing', 'ready-for-delivery', 'partially-refunded', 'completed', 'canceled']) {
      final mine = orderNextStep(_o(st, fulfillment: 'pickup'));
      final old = pickupHandoverStep(_o(st, fulfillment: 'pickup'));
      expect(mine?.toStatus, old?.toStatus, reason: st);
      expect(mine?.label, old?.label, reason: st);
    }
  });

  test('no button where the store has nothing to do or the courier owns it', () {
    for (final st in ['pending-payment', 'scheduled', 'ready-for-delivery', 'delivering', 'completed',
        'canceled', 'refunded', 'payment-failed']) {
      expect(orderNextStep(_o(st)), isNull, reason: st);
    }
  });

  test('an open replacement freezes the courier step and says why', () {
    final o = _o('processing', pendingSub: true);
    expect(orderNextStep(o), isNull);
    expect(orderStepBlockedReason(o), contains('Вызвать курьера можно будет после ответа'));
    expect(orderNextStep(o, ignoreOpenSubstitution: true)?.label, 'Заказ собран, вызвать курьера');
    expect(orderStepBlockedReason(_o('processing')), isNull);
  });

  test('critic round 2: no forward step while weighed lines are unweighed', () {
    Order weighed(String st, String f, {int? actualG}) => Order.fromJson({
          'id': 1, 'customer_id': 2, 'status': st, 'total_amount': '2369', 'delivery_sum': '0',
          'store_id': 3, 'store_name': 'X', 'delivery_address': '', 'fulfillment_type': f,
          'customer_comment': '', 'payment_method': 'epay', 'is_promo': false,
          'created_at': '2026-11-13T06:00:00Z', 'updated_at': '2026-11-13T06:00:00Z',
          'items': [
            {'id': 1, 'product_id': 101, 'qty': 6, 'price': '359', 'total': '2369', 'uom': 'кг',
             'unit_g': 50, 'price_per_kg': '7185', 'ordered_g': 300, 'charged_g_cap': 330,
             'buffer_amount': '215', if (actualG != null) 'actual_g': actualG},
          ],
        });
    expect(orderStepBlockedReason(weighed('processing', 'delivery')), contains('потом вызывайте курьера'));
    expect(orderStepBlockedReason(weighed('processing', 'pickup')), contains('потом нажмите «Заказ собран»'));
    expect(orderStepBlockedReason(weighed('processing', 'delivery', actualG: 287)), isNull);
    expect(orderStepBlockedReason(weighed('paid', 'delivery')), isNull, reason: 'accepting is never blocked');
  });

  test('the same order open twice stays "open" until both close', () {
    final s = OpenOrderScreens()..add(7)..add(7);
    s.remove(7);
    expect(s.contains(7), isTrue);
    s.remove(7);
    expect(s.contains(7), isFalse);
    s.remove(7); // an extra close never goes negative
    s.add(7);
    expect(s.contains(7), isTrue);
  });
}
