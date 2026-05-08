import '../../orders/models/order_models.dart' show Pagination;

class AdminCustomer {
  final int id;
  final String phone;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String role;
  final DateTime createdAt;

  AdminCustomer({
    required this.id,
    required this.phone,
    this.email,
    this.firstName,
    this.lastName,
    required this.role,
    required this.createdAt,
  });

  String get fullName {
    final fn = (firstName ?? '').trim();
    final ln = (lastName ?? '').trim();
    final c = ('$fn $ln').trim();
    return c.isNotEmpty ? c : '—';
  }

  factory AdminCustomer.fromJson(Map<String, dynamic> j) => AdminCustomer(
        id: j['id'] as int? ?? 0,
        phone: (j['phone'] as String? ?? '').trim(),
        email: (j['email'] as String?)?.trim(),
        firstName: (j['first_name'] as String?)?.trim(),
        lastName: (j['last_name'] as String?)?.trim(),
        role: (j['role'] as String? ?? '').trim(),
        createdAt:
            DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class CustomersPage {
  final Pagination pagination;
  final List<AdminCustomer> items;

  CustomersPage({required this.pagination, required this.items});

  factory CustomersPage.fromJson(Map<String, dynamic> j) => CustomersPage(
        pagination:
            Pagination.fromJson((j['pagination'] as Map).cast<String, dynamic>()),
        items: ((j['items'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(AdminCustomer.fromJson)
            .toList(),
      );
}
