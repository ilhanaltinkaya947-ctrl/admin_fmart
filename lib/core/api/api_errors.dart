import 'package:dio/dio.dart';

/// Coarse classification of a failed API call, used by cubits to pick
/// a friendly Russian message so the operator can distinguish "no
/// internet" from "auth expired" from "server is down". Previously every
/// cubit emitted the same "Не удалось загрузить X" which gave zero
/// diagnostic signal during incidents.
enum ApiErrorKind {
  network, // connect/receive/send timeout, host unreachable
  auth, // 401/403 — refresh already failed by the time we see it
  notFound, // 404
  badRequest, // 4xx (other) — usually our bug, not the operator's
  server, // 5xx
  unknown, // catch-all
}

ApiErrorKind classifyApiError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return ApiErrorKind.network;
      case DioExceptionType.badCertificate:
        return ApiErrorKind.network;
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        break;
    }
    final code = e.response?.statusCode;
    if (code == null) return ApiErrorKind.network;
    if (code == 401 || code == 403) return ApiErrorKind.auth;
    if (code == 404) return ApiErrorKind.notFound;
    if (code >= 500) return ApiErrorKind.server;
    if (code >= 400) return ApiErrorKind.badRequest;
  }
  return ApiErrorKind.unknown;
}

/// Built once — this runs on an error path, but there's no reason to
/// recompile the pattern per failure.
final RegExp _cyrillic = RegExp(r'[Ѐ-ӿ]');

/// The backend's own operator-facing message for a deliberate rejection,
/// or null when it didn't send one worth showing.
///
/// F-Mart services answer a *deliberate business rejection* with a Russian
/// `detail` written for the person who will read it — «Нельзя вызвать
/// курьера: заказ не готов к доставке» — and use English for internal or
/// generic fallbacks ("Failed to create delivery claim", "Admin only").
/// Only the Russian ones tell the operator something they can act on, so
/// English details are skipped in favour of the caller's own message.
///
/// The language check is the discriminator on purpose: status codes alone
/// don't separate these, because the same 400 carries both the useful
/// Russian rejections and the useless English catch-all.
///
/// Restricted to 4xx, and never 401/403, for two reasons. A 5xx is not a
/// decision about this order, so "the server is having trouble" is the
/// honest thing to say — and the gateway's own 502/504 details ARE Russian
/// but interpolate a raw exception ("Ошибка подключения к delivery: [Errno
/// -2] ..."), which is precisely what an operator must never be shown.
/// 401/403 are about the session, not the order, and the session-expired
/// wording below is more actionable.
///
/// FastAPI also returns `detail` as a LIST for 422 validation errors. That
/// shape is written for developers, never for an operator, so it's skipped.
///
/// Some newer endpoints return `detail` as an OBJECT carrying the same Russian
/// message under a `message` key, with a machine-readable `code` beside it —
/// the weight endpoints do this
/// (`{"code":"weight_missing","message":"Укажите вес или уберите позицию"}`).
/// The message is written for the operator, so it is read here; the code is
/// left to the caller, which uses it to branch (a 409 weight_missing should
/// make the screen name the unweighed lines). Only `message` is read — never
/// `code` — because a code is an English identifier and must not reach an
/// operator as if it were a reason.
///
/// Why this exists: the courier dispatch gate answers with a 409 explaining
/// that the order was never paid or hasn't been released yet, and the
/// manager was shown a flat «Не удалось создать заявку» instead — no way to
/// tell a real refusal from a transient failure, so they would just retry.
String? backendDetail(Object e) {
  if (e is! DioException) return null;
  final code = e.response?.statusCode;
  if (code == null || code < 400 || code >= 500) return null;
  if (code == 401 || code == 403) return null;
  final data = e.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  final String? text;
  if (detail is String) {
    text = detail.trim();
  } else if (detail is Map) {
    final msg = detail['message'];
    text = msg is String ? msg.trim() : null;
  } else {
    text = null;
  }
  if (text == null || text.isEmpty) return null;
  return _cyrillic.hasMatch(text) ? text : null;
}

