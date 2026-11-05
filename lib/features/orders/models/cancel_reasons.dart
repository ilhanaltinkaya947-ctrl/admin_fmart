// The cancel-reason picker, same shape as `refund_button.dart`'s
// `buildRefundReasons`: a fixed set of Russian labels so the free-text mess
// that made refund reasons unanalyzable never happens here either.
//
// Sweep 31.10 #4: 6 of 42 paid orders at Адырбекова were cancelled 7–33 min
// after the store accepted, 84 K, and nobody could tell whether that was
// missing items, a bad phone call, or something else — there was no reason
// at all. This is ASKED ONLY when cancelling a PAID order (money already
// captured): a `pending-payment` cancel never moved money, so there is
// nothing yet to explain.
//
// Sent as the SAME `reason` string order-service already accepts on
// `POST /gw/order/admin/{id}/cancel` — no schema change.
const List<String> cancelReasons = <String>[
  'Товар не в наличии',
  'Покупатель попросил отменить',
  'Не дозвонились до покупателя',
  'Долгая доставка',
  kOtherCancelReason,
];

/// The one reason that is useless without a comment — ux review: a manager
/// under pressure reaches for the no-further-questions option first, and
/// that is exactly the un-analyzable gap this whole picker exists to close.
/// The confirm button in `order_details_page.dart` stays disabled until this
/// reason has a non-empty note next to it.
const String kOtherCancelReason = 'Другое';
