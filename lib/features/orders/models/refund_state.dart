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
/// Returns null when the server does not send `refund_state` at all.
RefundStateView? refundStateViewAfterTap({
  required String? state,
  required DateTime? updatedAt,
  required bool awaiting,
  required DateTime? awaitingSince,
}) {
  if (state == null) return null;
  if (!awaiting) return refundStateView(state);
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
/// `unknown`.
bool refundWaitSettled({
  required String? state,
  required DateTime? updatedAt,
  required DateTime? awaitingSince,
}) {
  if (state == null) return true; // older server: nothing to wait for
  final moved = updatedAt != null &&
      (awaitingSince == null || updatedAt.isAfter(awaitingSince));
  return moved && (state == 'done' || state == 'failed' || state == 'unknown');
}
