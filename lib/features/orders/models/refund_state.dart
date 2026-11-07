/// Refund state on the admin order payload (contract C, round 2, 07.11).
///
/// order-service sends `refund_state` = the latest payment-service
/// refund_requests status for the order: `none | pending | deferred | done |
/// failed | unknown`, plus `refund_state_updated_at`.
///
/// Before this the app said «Возврат оформлен» the moment order-service queued
/// the refund, before the bank had answered. A failed or deferred refund never
/// reached the store, and the manager told the customer the money was back.
library;

const String kRefundDoneText = 'Возврат оформлен';
const String kRefundPendingText = 'Возврат в обработке';
const String kRefundCheckText =
    'Возврат требует проверки, мы уже разбираемся';

/// What kind of line to draw for a state.
enum RefundStateTone { done, pending, problem }

class RefundStateView {
  final String text;
  final RefundStateTone tone;
  const RefundStateView(this.text, this.tone);
}

/// The normalised state, or null when the server did not send the field (an
/// older order-service: keep today's behaviour).
String? normaliseRefundState(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString().trim().toLowerCase();
  return s.isEmpty ? null : s;
}

/// The line to show for [state], or null for no line at all (`none`, or the
/// field is missing).
///
/// Never says «оформлен» for anything but `done`. A value this build does not
/// know reads as «в обработке»: it must not claim the money is back, and it
/// must not raise an alarm nobody can act on.
RefundStateView? refundStateView(String? state) {
  switch (state) {
    case null:
    case 'none':
      return null;
    case 'done':
      return const RefundStateView(kRefundDoneText, RefundStateTone.done);
    case 'failed':
    case 'unknown':
      return const RefundStateView(kRefundCheckText, RefundStateTone.problem);
    case 'pending':
    case 'deferred':
    default:
      return const RefundStateView(kRefundPendingText, RefundStateTone.pending);
  }
}

/// The baseline a `done` must move past: the later of the server's
/// refund_state_updated_at before the tap and the newest refund ledger row
/// (order_refunds.created_at, written by the refund call itself). The ledger
/// row closes a gap: payment-service reports the WORST request with the newest
/// timestamp, and the new refund's request row is created later by the queue
/// consumer. Until then an earlier refund's `done` would otherwise read as
/// this one's.
DateTime? refundWaitBaseline(
  DateTime? beforeTap,
  Iterable<DateTime> ledgerCreatedAt,
) {
  var b = beforeTap;
  for (final c in ledgerCreatedAt) {
    if (b == null || c.isAfter(b)) b = c;
  }
  return b;
}

/// What the page should show after the manager tapped a refund (or a cancel
/// that refunds), while it waits for the server to report on THAT refund.
///
/// [awaitingSince] is the `refund_state_updated_at` the page saw when the tap
/// went out (null when there was none). The state can still be a PREVIOUS
/// refund's `done` (a second partial refund), so a `done` only counts once its
/// timestamp has moved past that baseline. Comparing server time with server
/// time, never with the iPad clock, so a wrong device clock cannot keep the
/// line stuck.
///
/// Returns null when the server does not send `refund_state` at all. While
/// awaiting, a null state is a short payment-service outage (order-service
/// leaves the field out then), so the line keeps saying «в обработке».
RefundStateView? refundStateViewAfterTap({
  required String? state,
  required DateTime? updatedAt,
  required bool awaiting,
  required DateTime? awaitingSince,
}) {
  if (!awaiting) return refundStateView(state);
  if (state == null) {
    return const RefundStateView(kRefundPendingText, RefundStateTone.pending);
  }
  final moved = updatedAt != null &&
      (awaitingSince == null || updatedAt.isAfter(awaitingSince));
  if (!moved) {
    return const RefundStateView(kRefundPendingText, RefundStateTone.pending);
  }
  return refundStateView(state) ??
      const RefundStateView(kRefundPendingText, RefundStateTone.pending);
}

/// True once the wait after a tap is over: the server reported on the new
/// refund (moved past the baseline) with a final word, `done`, `failed` or
/// `unknown`. A null state never ends the wait: the wait only starts when the
/// server sends the field, so null here is a passing outage, and ending the
/// wait on it would let an OLD `done` read as this refund's.
bool refundWaitSettled({
  required String? state,
  required DateTime? updatedAt,
  required DateTime? awaitingSince,
}) {
  if (state == null) return false;
  final moved = updatedAt != null &&
      (awaitingSince == null || updatedAt.isAfter(awaitingSince));
  return moved && (state == 'done' || state == 'failed' || state == 'unknown');
}
