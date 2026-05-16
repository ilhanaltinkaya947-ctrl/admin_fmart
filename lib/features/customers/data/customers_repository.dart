import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import '../../orders/models/order_models.dart' show CustomerInfo, OrdersPage;
import '../models/customer_models.dart';
import '../models/customer_note.dart';

class CustomersRepository {
  final ApiClient api;
  CustomersRepository({required this.api});

  Future<CustomersPage> listCustomers({
    int page = 1,
    int perPage = 20,
    String? q,
  }) async {
    final qp = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    final query = (q ?? '').trim();
    if (query.isNotEmpty) qp['q'] = query;

    final resp = await api.dio.get(
      '/gw/auth/admin/customers',
      queryParameters: qp,
    );
    return CustomersPage.fromJson(asJsonMap(resp.data));
  }

  Future<CustomerInfo> getCustomerById(int customerId) async {
    // Path must include the `/customers/` segment — without it this hit
    // /gw/auth/admin/<id>, 404'd, and the customer detail page never
    // loaded (order history + notes silently failed with it).
    final resp = await api.dio.get('/gw/auth/admin/customers/$customerId');
    return CustomerInfo.fromJson(asJsonMap(resp.data));
  }

  /// Order history for a customer in the context of a single store.
  /// Backend `/admin/orders` requires `store_id`; multi-store history is
  /// a v2 concern.
  Future<OrdersPage> getOrdersForCustomer({
    required int customerId,
    required int storeId,
    int page = 1,
    int perPage = 50,
  }) async {
    final resp = await api.dio.get(
      '/gw/order/admin/orders',
      queryParameters: {
        'store_id': storeId,
        'customer_id': customerId,
        'page': page,
        'per_page': perPage,
      },
    );
    return OrdersPage.fromJson(asJsonMap(resp.data));
  }

  // ---------- Internal customer notes (staff-only) ----------

  Future<List<CustomerNote>> listNotes(int customerId) async {
    final resp = await api.dio.get('/gw/auth/admin/customers/$customerId/notes');
    final raw = asJsonMap(resp.data);
    final items = (raw['items'] as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(CustomerNote.fromJson)
        .toList();
  }

  Future<CustomerNote> createNote(int customerId, String body) async {
    final resp = await api.dio.post(
      '/gw/auth/admin/customers/$customerId/notes',
      data: {'body': body},
    );
    return CustomerNote.fromJson(asJsonMap(resp.data));
  }

  Future<void> deleteNote(int customerId, int noteId) async {
    await api.dio.delete(
      '/gw/auth/admin/customers/$customerId/notes/$noteId',
    );
  }
}
