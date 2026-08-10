// Pins the DELIVERY dropdown as unchanged, and pins pickup's divergences.
//
// admin_fmart had no test suite. This is the first file, and it exists because
// this change edits the map that decides which buttons a manager can press on a
// paid order. Getting it wrong does not throw — it silently removes the only
// action that finishes an order, and leaves «Отменить» (a full refund) as the
// one thing that still works.
//
// The backend counterpart is order-service
// tests/test_fulfillment_presentation.py. The two must agree; where a value is
// duplicated across the boundary it is written out as a literal here so a drift
// shows up as a failing test rather than as a 409 in a manager's face.

import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';

const kAllStatuses = <String>[
  'pending-payment',
  'paid',
  'processing',
  'ready-for-delivery',
  'delivering',
  'completed',
  'canceled',
  'partially-refunded',
  'refunded',
  'payment-failed',
  'payment-timeout',
  'scheduled',
];

/// Statuses that mean the order did NOT succeed. A route to completion that has
/// to pass through one of these is not a happy path, it is a consolation prize.
const kUnhappy = <String>{
  'canceled',
  'refunded',
  'partially-refunded',
  'payment-failed',
};

Set<String> happyReachable(String fulfillment, {String start = 'paid'}) {
  final seen = <String>{start};
  final queue = <String>[start];
  while (queue.isNotEmpty) {
    final cur = queue.removeLast();
    for (final next
        in adminAllowedTransitions(cur, fulfillmentType: fulfillment)) {
      if (seen.contains(next) || kUnhappy.contains(next)) continue;
      seen.add(next);
      queue.add(next);
    }
  }
  return seen;
}

