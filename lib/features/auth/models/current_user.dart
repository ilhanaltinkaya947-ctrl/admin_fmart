import 'package:equatable/equatable.dart';

class CurrentUser extends Equatable {
  final int id;
  final String phone;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String role;
  final List<int> assignedStoreIds;

  const CurrentUser({
    required this.id,
    required this.phone,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.assignedStoreIds,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isManager => role.toLowerCase() == 'manager';
  bool get isStaff => isAdmin || isManager;

  String get fullName {
    final fn = (firstName ?? '').trim();
    final ln = (lastName ?? '').trim();
    final combined = ('$fn $ln').trim();
    return combined.isNotEmpty ? combined : phone;
  }

  factory CurrentUser.fromJson(Map<String, dynamic> j) => CurrentUser(
        id: j['id'] as int? ?? 0,
        phone: (j['phone'] as String? ?? '').trim(),
        email: (j['email'] as String?)?.trim(),
        firstName: (j['first_name'] as String?)?.trim(),
        lastName: (j['last_name'] as String?)?.trim(),
        role: (j['role'] as String? ?? '').trim(),
        assignedStoreIds: ((j['assigned_store_ids'] as List?) ?? const [])
            .whereType<int>()
            .toList(),
      );

  @override
  List<Object?> get props =>
      [id, phone, email, firstName, lastName, role, assignedStoreIds];
}
