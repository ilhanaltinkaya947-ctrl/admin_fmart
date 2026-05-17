import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/format/money.dart';
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: BlocBuilder<DeliveryCubit, DeliveryState>(
          builder: (ctx, st) {
            final loading = st is DeliveryLoading;

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
                      ElevatedButton(
                        onPressed: loading
                            ? null
                            : () => context.read<DeliveryCubit>().accept(st.claimId, st.version, widget.orderId),
                        child: const Text('Принять'),
                      ),
                      OutlinedButton(
                        onPressed: loading
                            ? null
                            : () => context.read<DeliveryCubit>().cancelFlow(st.claimId, st.version, widget.orderId),
                        child: const Text('Отменить'),
                      ),
                      OutlinedButton(
                        onPressed: loading
                            ? null
                            : () => context.read<DeliveryCubit>().loadCourierLink(widget.orderId, st.claimId),
                        child: const Text('Ссылка курьера'),
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
