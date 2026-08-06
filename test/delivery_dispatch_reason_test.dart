// End-to-end within the app, stubbed at the HTTP transport layer.
//
// The unit tests in api_errors_test.dart hand `backendDetail` a DioException
// built by hand. That proves the rule, not the plumbing — and the plumbing is
// where this kind of fix usually dies: if dio handed the cubit a String
// instead of a parsed Map, or the auth interceptor rewrapped the error, the
// helper would silently return null and the manager would still see nothing.
//
// So these drive a REAL Dio through a stub adapter: real JSON decoding, the
// real ApiClient interceptor, the real DeliveryRepository, the real cubit.
// The only fake is the socket.
//
// The 409 body is copied byte-for-byte from what delivery-service returned in
// production on 2026-08-06.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/storage/token_storage.dart';
import 'package:admin_fmart/features/delivery/data/delivery_repository.dart';
import 'package:admin_fmart/features/delivery/models/delivery_models.dart';
import 'package:admin_fmart/features/delivery/state/delivery_cubit.dart';

/// The real one reads FlutterSecureStorage, which needs a platform channel.
class _FakeTokenStorage extends TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'test-access-token';
}

/// Returns a canned HTTP response without touching a socket. Everything above
/// it — dio's decoder, the interceptor chain, the repository — runs for real.
class _StubAdapter implements HttpClientAdapter {
  final int status;
  final String body;
  final String contentType;

  _StubAdapter(this.status, this.body,
      {this.contentType = Headers.jsonContentType});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DeliveryCubit _cubitReturning(int status, String body,
    {String contentType = Headers.jsonContentType}) {
  final api = ApiClient(
    baseUrl: 'http://stub.invalid',
    tokenStorage: _FakeTokenStorage(),
    onUnauthorized: () {},
  );
  api.dio.httpClientAdapter = _StubAdapter(status, body, contentType: contentType);
  return DeliveryCubit(repo: DeliveryRepository(api: api));
}

CreateClaimRequestDto _dto() => CreateClaimRequestDto(
      orderId: 94,
      storeId: 4,
      totalAmount: 5000,
      requestId: 'test-request-id',
      tariffCode: 'express',
      items: const [],
      routePoints: const [],
      userPhone: '+77070000000',
      contactName: 'Test',
    );

void main() {
  // Verbatim from delivery_service.py.
  const gateMessage = 'Нельзя вызвать курьера: заказ не готов к доставке';

  test('the courier gate 409 reaches the manager as the gate wrote it', () async {
    final cubit = _cubitReturning(409, '{"detail":"$gateMessage"}');

    await cubit.create(_dto());

    expect(cubit.state, isA<DeliveryError>());
    expect((cubit.state as DeliveryError).message, gateMessage);
  });

  test('an internal English detail still shows the generic message', () async {
    // delivery-service's own catch-all. Reads like a crash to a Russian
    // -speaking operator, so it must not be surfaced.
    final cubit =
        _cubitReturning(400, '{"detail":"Failed to create delivery claim"}');

    await cubit.create(_dto());

    expect((cubit.state as DeliveryError).message, 'Не удалось создать заявку');
  });

  test('a gateway 502 does not leak its raw exception to the manager', () async {
    // The gateway's own detail IS Russian but interpolates the exception.
    // Language alone would let this through; the 4xx bound is what stops it.
    final cubit = _cubitReturning(502,
        '{"detail":"Ошибка подключения к delivery: [Errno -2] Name or service not known"}');

    await cubit.create(_dto());

    expect((cubit.state as DeliveryError).message, 'Не удалось создать заявку');
  });

  test('a non-JSON error body does not crash the cubit', () async {
    // A proxy or WAF can return HTML on a bad day. asJsonMap/backendDetail
    // must both survive it rather than throwing inside the catch block.
    final cubit = _cubitReturning(502, '<html>502 Bad Gateway</html>',
        contentType: 'text/html');

    await cubit.create(_dto());

    expect(cubit.state, isA<DeliveryError>());
    expect((cubit.state as DeliveryError).message, 'Не удалось создать заявку');
  });

  test('success is unaffected — no regression on the happy path', () async {
    // create() calls createClaim then claimInfo; the stub answers both with a
    // shape carrying the fields each DTO needs.
    const body = '{"order_id":464,"claim_id":"abc123","status":"new",'
        '"version":1,"provider":"yandex","tariff_code":"express",'
        '"price":2447.6,"currency":"KZT","provider_payload":{}}';
    final cubit = _cubitReturning(200, body);

    await cubit.create(_dto());

    expect(cubit.state, isA<DeliveryReady>(),
        reason: 'a successful dispatch must still reach DeliveryReady');
    expect((cubit.state as DeliveryReady).claimId, 'abc123');
  });
}
