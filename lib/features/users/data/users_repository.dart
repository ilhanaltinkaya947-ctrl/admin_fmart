import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import '../models/user_models.dart';

class UsersRepository {
  final ApiClient api;
  UsersRepository({required this.api});

  Future<AdminUsersPage> list({
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
      '/gw/auth/admin/users',
      queryParameters: qp,
    );
    return AdminUsersPage.fromJson(asJsonMap(resp.data));
  }

  Future<AdminUser> getById(int id) async {
    final resp = await api.dio.get('/gw/auth/admin/users/$id');
    return AdminUser.fromJson(asJsonMap(resp.data));
  }

  Future<AdminUser> create({
    required String phone,
    String? email,
    String? firstName,
    String? lastName,
    required String password,
    required String role,
    List<int> assignedStoreIds = const [],
  }) async {
    final resp = await api.dio.post(
      '/gw/auth/admin/users',
      data: {
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (firstName != null && firstName.isNotEmpty) 'first_name': firstName,
        if (lastName != null && lastName.isNotEmpty) 'last_name': lastName,
        'password': password,
        'role': role,
        'assigned_store_ids': assignedStoreIds,
      },
    );
    return AdminUser.fromJson(asJsonMap(resp.data));
  }

  Future<AdminUser> update(
    int id, {
    String? email,
    String? firstName,
    String? lastName,
    String? role,
    String? password,
  }) async {
    final body = <String, dynamic>{};
    if (email != null) body['email'] = email;
    if (firstName != null) body['first_name'] = firstName;
    if (lastName != null) body['last_name'] = lastName;
    if (role != null) body['role'] = role;
    if (password != null && password.isNotEmpty) body['password'] = password;

    final resp = await api.dio.put('/gw/auth/admin/users/$id', data: body);
    return AdminUser.fromJson(asJsonMap(resp.data));
  }

  Future<void> delete(int id) async {
    await api.dio.delete('/gw/auth/admin/users/$id');
  }

  Future<AdminUser> assignStores(int id, List<int> storeIds) async {
    final resp = await api.dio.put(
      '/gw/auth/admin/users/$id/stores',
      data: {'store_ids': storeIds},
    );
    return AdminUser.fromJson(asJsonMap(resp.data));
  }
}
