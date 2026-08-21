/// How much of an order the refund sheet may still offer.
///
/// Pure and dependency-free on purpose — no widgets, no Dio, no state — so the
/// arithmetic that decides how much money a manager gives back can be tested
/// exhaustively. It mirrors `app/domain/captured_amount.py` on the backend, and
/// the two must agree: the backend enforces the same ceiling server-side, so if
/// this one is looser the manager gets a confusing rejection, and if it is
/// tighter they cannot issue a refund the backend would have accepted.
///
/// The distinction the old code missed:
///
///   totalAmount     what the order is worth NOW. Mutable — a substitution or
///                   an item edit makes the backend run
///                   recalculate_order_totals and rewrite it, so after a
///                   partial refund it is already NET of that refund.
///   capturedAmount  what was actually CHARGED, frozen at capture, never moved.
///
/// `totalAmount - alreadyRefunded` therefore subtracts the same money twice.
/// The result was displayed as the remaining-refundable line AND prefilled into
/// the amount field, so the manager confirmed a short refund with nothing on
/// screen to reveal it. Measured in production: orders 392 and 424 were
/// hand-refunded from this screen and landed 20 ₸ and 55 ₸ light, each time by
/// exactly the size of the earlier substitution refund.
library;

/// The ceiling for a refund on this order, and where it came from.
class RefundCeiling {
  /// How much may still be refunded. Never negative.
  final double remaining;

  /// The figure [remaining] was computed against.
  final double basis;

  /// True when a real captured amount backed this answer. False means we fell
  /// back to `totalAmount` and the number may be short — same fallback the
  /// backend takes, so the two still agree.
  final bool known;

  const RefundCeiling({
    required this.remaining,
    required this.basis,
    required this.known,
  });
}

/// Parse a money string the backend sent. Accepts `"145.00"` and `"145,00"`.
double parseMoney(String? v) {
  if (v == null) return 0.0;
  return double.tryParse(v.trim().replaceAll(',', '.')) ?? 0.0;
}

/// Decide how much of an order is still refundable.
///
/// [capturedAmount] is null on orders captured before the backend column
/// existed, and on orders never captured at all. In that case this falls back
/// to `totalAmount - alreadyRefunded`, which is the OLD (short) behaviour —
/// kept deliberately so an un-backfilled order behaves exactly as it does today
/// rather than offering no refund at all. [RefundCeiling.known] is false there.
///
/// Note that null and "0.00" are different: null means we have no record of a
/// capture, while 0.00 means we captured nothing and there is genuinely nothing
/// to give back. Never collapse the two.
RefundCeiling refundCeiling({
  required String? capturedAmount,
  required String totalAmount,
  required double alreadyRefunded,
}) {
  final total = parseMoney(totalAmount);
  final known = capturedAmount != null;
  final basis = known ? parseMoney(capturedAmount) : total;

  final remaining = basis - alreadyRefunded;
  return RefundCeiling(
    remaining: remaining < 0 ? 0.0 : remaining,
    basis: basis,
    known: known,
  );
}
