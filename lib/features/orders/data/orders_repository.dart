import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import '../models/order_models.dart';

/// Typed exception surfaced to the UI layer when an admin-facing call
/// fails. Holds the most specific human-readable message we can extract
/// from the backend payload (e.g. "Address outside delivery zone" from
/// the Yandex proxy) so the SnackBar can show the real reason instead
/// of a generic fallback.
class OrdersApiException implements Exception {
  final String message;
  final int? statusCode;
  OrdersApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Walks the response payload of a failed admin call and returns the
/// most specific human-readable message we can find. Backend services
/// surface errors in a few different shapes — FastAPI defaults to
/// `{"detail": "..."}`, the Yandex proxy can nest the upstream reason
/// inside `{"error": {"message": "..."}}`, and some endpoints return
/// plain strings. We try each shape in turn and fall back to null so
/// the caller can use a generic message.
String? _extractApiErrorMessage(DioException e) {
  final data = e.response?.data;
  if (data == null) return null;
  if (data is String) {
    final s = data.trim();
    return s.isEmpty ? null : s;
  }
  if (data is Map) {
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) {
        final s = (first['msg'] as String).trim();
        if (s.isNotEmpty) return s;
      }
    }
    for (final key in const ['message', 'error_message', 'reason']) {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final err = data['error'];
    if (err is Map) {
      final msg = err['message'];
      if (msg is String && msg.trim().isNotEmpty) return msg.trim();
      final reason = err['reason'];
      if (reason is String && reason.trim().isNotEmpty) return reason.trim();
    }
    if (err is String && err.trim().isNotEmpty) return err.trim();
  }
  return null;
}

class OrdersRepository {
  final ApiClient api;
  OrdersRepository({required this.api});

  Future<OrdersPage> getOrders({
    required int storeId,
    required int page,
    required int perPage,
    int? customerId,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<int>? statusIds,
    String? paymentMethod,
    String? search,
  }) async {
    final qp = <String, dynamic>{
      'store_id': storeId,
      'page': page,
      'per_page': perPage,
    };
    if (customerId != null) qp['customer_id'] = customerId;
    if (dateFrom != null) qp['date_from'] = dateFrom.toUtc().toIso8601String();
    if (dateTo != null) qp['date_to'] = dateTo.toUtc().toIso8601String();
    if (statusIds != null && statusIds.isNotEmpty) qp['status_ids'] = statusIds;
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      qp['payment_method'] = paymentMethod;
    }
    if (search != null && search.trim().isNotEmpty) {
      qp['search'] = search.trim();
    }

    final resp = await api.dio.get(
      '/gw/order/admin/orders',
      queryParameters: qp,
    );

