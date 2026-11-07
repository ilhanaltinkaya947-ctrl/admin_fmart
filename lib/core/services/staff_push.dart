/// Staff push kinds (contract B, round 2, 07.11).
///
/// order-service puts `data.kind` on every OneSignal staff push:
/// `new_order` (only on the FIRST move to paid), `customer_confirmed`,
/// `status_changed`, `refund`, `order_modified`, `substitution`, and maybe more.
///
/// Only a new order may ring the siren and open the «Новый заказ» dialog. On
/// #100000 (07.11) the store heard the siren twice: once at create, before the
/// customer paid, and once more for «Клиент подтвердил заказ». A siren that
/// cries wolf teaches staff to mute the one alarm they have to trust.
///
/// A push with NO kind comes from an older order-service that does not send
/// it yet. That keeps today's behaviour (siren + dialog), so a server rollback
/// can never make a real new order silent.
bool isNewOrderPush(Map<String, dynamic> data) {
  final kind = staffPushKind(data);
  return kind == null || kind == 'new_order';
}

/// The normalised `data.kind`, or null when the push has none.
String? staffPushKind(Map<String, dynamic> data) {
  final raw = data['kind'];
  if (raw == null) return null;
  final k = raw.toString().trim().toLowerCase();
  return k.isEmpty ? null : k;
}

/// The quiet banner text for a push that is not a new order.
///
/// The push's own title and body come first: the server wrote them for this
/// exact event («Клиент подтвердил заказ», «Заказ №N: состав подтверждён…»).
/// The per-kind lines are only a fallback for a push with no text.
String quietStaffPushText(
  Map<String, dynamic> data, {
  String? title,
  String? body,
  int? orderId,
}) {
  final t = (title ?? '').trim();
  final b = (body ?? '').trim();
  if (t.isNotEmpty && b.isNotEmpty) return '$t. $b';
  if (t.isNotEmpty) return t;
  if (b.isNotEmpty) return b;
  final n = orderId != null ? ' №$orderId' : '';
  switch (staffPushKind(data)) {
    case 'customer_confirmed':
      return 'Клиент подтвердил заказ$n';
    case 'status_changed':
      return 'Статус заказа$n изменился';
    case 'refund':
      return 'Возврат по заказу$n';
    case 'order_modified':
      return 'Клиент изменил заказ$n';
    case 'substitution':
      return 'Клиент ответил по замене в заказе$n';
    default:
      return orderId != null ? 'Обновление по заказу$n' : 'Новое уведомление';
  }
}
