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
  }) async {
    final resp = await api.dio.get(
      '/gw/order/admin/orders',
      queryParameters: {
        'store_id': storeId,
        'page': page,
        'per_page': perPage,
      },
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
}
