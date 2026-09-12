/// How an order was paid, in words a manager can read.
///
/// `orders.payment_method` has carried `epay` since the Halyk rail went live
/// (23 orders as of 2026-09-12) and the model has parsed it all along, but it
/// was rendered nowhere — so during an ePay test week an ePay order and a card
/// order looked identical in the admin app.
///
/// An unknown token is shown VERBATIM rather than mapped to a friendly guess.
/// A refund and a support call both depend on knowing which rail took the
/// money, so "card" invented in place of an unrecognised value is worse than
/// the raw token: it reads as fact and sends the manager to the wrong gateway.
/// Same reasoning as never inventing a payment STATUS word — except here the
/// audience is staff, so the raw value is also the most diagnosable thing we
/// can show.
library;

const Map<String, String> _labels = <String, String>{
  'card': 'Карта',
  'apple_pay': 'Apple Pay',
  'google_pay': 'Google Pay',
  // The Halyk rail. Named for the bank, not for "epay", because a manager
  // phoning about a stuck refund has to say who to phone.
  'epay': 'Halyk ePay',
};

/// Human label for a `payment_method` token.
///
/// Returns null for an empty/missing value so callers can omit the row
/// entirely rather than print «Оплата: » with nothing after it.
String? paymentMethodLabel(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return null;
  return _labels[v.toLowerCase()] ?? v;
}

/// True when the token is one we recognise. Lets the UI style a known rail
/// differently from a token we are only echoing back.
bool isKnownPaymentMethod(String? raw) =>
    _labels.containsKey((raw ?? '').trim().toLowerCase());

/// True for the Halyk ePay rail. Kept as a named predicate so call sites read
/// as intent rather than as a string comparison.
bool isEpay(String? raw) => (raw ?? '').trim().toLowerCase() == 'epay';
