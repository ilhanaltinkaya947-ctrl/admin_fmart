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
