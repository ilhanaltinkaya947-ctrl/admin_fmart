import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import '../models/order_models.dart';

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
    await api.dio.post('/gw/order/admin/$orderId/change-status', data: {
      'status': status,
      'reason': reason,
    });
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
    final resp = await api.dio.post('/gw/order/admin/$orderId/cancel');
    return SimpleActionResponse.fromJson(asJsonMap(resp.data));
  }

  Future<SimpleActionResponse> refundOrder({
    required int orderId,
    required double amount,
    required String reason,
  }) async {
    final resp = await api.dio.post(
      '/gw/order/admin/$orderId/refund',
      data: {
        'amount': amount,
        'reason': reason,
      },
    );
    return SimpleActionResponse.fromJson(asJsonMap(resp.data));
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
}