    return OrdersPage.fromJson(asJsonMap(resp.data));
  }

  Future<void> changeStatus({
    required int orderId,
    required String status,
    String reason = '',
  }) async {
    try {
      await api.dio.post('/gw/order/admin/$orderId/change-status', data: {
        'status': status,
        'reason': reason,
      });
    } on DioException catch (e) {
      throw OrdersApiException(
        _extractApiErrorMessage(e) ?? 'Не удалось обновить статус',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Fetch a single order by id via the admin list endpoint's `search`
  /// param (which matches numeric input against the order id). Used by
  /// the push-tap path so we can hand a fresh OrderModel to
  /// OrderDetailsPage instead of just refreshing the list.
  Future<Order?> getOrderById({
    required int storeId,
    required int orderId,
  }) async {
    final page = await getOrders(
      storeId: storeId,
      page: 1,
      perPage: 1,
      search: orderId.toString(),
    );
    if (page.items.isEmpty) return null;
    return page.items.first;
  }

  Future<NewOrdersResponse> getNewOrders({
    required int storeId,
    DateTime? since,
    int minutes = 10,
    int limit = 20,
    List<String>? statuses,
    String tz = 'Asia/Almaty',
  }) async {
    final qp = <String, dynamic>{
      'store_id': storeId,
      'minutes': minutes,
      'limit': limit,
      'tz': tz,
    };

    if (since != null) {
      qp['since'] = since.toUtc().toIso8601String();
    }

    if (statuses != null && statuses.isNotEmpty) {
      qp['status'] = statuses;
    }

    final resp = await api.dio.get(
      '/gw/order/admin/new-orders',
      queryParameters: qp,
    );

    return NewOrdersResponse.fromJson(asJsonMap(resp.data));
  }


  Future<SimpleActionResponse> cancelOrder({required int orderId}) async {
    try {
      final resp = await api.dio.post('/gw/order/admin/$orderId/cancel');
      return SimpleActionResponse.fromJson(asJsonMap(resp.data));
    } on DioException catch (e) {
      throw OrdersApiException(
        _extractApiErrorMessage(e) ?? 'Не удалось отменить заказ',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Refund an order. [idempotencyKey] should be generated once per
  /// admin-initiated refund attempt and reused if the call is retried —
  /// backend does not currently dedupe by this header (planned), but
  /// sending it now makes server-side dedupe a one-line change later
  /// and at minimum gives us a per-attempt id in logs / Sentry.
  Future<SimpleActionResponse> refundOrder({
    required int orderId,
    required double amount,
    required String reason,
    required String idempotencyKey,
  }) async {
    try {
      final resp = await api.dio.post(
        '/gw/order/admin/$orderId/refund',
        data: {
          'amount': amount,
          'reason': reason,
        },
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return SimpleActionResponse.fromJson(asJsonMap(resp.data));
    } on DioException catch (e) {
      throw OrdersApiException(
        _extractApiErrorMessage(e) ?? 'Не удалось оформить возврат',
        statusCode: e.response?.statusCode,
      );
    }
  }


  Future<OrderStatusesResponse> getOrderStatuses() async {
    final resp = await api.dio.get('/gw/order/admin/statuses');
    return OrderStatusesResponse.fromJson(asJsonMap(resp.data));
  }

  Future<CustomerInfo> getCustomerInfo({required int customerId}) async {
    final resp = await api.dio.get('/gw/auth/admin/$customerId');
    return CustomerInfo.fromJson(asJsonMap(resp.data));
  }

  Future<OrderEventsResponse> getOrderEvents({required int orderId}) async {
    final resp = await api.dio.get('/gw/order/admin/orders/$orderId/events');
    return OrderEventsResponse.fromJson(asJsonMap(resp.data));
  }

  /// CSV export of orders matching the current filters. Backend caps at
  /// 10 000 rows. Returns the raw CSV text; caller decides what to do
  /// with it (clipboard, share sheet, etc).
  Future<String> exportOrdersCsv({
    required int storeId,
    int? customerId,
    DateTime? dateFrom,
    DateTime? dateTo,
    List<int>? statusIds,
    String? paymentMethod,
    String? search,
  }) async {
    final qp = <String, dynamic>{'store_id': storeId};
    if (customerId != null) qp['customer_id'] = customerId;
    if (dateFrom != null) qp['date_from'] = dateFrom.toUtc().toIso8601String();
    if (dateTo != null) qp['date_to'] = dateTo.toUtc().toIso8601String();
    if (statusIds != null && statusIds.isNotEmpty) qp['status_ids'] = statusIds;
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      qp['payment_method'] = paymentMethod;
    }
    if (search != null && search.trim().isNotEmpty) {
      qp['search'] = search.trim();
    }

    final resp = await api.dio.get(
      '/gw/order/admin/orders/export',
      queryParameters: qp,
      // Tell dio not to JSON-parse the CSV body.
      options: Options(responseType: ResponseType.plain),
    );
    return resp.data as String;
  }

  /// All refunds applied to [orderId], newest first. Used by the admin
  /// order-detail page to show partial-refund history when more than
  /// one refund has been applied.
  /// Today's KPIs for the admin dashboard. Returns
  /// {total, revenue, by_status, tz, as_of}.
  Future<Map<String, dynamic>> getDashboardToday({required int storeId}) async {
    final resp = await api.dio.get(
      '/gw/order/admin/dashboard/today',
      queryParameters: {'store_id': storeId},
    );
    return asJsonMap(resp.data);
  }

  Future<List<RefundHistoryEntry>> getRefundHistory({required int orderId}) async {
    final resp = await api.dio.get('/gw/order/admin/orders/$orderId/refunds');
    final raw = asJsonMap(resp.data);
    final items = (raw['items'] as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(RefundHistoryEntry.fromJson)
        .toList();
  }

  Future<OrderItemEditResult> updateItemQty({
    required int orderId,
    required int itemId,
    required int qty,
  }) async {
    final resp = await api.dio.patch(
      '/gw/order/admin/orders/$orderId/items/$itemId',
      data: {'qty': qty},
    );
    return OrderItemEditResult.fromJson(asJsonMap(resp.data));
  }

  Future<OrderItemEditResult> removeItem({
    required int orderId,
    required int itemId,
  }) async {
    final resp = await api.dio.delete(
      '/gw/order/admin/orders/$orderId/items/$itemId',
    );
    return OrderItemEditResult.fromJson(asJsonMap(resp.data));
  }

  Future<OrderItemPickedResult> setItemPicked({
    required int orderId,
    required int itemId,
    required bool picked,
  }) async {
    final path = '/gw/order/admin/orders/$orderId/items/$itemId/picked';
    final resp = picked
        ? await api.dio.post(path)
        : await api.dio.delete(path);
    return OrderItemPickedResult.fromJson(asJsonMap(resp.data));
  }
}
