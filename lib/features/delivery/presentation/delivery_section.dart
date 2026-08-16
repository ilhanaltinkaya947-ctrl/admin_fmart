import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/format/money.dart';
import '../data/delivery_repository.dart';
import '../state/delivery_cubit.dart';
import '../models/delivery_models.dart';
import 'courier_map_page.dart';

const Map<String, String> _kYandexStatusRu = {
  'new': 'Создана',
  'estimating': 'Расчёт стоимости',
  'estimating_failed': 'Ошибка расчёта',
  'ready_for_approval': 'Ожидает подтверждения',
  'accepted': 'Принята',
  'performer_lookup': 'Поиск курьера',
  'performer_draft': 'Курьер назначается',
  'performer_found': 'Курьер найден',
  'performer_not_found': 'Курьер не найден',
  'pickup_arrived': 'Курьер прибыл в магазин',
  'pickuped': 'Заказ забран',
  'delivery_arrived': 'Курьер у клиента',
  'pay_waiting': 'Ожидает оплаты',
  'delivered': 'Доставлен',
  'delivered_finish': 'Доставка завершена',
  'returning': 'Возврат в магазин',
  'returned': 'Возвращён',
  'returned_finish': 'Возврат завершён',
  'failed': 'Не удалась',
  'cancelled': 'Отменена',
  'cancelled_with_payment': 'Отменена (оплачено)',
  'cancelled_by_taxi': 'Отменена курьером',
};

String _yandexStatusRu(String code) =>
    _kYandexStatusRu[code.toLowerCase()] ?? code;

// Statuses where Yandex no longer accepts accept/cancel calls. Sending
// either returns 4xx and the admin gets a generic "Не удалось". Hide
// the action buttons instead so the only path from here is "Обновить
// статус" or "Ссылка курьера" (the link is fine to keep — it's a
// read-only redirect).
const Set<String> _kTerminalYandexStatuses = {
  'delivered',
  'delivered_finish',
  'returned',
  'returned_finish',
  'cancelled',
  'cancelled_with_payment',
  'cancelled_by_taxi',
  'failed',
  'performer_not_found',
};

bool _isTerminalYandexStatus(String code) =>
    _kTerminalYandexStatuses.contains(code.toLowerCase());

class YandexDeliverySection extends StatefulWidget {
  final int orderId;
  final int storeId;
  final double totalAmount;

  final double shippingLat;
  final double shippingLng;
  final String shippingAddress;

  final List<double> storeCoordinates;
  final String storeAddress;

  final List<CargoItemDto> items;

  final String? customerPhone;
  final String? customerName;

  final String defaultTariffCode;

  const YandexDeliverySection({
    super.key,
    required this.orderId,
    required this.storeId,
    required this.totalAmount,
    required this.shippingLat,
    required this.shippingLng,
    required this.shippingAddress,
    required this.storeCoordinates,
    required this.storeAddress,
    required this.items,
    this.customerPhone,
    this.customerName,
    this.defaultTariffCode = 'yandex_price',
  });

  @override
  State<YandexDeliverySection> createState() => _YandexDeliverySectionState();
}

class _YandexDeliverySectionState extends State<YandexDeliverySection> {
  final _phone = TextEditingController();
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _phone.text = widget.customerPhone ?? '';
    _name.text = widget.customerName ?? '';

    // Инициализация: найти claim по orderId (если есть)
    context.read<DeliveryCubit>().initByOrder(widget.orderId);
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  List<RoutePointDto> _routePoints() {
    return [
      RoutePointDto(
        type: 'source',
        coordinates: widget.storeCoordinates.map((e) => e.toDouble()).toList(),
        fullAddress: widget.storeAddress,
      ),
      RoutePointDto(
        type: 'destination',
        // Yandex/backend expects [lon, lat] — keep this order in sync with
        // delivery-service/app/application/api/schemas/delivery.py.
        coordinates: [widget.shippingLng, widget.shippingLat],
        fullAddress: widget.shippingAddress,
      ),
    ];
  }

