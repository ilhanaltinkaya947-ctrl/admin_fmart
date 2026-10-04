// The structured `detail` shape, added for the weight endpoints.
//
// The weight API answers a refusal with {"detail": {"code": "...", "message":
// "..."}} rather than a bare string. The screen needs BOTH halves: the message
// to show the operator, the code to decide what to do.
//
// What must NOT change is the safety rule that already governed backendDetail:
// Russian only, 4xx only, never 401/403, and never an English identifier shown
// as if it were a reason. Adding a new shape is exactly the change most likely
// to bypass those rules, so they are re-pinned here against the new shape.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_fmart/core/api/api_errors.dart';

DioException _err(Object? body, {int status = 409}) {
  final req = RequestOptions(path: '/gw/order/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: body),
  );
}

void main() {
  group('backendDetail — the structured weight detail', () {
    test('reads the Russian message out of the object', () {
      expect(
        backendDetail(_err({
          'detail': {
            'code': 'weight_missing',
            'message': 'Укажите вес или уберите позицию',
          }
        })),
        'Укажите вес или уберите позицию',
      );
    });

    test('the over-cap message is readable', () {
      expect(
        backendDetail(_err(
          {
            'detail': {
              'code': 'weight_out_of_range',
              'message': 'Слишком большой вес: максимум 330 г',
              'max_g': 330,
            }
          },
          status: 422,
        )),
        'Слишком большой вес: максимум 330 г',
      );
    });

    test('🔴 an English message is still refused', () {
      // The rule that keeps internal strings off the screen.
      expect(
        backendDetail(_err({
          'detail': {'code': 'conflict', 'message': 'Cannot settle in status=x'}
        })),
        isNull,
      );
    });

    test('🔴 a structured detail on a 5xx is still refused', () {
      expect(
        backendDetail(_err(
          {
            'detail': {
              'code': 'oops',
              'message': 'Внутренняя ошибка сервера',
            }
          },
          status: 500,
        )),
        isNull,
      );
    });

    test('🔴 a structured detail on 401/403 is still refused', () {
      for (final code in [401, 403]) {
        expect(
          backendDetail(_err(
            {
              'detail': {'code': 'nope', 'message': 'Сессия истекла'}
            },
            status: code,
          )),
          isNull,
          reason: 'status $code is about the session, not the order',
        );
      }
    });

    test('an object with no message is nothing to say', () {
      expect(
        backendDetail(_err({'detail': {'code': 'weight_missing'}})),
        isNull,
      );
    });

    test('an empty message is nothing to say', () {
      expect(
        backendDetail(_err({'detail': {'code': 'x', 'message': '   '}})),
        isNull,
      );
    });

    test('the plain-string shape is unaffected', () {
      expect(
        backendDetail(_err({'detail': 'Нельзя вызвать курьера'})),
        'Нельзя вызвать курьера',
      );
    });

    test('the validation LIST shape is still skipped', () {
      expect(
        backendDetail(_err({
          'detail': [
            {'msg': 'field required', 'type': 'value_error'}
          ]
        })),
        isNull,
      );
    });
  });

  group('backendErrorCode', () {
    test('returns the code the caller branches on', () {
      expect(
        backendErrorCode(_err({
          'detail': {'code': 'weight_missing', 'message': 'Укажите вес'}
        })),
        'weight_missing',
      );
    });

    test('returns the code even when the message is English', () {
      // The code is machine-readable; the display rule does not apply to it.
      expect(
        backendErrorCode(_err({
          'detail': {'code': 'weight_settled', 'message': 'Cannot settle'}
        })),
        'weight_settled',
      );
    });

    test('null for a plain-string detail', () {
      expect(backendErrorCode(_err({'detail': 'нет'})), isNull);
    });

    test('null for a 5xx, so a crash cannot be read as a decision', () {
      expect(
        backendErrorCode(_err({
          'detail': {'code': 'x'}
        }, status: 503)),
        isNull,
      );
    });

    test('null when there is no detail at all', () {
      expect(backendErrorCode(_err({'error': 'nope'})), isNull);
    });
  });
}
