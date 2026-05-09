import '../../orders/models/order_models.dart' show Pagination;

class AdminUser {
  final int id;
  final String phone;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String role;
  final List<int> assignedStoreIds;
  final DateTime createdAt;

  AdminUser({
    required this.id,
    required this.phone,
    this.email,
    this.firstName,
    this.lastName,
    required this.role,
    required this.assignedStoreIds,
    required this.createdAt,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isManager => role.toLowerCase() == 'manager';

  String get fullName {
    final fn = (firstName ?? '').trim();
    final ln = (lastName ?? '').trim();
    final c = ('$fn $ln').trim();
    return c.isNotEmpty ? c : '—';
  }

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as int? ?? 0,
        phone: (j['phone'] as String? ?? '').trim(),
        email: (j['email'] as String?)?.trim(),
        firstName: (j['first_name'] as String?)?.trim(),
        lastName: (j['last_name'] as String?)?.trim(),
        role: (j['role'] as String? ?? '').trim(),
        assignedStoreIds: ((j['assigned_store_ids'] as List?) ?? const [])
            .whereType<int>()
            .toList(),
        createdAt:
            DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class AdminUsersPage {
  final Pagination pagination;
  final List<AdminUser> items;

  AdminUsersPage({required this.pagination, required this.items});

  factory AdminUsersPage.fromJson(Map<String, dynamic> j) => AdminUsersPage(
        pagination:
            Pagination.fromJson((j['pagination'] as Map).cast<String, dynamic>()),
        items: ((j['items'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(AdminUser.fromJson)
            .toList(),
      );
}
