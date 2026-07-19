/// Address-display helpers used wherever a pre-formatted delivery
/// address is rendered to the manager.
///
/// Background: legacy customer addresses sometimes store apartment /
/// entrance / floor as the literal string "None" or get serialized into
/// the order's `delivery_address` field as a comma-joined string with
/// empty parts (e.g. "Адырбекова 114, , , ,"). Without cleanup the
/// manager sees the trailing commas in both the order detail and the
/// Yandex Доставка form.

/// True when the chunk carries a real value worth showing.
bool _isMeaningful(String s) {
  final t = s.trim().toLowerCase();
  if (t.isEmpty) return false;
  return t != 'none' && t != 'null';
}

/// Cleans a pre-formatted address string by splitting on commas,
/// trimming each part, dropping empty / "None" / "null" parts, and
/// rejoining. Idempotent + safe on already-clean addresses.
String cleanDeliveryAddress(String? raw) {
  if (raw == null) return '';
  return raw
      .split(',')
      .map((p) => p.trim())
      .where(_isMeaningful)
      .join(', ');
}
