import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';

/// The settle response, and what the operator is told about it.
///
/// Three of these four states are ways to say the wrong thing about money:
/// presenting a repeat as a fresh refund, presenting a refused ledger row as
/// success, or reporting a refund that was never published.
void main() {
  Map<String, dynamic> settle({
    Object? weightLines = 1,
    Object? due = 120.0,
    Object? already = 0.0,
    Object? refund = 120.0,
    Object? published = true,
  }) =>
      <String, dynamic>{
        'ok': true,
        'order_id': 55,
        'weight_lines': weightLines,
        'due': due,
        'already_settled': already,
        'refund_amount': refund,
        'refund_published': published,
        'lines': [
          {
            'item_id': 7,
            'product_id': 42,
            'ordered_g': 300,
            'actual_g': 280,
            'charged_g_cap': 330,
            'refund': 62.0,
          },
        ],
      };

  /// Mirrors _showSettleOutcome in order_details_page.
  String outcome(WeightSettleResult r) {
    if (r.wasAlreadySettled && r.refundAmount <= 0.005) {
      return 'already:${r.alreadySettled}';
    }
    if (r.refundAmount > 0.005 && r.refundPublished) {
      return 'refund:${r.refundAmount}';
    }
    if (r.due > 0.005 && !r.refundPublished) {
      return 'escalate:${r.due}';
    }
    return 'nothing';
  }

  group('parsing', () {
    test('reads the refund and the line breakdown', () {
      final r = WeightSettleResult.fromJson(settle());
      expect(r.orderId, 55);
      expect(r.weightLines, 1);
      expect(r.refundAmount, 120.0);
      expect(r.refundPublished, isTrue);
      expect(r.lines, hasLength(1));
      expect(r.lines.first.actualG, 280);
      expect(r.lines.first.refund, 62.0);
    });

    test('missing keys do not throw', () {
      final r = WeightSettleResult.fromJson({'ok': true});
      expect(r.orderId, 0);
      expect(r.refundAmount, 0);
      expect(r.lines, isEmpty);
      expect(r.refundPublished, isFalse);
    });

    test('a null lines list is an empty list, not a crash', () {
      final r = WeightSettleResult.fromJson({'lines': null});
      expect(r.lines, isEmpty);
    });
  });

  group('what the operator is told', () {
    test('a fresh refund says what will go back', () {
      expect(outcome(WeightSettleResult.fromJson(settle())), 'refund:120.0');
    });

    test('🔴 a REPEAT is reported as already settled, never as a new refund',
        () {
      // The server refunds nothing new on a second call and reports the earlier
      // figure in already_settled. Showing that as a fresh refund would tell
      // the operator money left the till twice.
      final r = WeightSettleResult.fromJson(
          settle(already: 120.0, refund: 0.0, published: false));
      expect(outcome(r), 'already:120.0');
    });

    test('🔴 a refused ledger row escalates rather than reading as success',
        () {
      // refund_published false with money due means the ledger already holds
      // this key and the customer is owed the difference. The server logs this
      // as money owed, so the operator must not be shown a silent success.
      final r = WeightSettleResult.fromJson(
          settle(refund: 0.0, published: false, due: 120.0));
      expect(outcome(r), 'escalate:120.0');
    });

    test('nothing owed is reported plainly', () {
      final r = WeightSettleResult.fromJson(
          settle(due: 0.0, refund: 0.0, published: false));
      expect(outcome(r), 'nothing');
    });

    test('a repeat flag with no stored amount still reads as nothing owed', () {
      // wasAlreadySettled keys off already_settled > 0.005.
      final r = WeightSettleResult.fromJson(
          settle(already: 0.0, due: 0.0, refund: 0.0, published: false));
      expect(r.wasAlreadySettled, isFalse);
      expect(outcome(r), 'nothing');
    });
  });

  group('the weight PUT response', () {
    test('carries the line preview the hint is built from', () {
      final r = OrderItemWeightResult.fromJson({
        'ok': true,
        'order_id': 55,
        'item_id': 7,
        'actual_g': 314,
        'ordered_g': 300,
        'charged_g_cap': 330,
        'weighed_at': '2026-10-04T10:00:00Z',
        'refund_preview': 0.0,
      });
      expect(r.actualG, 314);
      expect(r.orderedG, 300);
      expect(r.chargedGCap, 330);
      expect(r.refundPreview, 0.0);
      expect(r.weighedAt, isNotNull);
    });

    test('an over-order reading still carries a positive preview', () {
      // 314 g on a 300 g order: inside the 330 g cap, so the customer already
      // paid for the buffer and gets the difference back.
      final r = OrderItemWeightResult.fromJson({
        'item_id': 7,
        'actual_g': 314,
        'ordered_g': 300,
        'charged_g_cap': 330,
        'refund_preview': 16.0,
      });
      expect(r.refundPreview, 16.0);
    });
  });
}
