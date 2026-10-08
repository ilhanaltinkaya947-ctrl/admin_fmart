// The refund-button decision for the order screen.
//
// Extracted from `_OrderDetailsPageState._canRefund` so the rule can be tested
// without building a 3,400-line widget, the same reason `refundable.dart` was
// extracted. This is money and access.
//
// Кирилл 2026-10-07, Сб.8:
//   «закрыть доступы к возвратам на закрытом заказе у сотрудников, оставить
//    только у админов»
//
// This is the CLIENT half. order-service enforces the same rule with a 403
// (`refund_order`), and that gate is the one that counts — a hidden button is
// cosmetic. The two must agree, or a manager sees a control that fails when
// tapped, which is worse than not seeing it: it teaches staff the app is broken
// rather than that the action is not theirs.
//
// Deliberately ONE-SIDED: it can only ever take a control AWAY. A rule that also
// revealed the button would be a second source of truth about who may refund,
// and the two would drift.

/// Whether the refund control should be offered.
///
/// [closed] is server-derived: the order WAS EVER `completed` (see
/// `OrderService._was_ever_completed`). It is NOT `status == 'completed'`, and
/// that distinction is the whole point — after an admin partial refund a
/// completed order reads `partially-refunded`, so a status-only rule offered a
/// manager the remaining money on a DELIVERED order. Only the server's history
/// read can tell, which is why this flag is passed in rather than computed here.
///
/// * closed (was ever completed) — admin only, whatever the current status.
/// * live orders (paid / processing / ready-for-delivery / delivering /
///   partially-refunded that never completed) — unchanged, managers included:
///   the normal counter flow.
/// * anything else (canceled, refunded, payment-failed, …) — never.
bool canRefund({
  required String status,
  required bool isAdmin,
  bool closed = false,
}) {
  final s = status.trim().toLowerCase();

  // Terminal-no-money statuses are never offered, to anyone. There is nothing
  // left to refund on a `refunded` or `canceled` order, and an admin seeing the
  // button there would be offered an action that can only fail. This check must
  // come FIRST, before `closed`: otherwise `closed` (which is true forever once
  // an order completes) would re-offer «Возврат» on a fully refunded order.
  if (const {'refunded', 'canceled', 'payment-failed'}.contains(s)) {
    return false;
  }

  // A CLOSED order (ever completed) is admin-only, whatever its status now
  // reads. This is what covers `partially-refunded` after a partial refund.
  if (closed) return isAdmin;

  // `completed` is caught by `closed` when the server sent the flag; this keeps
  // the status-only path correct for an older backend that did not.
  if (s == 'completed') return isAdmin;

  return const {
    'paid',
    'processing',
    'ready-for-delivery',
    'delivering',
    'partially-refunded',
  }.contains(s);
}