void main() {
  group('delivery is unchanged', () {
    // GOLDEN LITERALS, not a comparison against kAdminAllowedTransitions.
    //
    // The first version of this test asserted
    //   adminAllowedTransitions(s, 'delivery') == kAdminAllowedTransitions[s]
    // which is `f(M[s]) == M[s]` with f = identity: true for ANY M. It pinned
    // "the mask is the identity for delivery" and pinned NOTHING about the
    // legacy sets. Deleting 'canceled' from 'paid' — removing the manager's
    // ability to cancel a paid order, the most common delivery intervention —
    // passed all 22 tests green. Written out longhand so a delivery regression
    // has to survive a literal diff.
    const goldenDelivery = <String, Set<String>>{
      'pending-payment': {'paid', 'payment-failed', 'canceled'},
      'paid': {'processing', 'canceled'},
      'processing': {'ready-for-delivery', 'canceled'},
      'ready-for-delivery': {'delivering'},
      'delivering': {'completed'},
      'completed': <String>{},
      'payment-failed': {'canceled'},
      'payment-timeout': {'canceled'},
      'canceled': <String>{},
      'partially-refunded': {
        'processing',
        'ready-for-delivery',
        'delivering',
        'completed',
      },
      'refunded': <String>{},
      'scheduled': {'paid', 'canceled'},
    };

    test('every status returns exactly the legacy set', () {
      for (final status in kAllStatuses) {
        expect(
          adminAllowedTransitions(status, fulfillmentType: 'delivery'),
          equals(goldenDelivery[status]),
          reason: 'delivery transitions changed for $status',
        );
      }
    });

    test('the legacy map itself is unchanged', () {
      // Catches an edit to kAdminAllowedTransitions even if someone also
      // "fixes" the mask to compensate.
      expect(kAdminAllowedTransitions.keys.toSet(), goldenDelivery.keys.toSet());
      goldenDelivery.forEach((status, expected) {
        expect(kAdminAllowedTransitions[status], equals(expected),
            reason: 'legacy transition map edited for $status');
      });
    });

    test('the default argument is delivery', () {
      for (final status in kAllStatuses) {
        expect(
          adminAllowedTransitions(status),
          equals(adminAllowedTransitions(status, fulfillmentType: 'delivery')),
        );
      }
    });

    test('labels are unchanged', () {
      const golden = {
        'pending-payment': 'Ожидает оплату',
        'paid': 'Оплачен',
        'processing': 'В обработке',
        'ready-for-delivery': 'Готов к доставке',
        'delivering': 'В пути',
        'completed': 'Завершён',
        'canceled': 'Отменён',
        'refunded': 'Полный возврат',
        'partially-refunded': 'Частичный возврат',
        'payment-failed': 'Карта отклонена',
        'payment-timeout': 'Оплата не завершена',
        'scheduled': 'Запланирован на утро',
      };
      golden.forEach((code, expected) {
        expect(orderStatusRu(code), expected);
        expect(orderStatusRu(code, fulfillmentType: 'delivery'), expected);
      });
    });

    test('delivery still routes through the courier state', () {
      expect(
        adminAllowedTransitions('ready-for-delivery',
            fulfillmentType: 'delivery'),
        contains('delivering'),
      );
      expect(happyReachable('delivery'), contains('delivering'));
    });
  });

  group('pickup', () {
    test('THE BLOCKER: a collected order can be marked collected', () {
      // Before this change the shipped app offered only {'delivering'} here,
      // which the backend now rejects for pickup. The manager was left with
      // «Отменить» — a full refund for goods already handed over.
      expect(
        adminAllowedTransitions('ready-for-delivery',
            fulfillmentType: 'pickup'),
        contains('completed'),
      );
    });

    test('a courier state is never offered', () {
      expect(
        adminAllowedTransitions('ready-for-delivery',
            fulfillmentType: 'pickup'),
        isNot(contains('delivering')),
      );
      expect(
        adminAllowedTransitions('partially-refunded',
            fulfillmentType: 'pickup'),
        isNot(contains('delivering')),
      );
    });

    test('a paid order can be completed without a refund', () {
      // Deliberately phrased as "without a refund". "Reaches some terminal
      // state" is satisfied trivially by canceled/refunded always being
      // reachable, so it passes even when orders can never be fulfilled.
      expect(happyReachable('pickup'), contains('completed'));
      expect(happyReachable('pickup'), isNot(contains('delivering')));
    });

    test('no status on the happy path is a dead end', () {
      for (final fulfillment in ['delivery', 'pickup']) {
        for (final status in happyReachable(fulfillment)) {
          if (status == 'completed') continue;
          expect(
            happyReachable(fulfillment, start: status),
            contains('completed'),
            reason: '$fulfillment: $status is a dead end',
          );
        }
      }
    });

    test('labels differ only where they must', () {
      expect(orderStatusRu('ready-for-delivery', fulfillmentType: 'pickup'),
          'Готов к выдаче');
      expect(orderStatusRu('completed', fulfillmentType: 'pickup'), 'Выдан');
      // Shared, not duplicated.
      expect(orderStatusRu('paid', fulfillmentType: 'pickup'), 'Оплачен');
      expect(orderStatusRu('refunded', fulfillmentType: 'pickup'),
          'Полный возврат');
    });

    test('a pickup order parked in a courier state reads as an error', () {
      // Unreachable by policy. If some other door does it, the manager must not
      // read «В пути» and assume a courier is calmly doing their job.
      expect(orderStatusRu('delivering', fulfillmentType: 'pickup'),
          contains('Ошибка'));
    });

    test('no mask ever removes a refund edge', () {
      for (final fulfillment in ['delivery', 'pickup']) {
        for (final entry in kAdminAllowedTransitions.entries) {
          final masked =
              adminAllowedTransitions(entry.key, fulfillmentType: fulfillment);
          for (final refundEdge in ['refunded', 'partially-refunded']) {
            if (entry.value.contains(refundEdge)) {
              expect(masked, contains(refundEdge),
                  reason: '$fulfillment: ${entry.key} lost $refundEdge');
            }
          }
        }
      }
    });
  });

  group('fails safe toward delivery', () {
    test('anything not exactly pickup behaves as delivery', () {
      for (final garbage in ['', '  ', 'delivery', 'самовывоз', 'PICKUP_', 'x']) {
        expect(
          adminAllowedTransitions('ready-for-delivery',
              fulfillmentType: garbage),
          equals(kAdminAllowedTransitions['ready-for-delivery']),
          reason: 'garbage "$garbage" did not fall back to delivery',
        );
      }
    });

    test('pickup is matched case and space insensitively', () {
      for (final variant in ['pickup', 'PICKUP', ' Pickup ', 'PickUp']) {
        expect(
          adminAllowedTransitions('ready-for-delivery',
              fulfillmentType: variant),
          contains('completed'),
          reason: 'variant "$variant" was not recognised as pickup',
        );
      }
    });

    test('an unknown status denies everything, including the ALLOW half', () {
      for (final fulfillment in ['delivery', 'pickup']) {
        expect(
          adminAllowedTransitions('not-a-status',
              fulfillmentType: fulfillment),
          isEmpty,
        );
      }
    });

    test('status matching tolerates case and whitespace', () {
      expect(adminAllowedTransitions('  READY-FOR-DELIVERY  ',
          fulfillmentType: 'pickup'),
          contains('completed'));
    });
  });

  group('order parsing', () {
    Order parse(Map<String, dynamic> extra) => Order.fromJson({
          'id': 1,
          'status': 'ready-for-delivery',
          'store_id': 3,
          'store_name': 'F-Mart Фиркан Сити',
          'delivery_address': 'улица Фиркан, 12',
          'customer_comment': '',
          'payment_method': 'card',
          'is_promo': false,
          ...extra,
        });

    test('absent fulfillment_type is a delivery', () {
      expect(parse({}).fulfillmentType, 'delivery');
    });

    test('unrecognised values are a delivery, never a pickup', () {
      for (final v in [null, '', 'PICKUP_', 'самовывоз', 'courier', 123]) {
        expect(parse({'fulfillment_type': v}).fulfillmentType, 'delivery',
            reason: '$v should not have parsed as pickup');
      }
    });

    test('pickup is recognised', () {
      for (final v in ['pickup', 'PICKUP', ' Pickup ']) {
        expect(parse({'fulfillment_type': v}).fulfillmentType, 'pickup');
      }
    });
  });

  group('copyWith must not launder a pickup order into a delivery', () {
    Order pickupOrder() => Order.fromJson({
          'id': 4312,
          'customer_id': 9,
          'status': 'processing',
          'total_amount': '12620',
          'delivery_sum': '0',
          'store_id': 3,
          'store_name': 'F-Mart Фиркан Сити',
          'delivery_address': 'улица Фиркан, 12',
          'fulfillment_type': 'pickup',
          'customer_comment': '',
          'payment_method': 'card',
          'is_promo': false,
        });

    test('a status change preserves fulfillmentType', () {
      // This is `_order = _order.copyWith(status: …)` at
      // order_details_page.dart:457, i.e. the most common action in the flow.
      final after = pickupOrder().copyWith(status: 'ready-for-delivery');
      expect(after.fulfillmentType, 'pickup',
          reason: 'copyWith silently converted a pickup order to a delivery');
    });

    test('the laundered order would re-offer the courier transition', () {
      // Stated as consequence, not as a field check, so the reason this
      // matters survives someone refactoring the model.
      final after = pickupOrder().copyWith(status: 'ready-for-delivery');
      final allowed = adminAllowedTransitions(
        after.status,
        fulfillmentType: after.fulfillmentType,
      );
      expect(allowed, isNot(contains('delivering')));
      expect(allowed, contains('completed'));
    });

    test('every copyWith field survives a round trip', () {
      // Catches the NEXT field somebody forgets, not just this one.
      final before = pickupOrder();
      final after = before.copyWith();
      expect(after.id, before.id);
      expect(after.customerId, before.customerId);
      expect(after.status, before.status);
      expect(after.totalAmount, before.totalAmount);
      expect(after.deliverySum, before.deliverySum);
      expect(after.storeId, before.storeId);
      expect(after.storeName, before.storeName);
      expect(after.deliveryAddress, before.deliveryAddress);
      expect(after.fulfillmentType, before.fulfillmentType);
      expect(after.paymentMethod, before.paymentMethod);
      expect(after.isPromo, before.isPromo);
      expect(after.shippingLat, before.shippingLat);
      expect(after.shippingLng, before.shippingLng);
      // The remaining constructor fields. The first version of this test
      // claimed to "catch the NEXT field somebody forgets" while checking 13
      // of 21 — a promise it did not keep. All of these are carried correctly
      // today; they are asserted so that stays true.
      expect(after.customerComment, before.customerComment);
      expect(after.createdAt, before.createdAt);
      expect(after.updatedAt, before.updatedAt);
      expect(after.scheduledForAt, before.scheduledForAt);
      expect(after.bigBagCount, before.bigBagCount);
      expect(after.mediumBagCount, before.mediumBagCount);
      expect(after.packagingSum, before.packagingSum);
      expect(after.items, before.items);
      expect(after.substitutions, before.substitutions);
      expect(after.hasPendingSubstitution, before.hasPendingSubstitution);
      expect(after.pendingSubstitutionExpiresAt,
          before.pendingSubstitutionExpiresAt);
    });
  });

  group('orders list row', () {
    Order orderOf(String fulfillment, String status) => Order.fromJson({
          'id': 4312,
          'status': status,
          'total_amount': '12620',
          'delivery_sum': '0',
          'store_id': 3,
          'store_name': 'F-Mart Фиркан Сити',
          'delivery_address': 'улица Фиркан, 12',
          'fulfillment_type': fulfillment,
          'customer_comment': '',
          'payment_method': 'card',
          'is_promo': false,
        });

    test('a delivery row is unchanged at every status', () {
      for (final status in kAllStatuses) {
        final d = orderRowDisplay(orderOf('delivery', status));
        expect(d.showsCustomerAddress, isTrue);
        expect(d.showsDeliveryFee, isTrue);
        expect(d.showsPickupChip, isFalse);
      }
    });

    test('a pickup row never presents the store address as the customer\'s', () {
      // deliveryAddress holds OUR shop's address on a pickup order.
      for (final status in kAllStatuses) {
        expect(orderRowDisplay(orderOf('pickup', status)).showsCustomerAddress,
            isFalse,
            reason: 'pickup at $status showed the store address as the customer address');
      }
    });

    test('a pickup row never shows a delivery fee', () {
      // «дост: 0 ₸» under a total reads as a discount, not as "no delivery".
      for (final status in kAllStatuses) {
        expect(orderRowDisplay(orderOf('pickup', status)).showsDeliveryFee,
            isFalse);
      }
    });

    test('the pickup marker shows at EVERY status, not just when ready', () {
      // paid and processing are exactly when a picker triages the day's work,
      // which is when the two kinds of order most need telling apart.
      for (final status in kAllStatuses) {
        expect(orderRowDisplay(orderOf('pickup', status)).showsPickupChip,
            isTrue,
            reason: 'pickup order at $status had no marker in the list');
      }
      for (final status in ['paid', 'processing']) {
        final d = orderRowDisplay(orderOf('pickup', status));
        expect(d.showsPickupChip, isTrue);
        expect(d.showsCustomerAddress, isFalse);
      }
    });

    test('the row rule agrees with the transition and label rules', () {
      // All three key on the same concept. If they normalize differently, a raw
      // value sends the row down one branch and the dropdown down another.
      for (final raw in ['pickup', 'PICKUP', ' Pickup ', 'PickUp']) {
        final o = Order(
          id: 1,
          customerId: 1,
          status: 'ready-for-delivery',
          totalAmount: '1',
          deliverySum: '0',
          shippingLat: 0,
          shippingLng: 0,
          storeId: 3,
          storeName: 'S',
          deliveryAddress: 'A',
          fulfillmentType: raw,
          customerComment: '',
          paymentMethod: 'card',
          isPromo: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          items: const [],
        );
        expect(orderRowDisplay(o).showsPickupChip, isTrue,
            reason: 'row rule missed "$raw"');
        expect(
          adminAllowedTransitions(o.status, fulfillmentType: o.fulfillmentType),
          contains('completed'),
          reason: 'transition rule missed "$raw"',
        );
        expect(orderStatusRu(o.status, fulfillmentType: o.fulfillmentType),
            'Готов к выдаче',
            reason: 'label rule missed "$raw"');
      }
    });

    test('an unparseable fulfillment type renders as a delivery row', () {
      for (final v in [null, '', 'PICKUP_', 123, 'самовывоз']) {
        final o = Order.fromJson({
          'id': 1,
          'status': 'paid',
          'delivery_sum': '0',
          'delivery_address': 'ул. Х',
          'fulfillment_type': v,
          'customer_comment': '',
          'payment_method': 'card',
          'is_promo': false,
        });
        final d = orderRowDisplay(o);
        expect(d.showsPickupChip, isFalse, reason: '$v rendered as pickup');
        expect(d.showsCustomerAddress, isTrue);
        expect(d.showsDeliveryFee, isTrue);
      }
    });
  });

  group('pickup handover button', () {
    Order o(String fulfillment, String status, {bool openSub = false}) =>
        Order.fromJson({
          'id': 4312,
          'status': status,
          'delivery_sum': '0',
          'delivery_address': 'улица Фиркан, 12',
          'fulfillment_type': fulfillment,
          'customer_comment': '',
          'payment_method': 'card',
          'is_promo': false,
          'substitutions': openSub
              ? [
                  {
                    'id': 1,
                    'order_item_id': 5,
                    'status': 'proposed',
                    'original_product_id': 9,
                    'original_price': '100',
                  }
                ]
              : [],
        });

    test('delivery orders NEVER get the button, at any status', () {
      // The same shortcut would help delivery, but adding it there is an
      // unrequested change to the path 446 real orders travel.
      for (final status in kAllStatuses) {
        expect(pickupHandoverStep(o('delivery', status)), isNull,
            reason: 'delivery at $status offered a pickup handover button');
      }
    });

    test('processing offers «Заказ собран» with no confirmation', () {
      final step = pickupHandoverStep(o('pickup', 'processing'))!;
      expect(step.toStatus, 'ready-for-delivery');
      expect(step.label, 'Заказ собран');
      expect(step.confirmTitle, isEmpty); // forward progress, not terminal
      expect(step.successText, contains('4312'));
    });

    test('ready-for-delivery offers «Выдать заказ» AND demands confirmation', () {
      // Terminal, and it pushes «Заказ выдан» to the customer. It must not be
      // possible to do that with one stray tap.
      final step = pickupHandoverStep(o('pickup', 'ready-for-delivery'))!;
      expect(step.toStatus, 'completed');
      expect(step.label, 'Выдать заказ');
      expect(step.confirmTitle, isNotEmpty);
      expect(step.confirmBody, contains('уведомление'));
      expect(step.successText, contains('выдан'));
    });

    test('the two steps chain into a complete handover', () {
      final first = pickupHandoverStep(o('pickup', 'processing'))!;
      final second = pickupHandoverStep(o('pickup', first.toStatus))!;
      expect(second.toStatus, 'completed');
      // ...and both are transitions the backend will actually accept.
      expect(
        adminAllowedTransitions('processing', fulfillmentType: 'pickup'),
        contains(first.toStatus),
      );
      expect(
        adminAllowedTransitions(first.toStatus, fulfillmentType: 'pickup'),
        contains(second.toStatus),
      );
    });

    test('no button on statuses where it would be wrong', () {
      for (final status in [
        'pending-payment',
        'paid',
        'scheduled',
        'completed',
        'canceled',
        'refunded',
        'payment-failed',
        'payment-timeout',
        'delivering',
      ]) {
        expect(pickupHandoverStep(o('pickup', status)), isNull,
            reason: 'pickup at $status should offer no one-tap step');
      }
    });

    test('an open substitution removes the button', () {
      // The backend freezes the order until the customer answers. Offering the
      // button anyway would hand the manager a guaranteed 409.
      expect(pickupHandoverStep(o('pickup', 'processing', openSub: true)),
          isNull);
      expect(
          pickupHandoverStep(o('pickup', 'ready-for-delivery', openSub: true)),
          isNull);
      // ...and it comes back once resolved.
      expect(pickupHandoverStep(o('pickup', 'processing')), isNotNull);
    });

    test('every offered step is a transition the backend permits', () {
      // The button must never propose something that 409s.
      for (final status in kAllStatuses) {
        final step = pickupHandoverStep(o('pickup', status));
        if (step == null) continue;
        expect(
          adminAllowedTransitions(status, fulfillmentType: 'pickup'),
          contains(step.toStatus),
          reason: '$status -> ${step.toStatus} is offered but not allowed',
        );
      }
    });
  });

  group('DEPLOY COUPLING with the backend', () {
    // Verified against the RUNNING prod container on 2026-08-10:
    //   status_machine.py:14
    //   ADMIN_ALLOWED[READY_FOR_DELIVERY] = {DELIVERING, PARTIALLY_REFUNDED, REFUNDED}
    // There is no COMPLETED. The fulfillment-aware policy exists only on the
    // branch feat/pickup-fulfillment-aware and is NOT deployed.
    const deployedBackendAllowsAtReady = {
      'delivering',
      'partially-refunded',
      'refunded',
    };

    test('NEITHER side can ship alone: they must deploy together', () {
      final clientOffers = adminAllowedTransitions(
        'ready-for-delivery',
        fulfillmentType: 'pickup',
      );

      // This app offers `completed`, which the deployed backend rejects...
      expect(clientOffers, contains('completed'));
      expect(deployedBackendAllowsAtReady, isNot(contains('completed')));

      // ...and this app no longer offers `delivering`, which is the only thing
      // the deployed backend WOULD accept. So there is zero overlap: a pickup
      // order at «Готов к выдаче» has no working forward move, and the only
      // button left is Отменить, which refunds a customer who already
      // collected. Shipping the backend alone is the mirror image of the same
      // freeze.
      expect(clientOffers.intersection(deployedBackendAllowsAtReady), isEmpty,
          reason: 'If this now overlaps, the backend policy has shipped. '
              'Update deployedBackendAllowsAtReady from the running container '
              'and delete this test.');
    });

    test('the client mask matches the backend policy BRANCH, entry for entry', () {
      // fulfillment_policy.py on feat/pickup-fulfillment-aware:
      //   DENY  pickup: ready-for-delivery -> {delivering}
      //                 partially-refunded -> {delivering}
      //   ALLOW pickup: ready-for-delivery -> {completed}
      // Mirrored here. When these two drift, a manager gets a dropdown option
      // the backend answers with a 409, which reads to them as a broken app.
      expect(kFulfillmentTransitionDeny['pickup']?['ready-for-delivery'],
          equals({'delivering'}));
      expect(kFulfillmentTransitionDeny['pickup']?['partially-refunded'],
          equals({'delivering'}));
      expect(kFulfillmentTransitionAllow['pickup']?['ready-for-delivery'],
          equals({'completed'}));
      expect(kFulfillmentTransitionDeny['delivery'], isEmpty);
      expect(kFulfillmentTransitionAllow['delivery'], isEmpty);
    });
  });

  group('discrimination: proves these tests would have caught the bug', () {
    test('the OLD map is the frozen-order bug', () {
      // The shipped 1.1.7+47 behaviour, replayed.
      const shipped = kAdminAllowedTransitions;
      expect(shipped['ready-for-delivery'], equals({'delivering'}));

      // ...which the backend pickup policy rejects, leaving no overlap.
      final backendPickupAllows = adminAllowedTransitions(
        'ready-for-delivery',
        fulfillmentType: 'pickup',
      );
      expect(
        shipped['ready-for-delivery']!.intersection(backendPickupAllows),
        isEmpty,
        reason: 'the old map and the pickup policy share no legal move',
      );

      // The fix restores an overlap.
      expect(backendPickupAllows, isNotEmpty);
    });
  });
}
