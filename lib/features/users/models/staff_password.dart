/// The staff password rule, the same one auth-service enforces on
/// `POST/PUT /admin/users` (`AuthService._validate_staff_password`:
/// `STAFF_PASSWORD_MIN_LENGTH = 12`, at least one digit, at least one letter).
///
/// Why it lives in the app too (08.11 bug): an admin typed a short new
/// password for a manager, the server refused it with a 400, and the screen
/// said «Проверь данные. Возможно, такой пользователь уже есть.» The admin
/// could not tell that the PASSWORD was the problem, so the old password
/// silently stayed. Checking here names the rule before anything is sent.
///
/// The messages are the server's own wording, so the admin reads the same
/// sentence whichever side catches it.
const int kStaffPasswordMinLength = 12;

const String kStaffPasswordHint =
    'Не короче $kStaffPasswordMinLength символов, буквы и цифры';

final RegExp _digit = RegExp(r'\p{Nd}', unicode: true);
final RegExp _letter = RegExp(r'\p{L}', unicode: true);

/// Null when [password] passes the server rule, else the reason in Russian.
String? staffPasswordProblem(String password) {
  // Python's len() counts code points, so count runes, not UTF-16 units.
  if (password.runes.length < kStaffPasswordMinLength) {
    return 'Пароль должен содержать не менее $kStaffPasswordMinLength символов';
  }
  if (!_digit.hasMatch(password)) {
    return 'Пароль должен содержать хотя бы одну цифру';
  }
  if (!_letter.hasMatch(password)) {
    return 'Пароль должен содержать хотя бы одну букву';
  }
  return null;
}
