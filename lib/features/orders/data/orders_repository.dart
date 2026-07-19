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
    // storeId is intentionally unused now — the backend identifies the
    // order by its own id. Kept in the signature so existing callers
    // (and the polling loop on the order detail page) compile unchanged.
    try {
      final resp = await api.dio.get('/gw/order/admin/orders/$orderId');
      final data = resp.data;
      if (data is! Map) return null;
      return Order.fromJson(data.cast<String, dynamic>());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
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

  /// Release an off-hours SCHEDULED order early — moves it out of the
  /// `scheduled` holding status into the normal fulfillment flow (paid /
  /// processing) so the picker can start assembling it before the 09:00
  /// auto-release worker fires. Backend endpoint added in task #229.
  Future<SimpleActionResponse> releaseOrder({required int orderId}) async {
    try {
      final resp =
          await api.dio.post('/gw/order/admin/orders/$orderId/release');
      return SimpleActionResponse.fromJson(asJsonMap(resp.data));
    } on DioException catch (e) {
      throw OrdersApiException(
        _extractApiErrorMessage(e) ?? 'Не удалось выпустить заказ',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Refund an order. [idempotencyKey] MUST be generated once per
  /// admin-initiated refund attempt and reused if the call is retried.
  /// The backend DEDUPES refunds by a partial unique index
  /// `ux_order_refunds_idem (order_id, idempotency_key)` (task #60/#417), so a
  /// retried call returns the first refund's result instead of applying a
  /// duplicate. Do NOT regenerate the key per attempt — that would defeat the
  /// dedupe and re-introduce the #79 double-apply class.
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

  /// Manager override for auto-assigned bag counts. Used when the
  /// heuristic picked the wrong bag (e.g. 7L of glass juice doesn't fit
  /// a Medium). Backend recomputes packaging_sum + adjusts total_amount
  /// by the delta and writes a history row. Status-gated on the backend
  /// (paid/processing only).
  Future<PackagingEditResult> updatePackaging({
    required int orderId,
    required int bigBagCount,
    required int mediumBagCount,
  }) async {
    final resp = await api.dio.patch(
      '/gw/order/admin/orders/$orderId/packaging',
      data: {
        'big_bag_count': bigBagCount,
        'medium_bag_count': mediumBagCount,
      },
    );
    return PackagingEditResult.fromJson(asJsonMap(resp.data));
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

  /// Per-day order count + revenue between [dateFrom] and [dateTo].
  /// Backend omits zero-day rows; caller zero-fills for the chart.
  Future<SalesByDayResponse> getSalesByDay({
    required int storeId,
    required DateTime dateFrom,
    required DateTime dateTo,
    String tz = 'Asia/Almaty',
  }) async {
    final resp = await api.dio.get(
      '/gw/order/admin/reports/sales-by-day',
      queryParameters: {
        'store_id': storeId,
        'date_from': dateFrom.toUtc().toIso8601String(),
        'date_to': dateTo.toUtc().toIso8601String(),
        'tz': tz,
      },
    );
    return SalesByDayResponse.fromJson(asJsonMap(resp.data));
  }

  Future<TopProductsResponse> getTopProducts({
    required int storeId,
    required DateTime dateFrom,
    required DateTime dateTo,
    int limit = 10,
  }) async {
    final resp = await api.dio.get(
      '/gw/order/admin/reports/top-products',
      queryParameters: {
        'store_id': storeId,
        'date_from': dateFrom.toUtc().toIso8601String(),
        'date_to': dateTo.toUtc().toIso8601String(),
        'limit': limit,
      },
    );
    return TopProductsResponse.fromJson(asJsonMap(resp.data));
  }

  /// Admin Отзывы tab — paginated reviews for one store, optional
  /// rating + date filters. Backend returns has_more so we can render
  /// "Load more" without a separate count query.
  Future<ReviewsListResponse> getReviews({
    required int storeId,
    int limit = 50,
    int offset = 0,
    int? minRating,
    int? maxRating,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? answered,
  }) async {
    final resp = await api.dio.get(
      '/gw/order/admin/reviews',
      queryParameters: {
        'store_id': storeId,
        'limit': limit,
        'offset': offset,
        if (minRating != null) 'min_rating': minRating,
        if (maxRating != null) 'max_rating': maxRating,
        if (dateFrom != null) 'date_from': dateFrom.toUtc().toIso8601String(),
        if (dateTo != null) 'date_to': dateTo.toUtc().toIso8601String(),
        if (answered != null) 'answered': answered,
      },
    );
    return ReviewsListResponse.fromJson(asJsonMap(resp.data));
  }

  /// Per-user feature flags for staged rollout (review reply, substitution UI).
  /// Empty/failed → caller keeps the safe all-off default.
  Future<Map<String, bool>> getFeatures() async {
    final resp = await api.dio.get('/gw/order/app/features');
    final j = asJsonMap(resp.data);
    return {
      for (final e in j.entries)
        if (e.value is bool) e.key.toString(): e.value as bool,
    };
  }

  /// Manager replies to a customer review. Backend upserts the reply + fires
  /// one push to the customer. [replyTag] is an optional resolution marker
  /// (in_progress / refunded / resolved). Returns the updated review.
  Future<ReviewItem> replyToReview({
    required int orderId,
    required String replyText,
    String? replyTag,
  }) async {
    final resp = await api.dio.put(
      '/gw/order/admin/reviews/$orderId/reply',
      data: {
        'reply_text': replyText,
        if (replyTag != null) 'reply_tag': replyTag,
      },
    );
    return ReviewItem.fromJson(asJsonMap(resp.data));
  }

  Future<ReviewStats> getReviewStats({
    required int storeId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final resp = await api.dio.get(
      '/gw/order/admin/reviews/stats',
      queryParameters: {
        'store_id': storeId,
        if (dateFrom != null) 'date_from': dateFrom.toUtc().toIso8601String(),
        if (dateTo != null) 'date_to': dateTo.toUtc().toIso8601String(),
      },
    );
    return ReviewStats.fromJson(asJsonMap(resp.data));
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

  // ───────────────────────── item substitution ─────────────────────────

  /// Similar products for [productId] at [storeId], capped at [maxPrice]
  /// (the OOS item's unit price) so the picker only offers equal-or-cheaper
  /// candidates. Backend already filters in-stock + active.
  Future<List<SimilarProduct>> getSimilarProducts({
    required int storeId,
    required int productId,
    required double maxPrice,
  }) async {
    final resp = await api.dio.get(
      '/gw/catalog/products/similar-products',
      queryParameters: {
        'store_id': storeId,
        'product_id': productId,
        'max_price': maxPrice,
      },
    );
    final data = resp.data;
    final list = (data is List) ? data : const [];
    return list
        .whereType<Map>()
        .map((m) => SimilarProduct.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// Propose an equal-or-cheaper substitute for an OOS item. The backend
  /// re-validates the substitute price/stock (never trusts the client) and
  /// returns 409 with a Russian reason on any violation (dearer, OOS, or an
  /// already-open proposal for this item) — surfaced via [OrdersApiException].
  Future<Map<String, dynamic>> proposeSubstitution({
    required int orderId,
    required int itemId,
    required int substituteProductId,
    String? managerNote,
  }) async {
    try {
      final resp = await api.dio.post(
        '/gw/order/admin/orders/$orderId/items/$itemId/substitute',
        data: {
          'substitute_product_id': substituteProductId,
          if (managerNote != null && managerNote.trim().isNotEmpty)
            'manager_note': managerNote.trim(),
        },
      );
      return asJsonMap(resp.data);
    } on DioException catch (e) {
      throw OrdersApiException(
        _extractApiErrorMessage(e) ?? 'Не удалось предложить замену',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Withdraw a still-open proposal before the customer answers. 409 if the
  /// customer already accepted/declined in the meantime.
  Future<SimpleActionResponse> cancelSubstitution({
    required int orderId,
    required int subId,
  }) async {
    try {
      final resp = await api.dio.post(
        '/gw/order/admin/orders/$orderId/substitutions/$subId/cancel',
      );
      return SimpleActionResponse.fromJson(asJsonMap(resp.data));
    } on DioException catch (e) {
      throw OrdersApiException(
        _extractApiErrorMessage(e) ?? 'Не удалось отменить замену',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
