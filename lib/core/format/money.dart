import 'package:intl/intl.dart';

final NumberFormat _ru = NumberFormat.decimalPattern('ru');

/// Format any [value] as a KZ-tenge amount: `1 500 ₸`.
///
/// Accepts `num`, `String`, or `null`. Strings that don't parse get
/// rendered raw (no crash). The trailing `.00` from `toStringAsFixed(2)`
/// is dropped when fractional part is zero, since admin doesn't care
/// about the kopecks for whole-tenge orders.
String formatTenge(Object? value) {
  if (value == null) return '0 ₸';

  num? n;
  if (value is num) {
    n = value;
  } else if (value is String) {
    n = num.tryParse(value);
    if (n == null) return value; // can't parse — render the raw text
  } else {
    return value.toString();
  }

  // Whole-tenge integer, drop fractional rendering.
  if (n is double && n == n.roundToDouble()) n = n.toInt();

  return '${_ru.format(n)} ₸';
}
