// The courier dispatch gate refuses an undeliverable order with a 409 and a
// Russian reason. Before this, the manager saw a flat «Не удалось создать
// заявку» and would just tap again — a retry that can never succeed.
//
// These pin the rule that decides whether a backend `detail` is fit to show
// an operator, because getting it wrong is silent in both directions: showing
// an internal English string looks like a crash, and hiding a real Russian
// reason puts us back where we started.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_fmart/core/api/api_errors.dart';

DioException _err(Object? body, {int status = 409}) {
  final req = RequestOptions(path: '/gw/delivery/claims/create');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: body),
  );
}

void main() {
  group('backendDetail — shows deliberate Russian rejections', () {
    test('the real courier gate 409 is surfaced verbatim', () {
      // Byte-for-byte the string delivery_service.py raises. If the backend
      // reworks its wording this test still passes (it is not asserting the
      // wording), but it documents exactly what the operator will read.
      const msg = 'Нельзя вызвать курьера: заказ не готов к доставке';
      expect(backendDetail(_err({'detail': msg})), msg);
    });

    test('surrounding whitespace is trimmed', () {
      expect(
        backendDetail(_err({'detail': '  Заказ не оплачен  '})),
        'Заказ не оплачен',
      );
    });

    test('any 4xx carries it — a Russian 400 is still shown', () {
      // Within 4xx the language is the discriminator, not the code: the same
      // 400 carries both useful Russian rejections and the useless English
      // catch-all.
      expect(
        backendDetail(_err({'detail': 'Заказ уже отменён'}, status: 400)),
        'Заказ уже отменён',
      );
    });
  });

  group('backendDetail — gateway 5xx noise never reaches the operator', () {
    // The gateway's OWN error details are Russian too, and interpolate a raw
    // exception. Language alone would let these through, which is why the
    // rule is also bounded to 4xx.
    test('502 with an interpolated exception is hidden', () {
      expect(
        backendDetail(_err(
          {'detail': 'Ошибка подключения к delivery: [Errno -2] Name or service not known'},
          status: 502,
        )),
        isNull,
      );
    });

    test('504 gateway timeout is hidden', () {
      expect(
        backendDetail(_err({'detail': 'Timeout: delivery не отвечает'}, status: 504)),
        isNull,
      );
    });

    test('500 is hidden', () {
      expect(
        backendDetail(_err({'detail': 'Внутренняя ошибка'}, status: 500)),
        isNull,
      );
    });
  });

  group('backendDetail — hides everything not written for an operator', () {
    test('internal English detail falls through to the caller message', () {
      // delivery-service's own generic catch-all. Showing this to a Russian
      // -speaking manager reads like a crash and says nothing actionable.
      expect(backendDetail(_err({'detail': 'Failed to create delivery claim'})),
          isNull);
    });

    test('"Admin only" is hidden — 403 is about the session, not the order', () {
      expect(backendDetail(_err({'detail': 'Admin only'}, status: 403)), isNull);
    });

    test('a Russian 401/403 is still hidden — session wording wins', () {
      expect(backendDetail(_err({'detail': 'Нет доступа'}, status: 403)), isNull);
      expect(backendDetail(_err({'detail': 'Нет доступа'}, status: 401)), isNull);
    });

    test('FastAPI 422 list-shaped detail is hidden', () {
      // Validation errors come back as a list of dicts — a developer shape.
      final body = {
        'detail': [
          {'loc': ['body', 'order_id'], 'msg': 'field required'}
        ]
      };
      expect(backendDetail(_err(body, status: 422)), isNull);
    });

    test('empty and whitespace-only details are hidden', () {
      expect(backendDetail(_err({'detail': ''})), isNull);
      expect(backendDetail(_err({'detail': '   '})), isNull);
    });

    test('missing detail key is hidden', () {
      expect(backendDetail(_err({'error': 'nope'})), isNull);
    });

    test('non-map body is hidden', () {
      expect(backendDetail(_err('plain text body')), isNull);
      expect(backendDetail(_err(null)), isNull);
    });

    test('a transport failure with no response is hidden', () {
      // No server verdict exists, so the caller's own "check your connection"
      // style message is the honest thing to show.
      final req = RequestOptions(path: '/gw/delivery/claims/create');
      expect(
        backendDetail(DioException(
          requestOptions: req,
          type: DioExceptionType.connectionTimeout,
        )),
        isNull,
      );
    });

    test('a non-Dio error is hidden', () {
      expect(backendDetail(StateError('boom')), isNull);
    });
  });

  // The pickup handover catches a typed OrdersApiException, not a
  // DioException, so backendDetail cannot be used there — by then the
  // response is gone and all that survives is (message, statusCode).
  // These assert the SAME discipline holds on that reduced pair.
  group('operatorSafeDetail — the handover path', () {
    test('a Russian 409 refusal is shown verbatim', () {
      expect(
        operatorSafeDetail('Заказ не оплачен, выдавать нельзя', 409),
        'Заказ не оплачен, выдавать нельзя',
      );
    });

    test('a Russian 400 is shown too', () {
      expect(operatorSafeDetail('Недопустимый переход статуса', 400),
          'Недопустимый переход статуса');
    });

    test('whitespace is trimmed', () {
      expect(operatorSafeDetail('  Заказ не готов  ', 409), 'Заказ не готов');
    });

    // The four a manager must never read while the customer waits.
    test('the English internal fallback is hidden', () {
      expect(operatorSafeDetail('Failed to update order status', 400), isNull);
    });

    test('a gateway 5xx is hidden even when its detail is Russian', () {
      expect(
        operatorSafeDetail('Ошибка подключения к order: [Errno -3]', 502),
        isNull,
      );
    });

    test('401/403 are hidden — the session wording is more actionable', () {
      expect(operatorSafeDetail('Только для администратора', 401), isNull);
      expect(operatorSafeDetail('Только для администратора', 403), isNull);
    });

    test('a transport failure has no status, so nothing is shown', () {
      expect(operatorSafeDetail('Не удалось обновить статус', null), isNull);
    });

    test('empty, whitespace-only and null messages are hidden', () {
      expect(operatorSafeDetail('', 409), isNull);
      expect(operatorSafeDetail('   ', 409), isNull);
      expect(operatorSafeDetail(null, 409), isNull);
    });

    // Two implementations of one rule drift apart silently. This pins them
    // together on the inputs that actually occur.
    test('agrees with backendDetail on the same inputs', () {
      final cases = <String, int>{
        'Заказ не оплачен': 409,
        'Failed to update order status': 409,
        'Ошибка подключения к order: [Errno -3]': 502,
        'Admin only': 403,
      };
      cases.forEach((detail, code) {
        expect(
          operatorSafeDetail(detail, code),
          backendDetail(_err({'detail': detail}, status: code)),
          reason: 'disagreed on $code / $detail',
        );
      });
    });
  });

  group('describeApiError is unchanged by this', () {
    test('still maps a transport failure to the connection message', () {
      final req = RequestOptions(path: '/x');
      final e = DioException(
        requestOptions: req,
        type: DioExceptionType.connectionTimeout,
      );
      expect(describeApiError(e, subject: 'заказы'), contains('Нет связи'));
    });
  });
}
