import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/widgets/order_flag_chip.dart';

/// Store app 1.3.0 (S5-S7): the keys order-service 019851d / db189f1 send.
/// Display only — the server re-checks every move — so the rule here is:
/// read what is there, and a malformed value is UNKNOWN, never a crash.
Map<String, dynamic> _j([Map<String, dynamic> extra = const {}]) => {
      'id': 100090,
      'customer_id': 2,
      'status': 'scheduled',
      'total_amount': '8690',
      'delivery_sum': '0',
      'store_id': 5,
      'store_name': 'F-Mart Тулпар',
      'delivery_address': 'ул. Тест 1',
      'customer_comment': '',
      'payment_method': 'epay',
      'is_promo': false,
      'created_at': '2026-11-12T20:00:00Z',
      'updated_at': '2026-11-12T20:00:00Z',
      'items': <dynamic>[],
      ...extra,
    };

void main() {
  test('a 1.3.0 order reads every new key', () {
    final o = Order.fromJson(_j({
      'alcohol_class': 'strong',
      'release_at': '2026-11-13T07:00:00+00:00',
      'release_block_reason': 'В заказе алкоголь. По закону его можно выдать с 12:00. Заказ выпустится сам в 12:00.',
      'handover_block_reason': null,
      'possible_duplicate_of': 100088,
      'customer_first_name': 'Айгерим',
      'customer_phone_last4': '5678',
      'scheduled_reason': 'alcohol',
    }));
    expect(o.alcoholClass, 'strong');
    expect(o.hasAlcohol, isTrue);
    expect(o.releaseAt, DateTime.utc(2026, 11, 13, 7));
    expect(o.releaseBlockReason, startsWith('В заказе алкоголь'));
    expect(o.handoverBlockReason, isNull);
    expect(o.possibleDuplicateOf, 100088);
    expect((o.customerFirstName, o.customerPhoneLast4), ('Айгерим', '5678'));
    expect(o.scheduledReason, 'alcohol');
  });

  test('an order from today\'s server (no keys) is a plain order', () {
    final o = Order.fromJson(_j());
    expect(o.hasAlcohol, isFalse);
    expect(o.releaseBlockReason, isNull);
    expect(o.possibleDuplicateOf, isNull);
    expect(o.customerFirstName, isNull);
  });

  test('malformed values read as unknown, never throw', () {
    final o = Order.fromJson(_j({
      'alcohol_class': 7,
      'release_at': 'not a date',
      'release_block_reason': '   ',
      'possible_duplicate_of': '100088',
      'customer_first_name': ['x'],
      'customer_phone_last4': 5678,
      'scheduled_reason': false,
    }));
    expect(o.alcoholClass, isNull);
    expect(o.hasAlcohol, isFalse);
    expect(o.releaseAt, isNull);
    expect(o.releaseBlockReason, isNull, reason: 'blank is not a reason to block');
    expect(o.possibleDuplicateOf, isNull);
    expect(o.customerFirstName, isNull);
    expect(o.customerPhoneLast4, isNull);
    expect(o.scheduledReason, isNull);
  });

  test('"none" alcohol is no alcohol', () {
    expect(Order.fromJson(_j({'alcohol_class': 'none'})).hasAlcohol, isFalse);
    expect(Order.fromJson(_j({'alcohol_class': 'weak'})).hasAlcohol, isTrue);
  });

  test('an optimistic status edit keeps the server facts', () {
    final o = Order.fromJson(_j({
      'alcohol_class': 'weak',
      'release_block_reason': 'x',
      'handover_block_reason': 'y',
      'possible_duplicate_of': 1,
      'customer_first_name': 'А',
      'customer_phone_last4': '1234',
      'scheduled_reason': 'off_hours',
      'release_at': '2026-11-13T04:00:00Z',
    })).copyWith(status: 'paid');
    expect(o.status, 'paid');
    expect((o.alcoholClass, o.releaseBlockReason, o.handoverBlockReason, o.possibleDuplicateOf),
        ('weak', 'x', 'y', 1));
    expect((o.customerFirstName, o.customerPhoneLast4, o.scheduledReason), ('А', '1234', 'off_hours'));
    expect(o.releaseAt, DateTime.utc(2026, 11, 13, 4));
  });

  testWidgets('the chips say what they mean', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Wrap(children: [OrderFlagChip.alcohol(), OrderFlagChip.duplicate(100033)])),
    ));
    expect(find.text('Алкоголь'), findsOneWidget);
    expect(find.text('Похоже на повтор №100033'), findsOneWidget);
  });
}