  Future<void> _create() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нужен телефон клиента')),
      );
      return;
    }

    // базовая валидация координат (иначе бэк/яндекс упадут)
    if (widget.storeCoordinates.length < 2 || widget.shippingLat == 0 || widget.shippingLng == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет координат для доставки/магазина')),
      );
      return;
    }

    final cubit = context.read<DeliveryCubit>();

    final dto = CreateClaimRequestDto(
      orderId: widget.orderId,
      storeId: widget.storeId,
      totalAmount: widget.totalAmount,
      requestId: "${cubit.newRequestId()}",
      tariffCode: widget.defaultTariffCode,
      items: widget.items,
      routePoints: _routePoints(),
      userPhone: phone,
      contactName: _name.text.trim().isEmpty ? null : _name.text.trim(),
    );

    await cubit.create(dto);
  }

  Future<void> _acceptClaim(String claimId, int version) async {
    final cubit = context.read<DeliveryCubit>();
    await cubit.accept(claimId, version, widget.orderId);
    if (!mounted) return;
    final failed = cubit.state is DeliveryError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failed ? 'Не удалось принять заявку' : 'Курьер принят')),
    );
  }

  // Cancelling a live Yandex claim is destructive + can cost the store money
  // (`cancelled_with_payment` if the courier is already dispatched). Every
  // other destructive action in the app confirms — this one must too. Confirm
  // first, then act, then give explicit success/fail feedback so the manager
  // doesn't re-tap into a double-cancel.
  Future<void> _confirmAndCancel(String claimId, int version) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Отменить доставку?'),
        content: const Text(
            'Курьер Яндекса будет отменён. Если курьер уже в пути, отмена может быть платной.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Отменить доставку'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cubit = context.read<DeliveryCubit>();
    await cubit.cancelFlow(claimId, version, widget.orderId);
    if (!mounted) return;
    final failed = cubit.state is DeliveryError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failed ? 'Не удалось отменить доставку' : 'Доставка отменена')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: BlocBuilder<DeliveryCubit, DeliveryState>(
          builder: (ctx, st) {
            final loading = st is DeliveryLoading;

            // The DeliveryCubit is app-scoped (singleton) and carries the
            // orderId in its state. Push tap-routing can stack a 2nd order
            // detail on top of this one and leave the cubit in the SIBLING
            // order's state; when this (preserved) section rebuilds it would
            // otherwise render + let the manager accept/cancel the WRONG
            // order's live courier. If the current state belongs to a
            // different order, re-init for OUR order and show a loader.
            final stOrderId = st is DeliveryReady
                ? st.orderId
                : st is DeliveryNoClaim
                    ? st.orderId
                    : st is DeliveryTariffs
                        ? st.orderId
                        : null;
            if (stOrderId != null && stOrderId != widget.orderId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  context.read<DeliveryCubit>().initByOrder(widget.orderId);
                }
              });
              return const SizedBox(
                height: 88,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }

            final header = Row(
              children: [
                Text('Яндекс.Доставка', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (loading)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            );

            // 1) Если заявка есть — управление
            if (st is DeliveryReady) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 8),
                  Text(
                    'Статус: ${_yandexStatusRu(st.status)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text('Стоимость: ${st.price} ${st.currency}'),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    title: const Text('Технические детали', style: TextStyle(fontSize: 12)),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          'claim_id: ${st.claimId}\nversion: ${st.version}',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: loading
                            ? null
                            : () => context.read<DeliveryCubit>().refresh(st.claimId, widget.orderId),
                        child: const Text('Обновить статус'),
                      ),
                      if (!_isTerminalYandexStatus(st.status))
                        ElevatedButton(
                          onPressed: loading
                              ? null
                              : () => _acceptClaim(st.claimId, st.version),
                          child: const Text('Принять'),
                        ),
                      if (!_isTerminalYandexStatus(st.status))
                        OutlinedButton(
                          onPressed: loading
                              ? null
                              : () => _confirmAndCancel(st.claimId, st.version),
                          child: const Text('Отменить'),
                        ),
                      OutlinedButton(
                        onPressed: loading
                            ? null
                            : () => context.read<DeliveryCubit>().loadCourierLink(widget.orderId, st.claimId),
                        child: const Text('Ссылка курьера'),
                      ),
                      // Re-request a fresh courier when the prior claim
                      // ended in a terminal state (cancelled, taxi
                      // cancelled, performer not found, etc.). Backend
                      // (delivery-service.create_claim) now allows this
                      // — it inserts a new row with a fresh Yandex
                      // claim_id; get_by_order_id returns the latest
                      // so subsequent UI reads pick up the new one.
                      if (_isTerminalYandexStatus(st.status))
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEE6F00),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: loading ? null : _create,
                          label: const Text('Заново вызвать курьера'),
                        ),
                    ],
                  ),
                  if (st.courierLink != null) ...[
                    const SizedBox(height: 8),
                    // Primary action: open the courier's live position on a
                    // Yandex map inside the app. Matches the customer-app
                    // pattern (CourierTrackingPage) so admin sees the same
                    // view the customer does.
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Открыть карту курьера'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CourierMapPage(
                                url: st.courierLink!,
                                orderId: widget.orderId,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              st.courierLink!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Скопировать',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: st.courierLink!));
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Ссылка скопирована'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            }

            // 2) Если нет заявки — форма Create.
            // Summary card up top so the admin sees what addresses and
            // contents will be sent to Yandex before tapping Create.
            // Previously the form only showed phone + name fields and
            // admins thought no address was being passed — it was, just
            // hidden in widget.shippingAddress / widget.storeAddress.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 8),
                const Text('Заявка не создана.'),
                const SizedBox(height: 12),

                _SummaryCard(
                  storeAddress: widget.storeAddress,
                  deliveryAddress: widget.shippingAddress,
                  itemsCount: widget.items.length,
                  totalAmount: widget.totalAmount,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Телефон клиента',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Имя получателя (опционально)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : _create,
                    child: const Text('Создать заявку'),
                  ),
                ),

                if (st is DeliveryError) ...[
                  const SizedBox(height: 8),
                  Text(st.message, style: const TextStyle(color: Colors.red)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// What gets sent to Yandex on "Создать заявку" — addresses come from
/// the order/store, not from any form field the admin has to fill in.
/// Rendering them here keeps the admin from thinking "I haven't filled
/// in the address" and adds trust to the auto-fill.
class _SummaryCard extends StatelessWidget {
  final String storeAddress;
  final String deliveryAddress;
  final int itemsCount;
  final double totalAmount;

  const _SummaryCard({
    required this.storeAddress,
    required this.deliveryAddress,
    required this.itemsCount,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(theme, Icons.store_outlined, 'Откуда', storeAddress),
          const SizedBox(height: 8),
          _row(theme, Icons.location_on_outlined, 'Куда', deliveryAddress),
          const SizedBox(height: 8),
          _row(theme, Icons.shopping_basket_outlined, 'Товары',
              '$itemsCount шт · ${formatTenge(totalAmount)}'),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// A самовывоз order should never have a Yandex courier attached to it, and
/// the new build makes that impossible: the whole [YandexDeliverySection] is
/// replaced by «курьер не нужен» copy on pickup orders.
///
/// That is exactly the problem. The admin app ships through TestFlight, so
/// there is no way to force every iPad onto the new build at once. An older
/// build does not understand `fulfillment_type` at all — it renders a pickup
/// order as an ordinary delivery and will happily dispatch a courier for it.
/// The courier then drives to an address the customer never intends to be at,
/// and the manager who opens that same order on an UPDATED iPad sees only
/// «курьер не нужен»: the live claim is invisible and there is no button that
/// can stop it.
///
/// So this panel exists to make a stray claim visible and cancellable, and
/// deliberately does nothing else — no create, no accept, no re-dispatch.
/// Bringing a courier back to a pickup order is never the right answer, and
/// an admin who is handed that button will eventually press it.
///
/// Renders NOTHING in the normal case (no claim), which is every pickup order
/// created by a current build.
class PickupStrayClaimPanel extends StatelessWidget {
  final int orderId;

  const PickupStrayClaimPanel({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    // Its OWN DeliveryCubit, not the app-wide one, and this is load-bearing.
    //
    // The shared cubit's "is this state mine?" guard keys on an orderId that
    // only the SUCCESS states carry — DeliveryReady, DeliveryNoClaim,
    // DeliveryTariffs. DeliveryError and DeliveryLoading carry none, so the
    // guard reads null and lets them through. Writing into the shared cubit
    // from a pickup order therefore had a real cost: open delivery order #200
    // with a live courier, get a pickup order pushed on top, let its lookup
    // fail on a flaky store connection, pop back to #200 — its section never
    // re-inits, sees DeliveryError, and renders «Заявка не создана» with
    // «Создать заявку» ENABLED. delivery-service has no existing-active-claim
    // gate, so the second tap dispatches a SECOND courier to a customer who
    // already has one, at ~1,774₸ each.
    //
    // Scoping the cubit to this panel removes the shared-state question
    // entirely rather than adding a second guard that the next state class
    // will forget to satisfy.
    return BlocProvider<DeliveryCubit>(
      create: (_) => DeliveryCubit(repo: context.read<DeliveryRepository>())
        ..initByOrder(orderId),
      child: _PickupStrayClaimView(orderId: orderId),
    );
  }
}

/// A самовывоз order should never have a Yandex courier attached to it, and
/// the new build makes that impossible: the whole [YandexDeliverySection] is
/// replaced by «курьер не нужен» copy on pickup orders.
///
/// That is exactly the problem. The admin app ships through TestFlight, so
/// there is no way to force every iPad onto the new build at once. An older
/// build does not understand `fulfillment_type` at all — it renders a pickup
/// order as an ordinary delivery and will happily dispatch a courier for it.
/// The courier then drives to an address the customer never intends to be at,
/// and the manager who opens that same order on an UPDATED iPad sees only
/// «курьер не нужен»: the live claim is invisible and there is no button that
/// can stop it.
///
/// So this panel exists to make a stray claim visible and cancellable, and
/// deliberately does nothing else — no create, no accept, no re-dispatch.
/// Bringing a courier back to a pickup order is never the right answer, and
/// an admin who is handed that button will eventually press it.
///
/// Renders NOTHING in the normal case (no claim), which is every pickup order
/// created by a current build.
class _PickupStrayClaimView extends StatefulWidget {
  final int orderId;

  const _PickupStrayClaimView({required this.orderId});

  @override
  State<_PickupStrayClaimView> createState() => _PickupStrayClaimViewState();
}

class _PickupStrayClaimViewState extends State<_PickupStrayClaimView> {
  /// The last live claim this panel saw.
  ///
  /// Kept because a failed cancel emits DeliveryError, which is not a
  /// DeliveryReady — so rendering straight off the current state made the
  /// whole red panel VANISH at the exact moment it mattered, while the
  /// courier was still en route and the only control that could stop it had
  /// just disappeared. The manager's only recovery was to leave the screen
  /// and come back, which is not a discoverable move.
  DeliveryReady? _lastLive;

  bool _cancelling = false;

  Future<void> _confirmAndCancel(String claimId, int version) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Отменить курьера?'),
        content: const Text(
            'Это заказ на самовывоз, курьер ему не нужен. Заявка в Яндексе будет отменена. '
            'Если курьер уже выехал, отмена может быть платной.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Отменить курьера'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    final cubit = context.read<DeliveryCubit>();
    await cubit.cancelFlow(claimId, version, widget.orderId);
    if (!mounted) return;
    setState(() => _cancelling = false);
    final failed = cubit.state is DeliveryError;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed
          // Deliberately not «Не удалось отменить курьера». cancelFlow wraps
          // the cancel AND the follow-up refresh in one try, so a cancel that
          // SUCCEEDED and then failed to re-read reports as a failure. Telling
          // the manager it definitely did not work would send them tapping
          // again; telling them to check is the honest instruction.
          ? 'Не удалось подтвердить отмену. Проверьте статус заявки.'
          : 'Курьер отменён'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeliveryCubit, DeliveryState>(
      builder: (context, st) {
        if (st is DeliveryReady && st.orderId == widget.orderId) {
          // An already-cancelled claim is not a live courier. Showing a red
          // alarm for it would train managers to ignore the panel.
          _lastLive = _isTerminalYandexStatus(st.status) ? null : st;
        } else if (st is DeliveryNoClaim && st.orderId == widget.orderId) {
          _lastLive = null;
        }

        final live = _lastLive;
        if (live == null) return const SizedBox.shrink();

        final failed = st is DeliveryError;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'На заказе самовывоза есть курьер',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Заявка создана в старой версии приложения. Статус: '
                '${_yandexStatusRu(live.status)}. Курьера нужно отменить, '
                'покупатель заберёт заказ сам.',
                style: const TextStyle(fontSize: 13),
              ),
              if (failed) ...[
                const SizedBox(height: 8),
                Text(
                  st.message,
                  style: const TextStyle(fontSize: 13, color: Colors.red),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                // After a failure this becomes «Обновить статус», NOT a retry.
                //
                // Yandex uses optimistic concurrency: `version` is captured
                // when the panel loads, and the courier accepting the claim
                // bumps it. A retry that replays the captured version fails
                // for exactly the same reason, forever — and because the error
                // branch never refreshes `_lastLive`, nothing in the panel can
                // ever recover. The manager's only escape was to leave the
                // screen, which nobody discovers, while an uncancellable
                // courier drives to a customer who is not there. That is the
                // infinite-retry dead end that got 1.9.0 archived.
                //
                // It also fixes the opposite face: `cancelFlow` wraps the
                // cancel AND the follow-up refresh in one try, so a cancel
                // that SUCCEEDED and then failed to re-read also lands here.
                // Re-reading resolves that honestly — the claim comes back
                // terminal and the panel disappears on its own.
                child: OutlinedButton.icon(
                  onPressed: _cancelling
                      ? null
                      : failed
                          ? () => context
                              .read<DeliveryCubit>()
                              .initByOrder(widget.orderId)
                          : () => _confirmAndCancel(live.claimId, live.version),
                  icon: _cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(failed ? Icons.refresh_rounded : Icons.cancel_outlined,
                          size: 18),
                  label: Text(failed ? 'Обновить статус' : 'Отменить курьера'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
