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
        // Guarded parse: a single legacy row with a null created_by (the
        // backend has documented such rows) or an odd id/created_at used
        // to throw inside listNotes().map() and break the whole notes
        // section — and createNote() threw AFTER a successful POST, so
        // the user re-submitted and created duplicate notes.
        id: (j['id'] as num?)?.toInt() ?? 0,
        body: (j['body'] as String? ?? '').trim(),
        createdBy: (j['created_by'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '') ??
                DateTime.now(),
      );
}
