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
}
