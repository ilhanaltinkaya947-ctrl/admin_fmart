// The refund modal used to print whatever the backend put in `message`
// straight into a SnackBar. That was harmless while the field was always
// empty; it stopped being harmless the moment order-service started answering
// `refund_performed` / `refund_queued`, because the operator would have been
// shown those words verbatim.
//
// It also used to say «Возврат оформлен» for every non-throwing outcome,
// including the ones where no money moved at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';

SimpleActionResponse res(bool success, String message) =>
    SimpleActionResponse(success: success, message: message);

void main() {
  group('refundOutcomeMessage', () {
    test('never leaks a backend token to the operator', () {
      // Including codes that do not exist yet: the rule is a shape test, not a
      // list, because order-service will add reasons without thinking about
      // this SnackBar.
      const tokens = [
        'refund_performed',
        'refund_queued',
        'no_captured_tx',
        'exceeds_captured',
        'some_future_code',
      ];
      for (final m in tokens) {
        for (final ok in const [true, false]) {
          final out = refundOutcomeMessage(res(ok, m));
          expect(out, isNot(equals(m)),
              reason: 'raw backend token "$m" reached the SnackBar: $out');
          expect(RegExp(r'^[a-z0-9_]+$').hasMatch(out), isFalse,
              reason: 'SnackBar shows an identifier, not a sentence: $out');
        }
      }
    });

    test('a genuine human message from the backend is still shown', () {
      expect(refundOutcomeMessage(res(false, 'Заказ уже изменился')),
          'Заказ уже изменился');
    });

    test('says the money moved only when it actually did', () {
      expect(refundOutcomeMessage(res(true, 'refund_performed')),
          'Возврат выполнен, банк вернул деньги');
    });

    test('a queued refund is not reported as completed', () {
      final out = refundOutcomeMessage(res(true, 'refund_queued'));
      expect(out.contains('выполнен'), isFalse,
          reason: 'a refund we could not confirm must not read as done: $out');
      expect(out.contains('подтвердил'), isTrue);
    });

    test('an older order-service with no message still reads sensibly', () {
      expect(refundOutcomeMessage(res(true, '')), 'Возврат оформлен');
    });

    test('a failure is never dressed up as a refund', () {
      expect(refundOutcomeMessage(res(false, '')), 'Не удалось оформить возврат');
      // The no-capture signal is success=false with a token message; it must
      // not be echoed either.
      final out = refundOutcomeMessage(res(false, 'no_captured_tx'));
      expect(out, 'Не удалось оформить возврат');
    });
  });

  group('refundRefusalMessage', () {
    test('every refusal states that the money did not move', () {
      const reasons = [
        'no_captured_tx',
        'exceeds_captured',
        'provider_refund_failed',
        'no_provider_payment_id',
        null,
      ];
      for (final r in reasons) {
        final out = refundRefusalMessage(r);
        expect(out.isNotEmpty, isTrue);
        // The operator's one question is "did the customer get their money?"
        final saysNo = out.contains('не выполнил') ||
            out.contains('не выполнен') ||
            out.contains('не вернулись') ||
            out.contains('возвращать нечего') ||
            out.contains('Проверьте историю');
        expect(saysNo, isTrue, reason: 'reason "$r" does not say what happened: $out');
      }
    });

    test('each known reason gets its own wording, not a generic one', () {
      final distinct = {
        refundRefusalMessage('no_captured_tx'),
        refundRefusalMessage('exceeds_captured'),
        refundRefusalMessage('provider_refund_failed'),
        refundRefusalMessage('no_provider_payment_id'),
        refundRefusalMessage(null),
      };
      expect(distinct.length, 5);
    });

    test('an unrecognised reason still produces something safe', () {
      final out = refundRefusalMessage('some_future_reason');
      expect(out, 'Возврат не выполнен, деньги не вернулись клиенту.');
    });
  });
}
