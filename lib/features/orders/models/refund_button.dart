// The refund-button decision for the order screen.
//
// Extracted from `_OrderDetailsPageState._canRefund` for the same reason
// `refundable.dart` was extracted: the rule is money and access, and it needs a
// test that does not have to build a 3,400-line widget to run.
//
// Кирилл 2026-10-07, Сб.8:
//   «закрыть доступы к возвратам на закрытом заказе у сотрудников, оставить
//    только у админов»
//
// This is the CLIENT half. order-service enforces the same rule with a 403
// (`refund_order`), and that server gate is the one that counts — a hidden
// button is cosmetic. The two must agree, or a manager sees a control that
// fails when tapped, which is worse than not seeing it: it teaches staff that
// the app is broken rather than that the action is not theirs.
//
// Deliberately ONE-SIDED: this can only ever take a control AWAY. A rule that
// also revealed the button would be a second source of truth about who may
// refund, and the two would drift.

/// Whether the refund control should be offered for [status].
///
/// * live orders (paid / processing / ready-for-delivery / delivering /
///   partially-refunded) — unchanged, managers included: that is the normal
///   counter flow and Kirill's words are about a CLOSED order.
/// * `completed` — admin only.
/// * anything else (canceled, refunded, payment-failed, …) — never.
bool canRefund({
  required String status,
  required bool isAdmin,
}) {
  final s = status.trim().toLowerCase();
  if (s == 'completed') return isAdmin;
  return const {
    'paid',
    'processing',
    'ready-for-delivery',
    'delivering',
    'partially-refunded',
  }.contains(s);
}
