/// Phone-number normalisation shared across login and user-create.
///
/// Accepts whatever the operator typed (8 700 ..., +7 (700) ..., 77001234567,
/// 7001234567) and returns a canonical `+7XXXXXXXXXX` (12 chars total).
/// Returns null if the input doesn't look like a KZ phone — caller should
/// reject with a user-facing error so we don't create unloggable accounts.
String? normaliseKzPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('8') && digits.length == 11) {
    digits = '7${digits.substring(1)}';
  }
  if (digits.length == 10) {
    digits = '7$digits';
  }
  if (digits.length != 11 || !digits.startsWith('7')) return null;
  return '+$digits';
}

/// Light email check — single '@' with text both sides. Not RFC-perfect on
/// purpose; the goal is to catch the obvious typo before sending to backend.
bool isPlausibleEmail(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return false;
  final at = t.indexOf('@');
  if (at <= 0 || at != t.lastIndexOf('@')) return false;
  if (at == t.length - 1) return false;
  return t.contains('.', at);
}
