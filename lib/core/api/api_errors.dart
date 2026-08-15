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
  if (detail is! String) return null;
  final text = detail.trim();
  if (text.isEmpty) return null;
  return _cyrillic.hasMatch(text) ? text : null;
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
