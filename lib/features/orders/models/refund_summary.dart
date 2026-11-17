/// What the customer is owed back, and what already went back (1.3.1).
///
/// order-service sends `refund_summary` on the admin order detail:
///   {"captured": "17050.00", "current_total": "9400.00", "owed": "7650.00",
///    "refunded": "7700.00", "pending": "0.00", "remaining_owed": "0.00",
///    "over_by": "50.00"}
/// Money arrives as strings, like every other money field of the response.
/// An older server does not send it: then [RefundSummary.tryParse] is null and
/// every line built from it stays hidden.
///
/// The manual refund endpoint refuses a refund that would push `refunded`
/// above `owed` by more than [kOverOwedTolerance] with a 409
/// `{"code": "refund_over_owed", "owed", "refunded", "requested"}`, unless the
/// request carries `confirm_over_owed: true`. The app checks the same rule as
/// the person types so the confirm step comes before the tap, not after.
library;

import '../../../core/format/money.dart';

/// The server lets a refund overshoot what is owed by up to 1 ₸ (rounding).
const double kOverOwedTolerance = 1.0;

class RefundSummary {
  final double captured;
  final double currentTotal;
  final double owed;
  final double refunded;
  final double pending;
  final double remainingOwed;
  final double overBy;

  const RefundSummary({
    required this.captured,
    required this.currentTotal,
    required this.owed,
    required this.refunded,
    this.pending = 0,
    this.remainingOwed = 0,
    this.overBy = 0,
  });

  /// Null when the server did not send the block, or sent it without the two
  /// numbers every line needs (`owed`, `refunded`). Never throws: a malformed
  /// value must not be the reason an order screen fails to open.
  static RefundSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    double? money(String key) {
      final v = raw[key];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return double.tryParse(s.replaceAll(',', '.'));
    }

    final owed = money('owed');
    final refunded = money('refunded');
    if (owed == null || refunded == null) return null;
    return RefundSummary(
      captured: money('captured') ?? 0,
      currentTotal: money('current_total') ?? 0,
      owed: owed,
      refunded: refunded,
      pending: money('pending') ?? 0,
      remainingOwed: money('remaining_owed') ?? 0,
      overBy: money('over_by') ?? 0,
    );
  }

  /// Anything worth a line on the order screen: money owed, sent or on its way.
  bool get hasAnything => owed > 0 || refunded > 0 || pending > 0;

  /// By how much a refund of [amount] would overshoot what is owed, or null
  /// when it stays within [kOverOwedTolerance] (the server's own rule).
  double? overOwedBy(double amount) =>
      overOwedExcess(owed: owed, refunded: refunded, amount: amount);
}

/// Shared by the live check in the sheet and the server's 409 numbers.
double? overOwedExcess({
  required double owed,
  required double refunded,
  required double amount,
}) {
  if (amount <= 0) return null;
  final after = refunded + amount;
  if (after <= owed + kOverOwedTolerance) return null;
  return double.parse((after - owed).toStringAsFixed(2));
}

// ---- copy (Russian, formal, no dashes) -------------------------------------

/// «Возвращено 7 700 ₸ из 7 650 ₸» on the order screen.
String refundedOfOwedText(RefundSummary s) =>
    'Возвращено ${formatTenge(s.refunded)} из ${formatTenge(s.owed)}';

/// «Уже возвращено 7 700 ₸ из 7 650 ₸» in the refund sheet.
String alreadyRefundedOfOwedText({
  required double refunded,
  required double owed,
}) =>
    'Уже возвращено ${formatTenge(refunded)} из ${formatTenge(owed)}';

String refundPendingBankText(double pending) =>
    'Ещё уходит в банк: ${formatTenge(pending)}';

String refundOverByChipText(double overBy) =>
    'Возвращено больше на ${formatTenge(overBy)}';

String refundRemainingOwedText(double remaining) =>
    'Осталось вернуть ${formatTenge(remaining)}';

String overOwedWarningText(double excess) =>
    'Это больше, чем клиенту положено вернуть, на ${formatTenge(excess)}';

String overOwedConfirmButtonText(double amount) =>
    'Всё равно вернуть ${formatTenge(amount)}';

/// «Клиенту вернётся 1 190 ₸» before a quantity cut or a removed line.
String itemEditRefundText(Object amount) =>
    'Клиенту вернётся ${formatTenge(amount)}';

/// The 409 `refund_over_owed` answer, with the server's numbers.
class RefundOverOwed {
  final double owed;
  final double refunded;
  final double requested;
  const RefundOverOwed({
    required this.owed,
    required this.refunded,
    required this.requested,
  });

  double get excess =>
      overOwedExcess(owed: owed, refunded: refunded, amount: requested) ??
      double.parse((refunded + requested - owed).toStringAsFixed(2));

  /// The body may be the object itself or wrapped in FastAPI's `detail`.
  static RefundOverOwed? tryParse(Object? body) {
    if (body is! Map) return null;
    Map? m = body;
    if (m['code'] != 'refund_over_owed') {
      final d = body['detail'];
      m = d is Map && d['code'] == 'refund_over_owed' ? d : null;
    }
    if (m == null) return null;
    double? n(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim().replaceAll(',', '.'));
    }

    final owed = n(m['owed']);
    final refunded = n(m['refunded']);
    final requested = n(m['requested']);
    if (owed == null || refunded == null || requested == null) return null;
    return RefundOverOwed(owed: owed, refunded: refunded, requested: requested);
  }
}

/// The over-owed check as the server runs it for a manual refund: none
/// without a summary, and none for a refund that gives the rest of the card
/// back (the order becomes «refunded»; the server skips the guard then, same
/// rule as the sheet's «полный возврат»). [remainingOnCard] is the captured
/// ceiling left (refundCeiling().remaining).
double? overOwedForRefund(
  RefundSummary? s,
  double amount, {
  required double remainingOnCard,
}) {
  if (s == null) return null;
  if (amount + 0.0001 >= remainingOnCard) return null;
  return s.overOwedBy(amount);
}

/// Nothing was edited and nothing returned yet (owed = refunded = 0): a
/// refund now is goodwill, not a mistake, so the wording is softer.
bool isUneditedOrder({required double owed, required double refunded}) =>
    owed <= 0 && refunded <= 0;

/// The warning for [excess], softer on an unedited order.
String overOwedWarningFor({
  required double owed,
  required double refunded,
  required double excess,
}) =>
    isUneditedOrder(owed: owed, refunded: refunded)
        ? 'Заказ не менялся. Возврат будет сверх суммы изменений: '
            '${formatTenge(excess)}'
        : overOwedWarningText(excess);
