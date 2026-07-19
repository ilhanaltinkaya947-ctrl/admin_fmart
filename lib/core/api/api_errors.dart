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
