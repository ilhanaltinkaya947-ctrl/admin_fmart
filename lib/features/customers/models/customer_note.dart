/// One internal staff-only note attached to a customer record.
///
/// Read from /gw/auth/admin/customers/{id}/notes. Never sent to the
/// customer — visible only to admin/manager.
class CustomerNote {
  final int id;
  final String body;
  final int createdBy;
  final DateTime createdAt;

  const CustomerNote({
    required this.id,
    required this.body,
    required this.createdBy,
    required this.createdAt,
  });

  factory CustomerNote.fromJson(Map<String, dynamic> j) => CustomerNote(
        id: j['id'] as int,
        body: (j['body'] as String? ?? '').trim(),
        createdBy: j['created_by'] as int,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
