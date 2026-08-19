import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';

/// The store's overdue cue. Kiril confirmed the process on 2026-08-17: at hour
/// 25 the старший кассир phones the customer and cancels only if they cannot be
/// reached. So `isPickupOverdue` drives a prompt, never a block, and the tests
/// below pin both halves of that.

// 'ready-for-delivery' with HYPHENS is the real value: verified against prod's
// order_statuses table (id=8), and it is what OrderStatus.READY_FOR_DELIVERY
// resolves to. The underscore form matches nothing and silently produces an
// order with no handover step.
Map<String, dynamic> _orderJson({String? pickupHoldUntil, String status = 'ready-for-delivery'}) => {
      'id': 1,
      'customer_id': 2,
      'status': status,
      'total_amount': '1000',
      'delivery_sum': '0',
      'store_id': 3,
      'store_name': 'F-Mart Фиркан Сити',
      'delivery_address': 'просп. Тауке хана 330',
      'fulfillment_type': 'pickup',
      'customer_comment': '',
      'payment_method': 'card',
      'is_promo': false,
      'created_at': '2026-08-17T06:00:00Z',
      'updated_at': '2026-08-17T06:00:00Z',
      if (pickupHoldUntil != null) 'pickup_hold_until': pickupHoldUntil,
      'items': <dynamic>[],
    };

void main() {
  group('pickup_hold_until parsing', () {
    test('absent field leaves the deadline null and nothing is overdue', () {
      final o = Order.fromJson(_orderJson());
      expect(o.pickupHoldUntil, isNull);
      expect(o.isPickupOverdue, isFalse);
    });

    test('a delivery order from an older backend is never overdue', () {
      final j = _orderJson()..['fulfillment_type'] = 'delivery';
      final o = Order.fromJson(j);
      expect(o.pickupHoldUntil, isNull);
      expect(o.isPickupOverdue, isFalse);
    });

    test('an unparseable value does not throw and does not fake a deadline', () {
      final o = Order.fromJson(_orderJson(pickupHoldUntil: 'not-a-date'));
      expect(o.pickupHoldUntil, isNull);
      expect(o.isPickupOverdue, isFalse);
    });

    test('an explicit null is tolerated', () {
      final j = _orderJson()..['pickup_hold_until'] = null;
      final o = Order.fromJson(j);
      expect(o.pickupHoldUntil, isNull);
      expect(o.isPickupOverdue, isFalse);
    });
  });

  group('isPickupOverdue', () {
    test('a deadline in the future is not overdue', () {
      final future = DateTime.now().toUtc().add(const Duration(hours: 5));
      final o = Order.fromJson(_orderJson(pickupHoldUntil: future.toIso8601String()));
      expect(o.pickupHoldUntil, isNotNull);
      expect(o.isPickupOverdue, isFalse);
    });

    test('a deadline in the past is overdue', () {
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      final o = Order.fromJson(_orderJson(pickupHoldUntil: past.toIso8601String()));
      expect(o.isPickupOverdue, isTrue);
    });

    test('a UTC deadline is compared as an instant, not as wall-clock text', () {
      // Shymkent is UTC+5. A deadline 1 hour ago in UTC is still 1 hour ago
      // locally; naive field-by-field comparison would read it as 4 hours
      // AHEAD and quietly hide every overdue order in the store.
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final o = Order.fromJson(_orderJson(pickupHoldUntil: past.toIso8601String()));
      expect(o.pickupHoldUntil!.isUtc, isTrue);
      expect(o.isPickupOverdue, isTrue);
    });
  });

  group('overdue must never block the handover', () {
    test('an overdue order still offers a handover step', () {
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      final o = Order.fromJson(_orderJson(pickupHoldUntil: past.toIso8601String()));
      // The customer who turns up on hour 25 must still get their bag: the
      // store cancels only after failing to reach them.
      expect(o.isPickupOverdue, isTrue);
      expect(pickupHandoverStep(o), isNotNull);
      expect(pickupHandoverStep(o)!.toStatus, 'completed');
      expect(pickupHandoverBlockedReason(o), isNull);
    });

    test('an overdue PARTIALLY-REFUNDED order still offers a handover', () {
      // Not an edge case on pickup: roughly a tenth of orders at this store
      // lose a line to phantom stock, so an overdue bag has often already been
      // partially refunded. Both conditions at once must still hand over.
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final o = Order.fromJson(_orderJson(
        pickupHoldUntil: past.toIso8601String(),
        status: 'partially-refunded',
      ));
      expect(o.isPickupOverdue, isTrue);
      expect(pickupHandoverStep(o), isNotNull);
      expect(pickupHandoverStep(o)!.toStatus, 'completed');
    });
  });

  group('a local status change must stop the overdue prompt', () {
    // This is the one that bites. `pickupHoldUntil` is server-derived and
    // computed CONDITIONALLY on status, but the app mutates status locally and
    // optimistically, and copyWith carries the deadline through unconditionally
    // (it is not even a copyWith parameter). The detail page hides the problem,
    // because its 8s poll overwrites from server truth. THE LIST HAS NO TIMER,
    // so the order popped back to it keeps the stale field and the row tells the
    // cashier to phone a customer who already walked out with their bag.
    final past = DateTime.now().toUtc().subtract(const Duration(hours: 2));

    Order overdueOrder() =>
        Order.fromJson(_orderJson(pickupHoldUntil: past.toIso8601String()));

    test('copyWith still carries the field itself', () {
      final o = overdueOrder();
      expect(o.copyWith(status: 'ready-for-delivery').pickupHoldUntil,
          equals(o.pickupHoldUntil),
          reason: 'the field is not dropped; the GETTER is what gates it');
    });

    test('handing over stops it being overdue', () {
      final o = overdueOrder();
      expect(o.isPickupOverdue, isTrue);
      expect(o.copyWith(status: 'completed').isPickupOverdue, isFalse,
          reason: 'a bag just handed over must not say «Позвоните клиенту»');
    });

    test('cancelling stops it being overdue', () {
      // The detail page falls back to copyWith(status: 'canceled') when the
      // post-cancel refetch fails, which on Shymkent 3G is common.
      expect(overdueOrder().copyWith(status: 'canceled').isPickupOverdue, isFalse);
    });

    test('refunding stops it being overdue', () {
      expect(overdueOrder().copyWith(status: 'refunded').isPickupOverdue, isFalse);
    });

    test('the two hold statuses still report overdue', () {
      for (final s in ['ready-for-delivery', 'partially-refunded']) {
        expect(overdueOrder().copyWith(status: s).isPickupOverdue, isTrue,
            reason: '$s is a genuine hold status and must stay actionable');
      }
    });

    test('a pre-counter status never reports overdue', () {
      for (final s in ['paid', 'processing', 'scheduled']) {
        expect(overdueOrder().copyWith(status: s).isPickupOverdue, isFalse);
      }
    });
  });
}