/// The machine-readable `detail.code` of a failed call, when there is one.
///
/// The counterpart to [backendDetail]: the message is what the operator reads,
/// this is what the code branches on. Returns null unless the response is a 4xx
/// carrying a structured detail, so a caller cannot accidentally treat a
/// missing code as a decision.
String? backendErrorCode(Object e) {
  if (e is! DioException) return null;
  final status = e.response?.statusCode;
  if (status == null || status < 400 || status >= 500) return null;
  final data = e.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! Map) return null;
  final code = detail['code'];
  return code is String && code.trim().isNotEmpty ? code.trim() : null;
}

/// Same rule as [backendDetail], but for a message that has ALREADY been
/// pulled off the wire and wrapped in a typed exception, where the
/// DioException itself is no longer reachable.
///
/// `OrdersApiException` carries whatever `_extractApiErrorMessage` could
/// find, with no language filter and no status filter — so it happily
/// surfaces "Failed to update order status", or a gateway 502 detail that
/// interpolates a raw errno. Showing either to a store manager mid-handover
/// is worse than saying nothing: they cannot act on it, and it reads as a
/// crash rather than as a refusal.
///
/// Returns null when the message is not the backend's own Russian
/// explanation, so the caller can fall back to its own wording.
String? operatorSafeDetail(String? message, int? statusCode) {
  if (message == null) return null;
  final text = message.trim();
  if (text.isEmpty) return null;
  if (statusCode == null) return null;
  if (statusCode < 400 || statusCode >= 500) return null;
  if (statusCode == 401 || statusCode == 403) return null;
  return _cyrillic.hasMatch(text) ? text : null;
}

/// Renders a failure as a short Russian message suitable for a Snackbar
/// or in-page error tile. [subject] is the object being loaded — used
/// only by the generic-unknown fallback so the message still reads
/// naturally (e.g. "Не удалось загрузить заказы").
String describeApiError(Object e, {required String subject}) {
  switch (classifyApiError(e)) {
    case ApiErrorKind.network:
      return 'Нет связи с сервером. Проверьте интернет и попробуйте ещё раз.';
    case ApiErrorKind.auth:
      return 'Сессия истекла. Войдите снова.';
    case ApiErrorKind.notFound:
      return 'Не найдено.';
    case ApiErrorKind.badRequest:
      return 'Неверный запрос. Попробуйте обновить.';
    case ApiErrorKind.server:
      return 'Сервер временно недоступен. Попробуйте через минуту.';
    case ApiErrorKind.unknown:
      return 'Не удалось загрузить $subject. Попробуйте ещё раз.';
  }
}

/// The HTTP status of a failed call, or null when there was no response.
int? backendStatus(Object e) =>
    e is DioException ? e.response?.statusCode : null;

/// order-service's refusal once an order's weight has been settled
/// (`order_service.py`): «Расчёт по весу уже выполнен: вес больше не
/// меняется» on a weight PUT, «…: весовую позицию нельзя убрать, оформите
/// возврат вручную» on removing the line. Always a 409.
const String kWeightSettledPhrase = 'Расчёт по весу уже выполнен';

bool isWeightAlreadySettledRefusal(int? statusCode, String? message) =>
    statusCode == 409 && (message ?? '').contains(kWeightSettledPhrase);

/// The refusal as two plain sentences: «Расчёт по весу уже выполнен. Вес
/// больше не меняется.» The server's tail is kept, because it is the part
/// that tells the operator what to do instead.
///
/// A decision, not a glitch: callers show it WITHOUT «Повторить», since the
/// same request is refused the same way every time.
String weightAlreadySettledText(String? message) {
  final m = (message ?? '').trim();
  final i = m.indexOf(kWeightSettledPhrase);
  var tail = i < 0 ? '' : m.substring(i + kWeightSettledPhrase.length);
  tail = tail.replaceFirst(RegExp(r'^[\s:.,]+'), '').trim();
  if (tail.isEmpty) return '$kWeightSettledPhrase. Вес больше не меняется.';
  tail = tail[0].toUpperCase() + tail.substring(1);
  if (!RegExp(r'[.!?]$').hasMatch(tail)) tail = '$tail.';
  return '$kWeightSettledPhrase. $tail';
}
