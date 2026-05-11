import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/format/money.dart';
import '../../delivery/models/delivery_models.dart';
import '../data/orders_repository.dart';
import '../models/order_models.dart';
import '../../stores/state/store_cubit.dart';
import '../../delivery/presentation/delivery_section.dart';
import 'widgets/order_item_card.dart';
import 'widgets/order_timeline_section.dart';

class OrderDetailsPage extends StatefulWidget {
  final Order order;
  const OrderDetailsPage({super.key, required this.order});

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  late Order _order;

  final _reasonCtrl = TextEditingController();

  bool _saving = false;
  bool _actionLoading = false;
  String? _error;

  List<OrderStatusDto> _statuses = [];
  bool _statusesLoading = false;
  String? _selectedStatus;

  CustomerInfo? _customer;
  bool _customerLoading = false;
  bool _customerLoadFailed = false;

  final Set<int> _itemBusy = <int>{};

  final _timelineKey = GlobalKey<OrderTimelineSectionState>();

  bool get _itemsEditable {
    final s = _order.status.toLowerCase();
    return s == 'paid' || s == 'processing';
  }

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _selectedStatus = _order.status; // код
    _loadStatuses();
    _loadCustomer();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  double _parseMoney(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0.0;

  Future<void> _loadCustomer() async {
    final cid = _order.customerId;
    if (cid <= 0) return;

    setState(() {
      _customerLoading = true;
      _customerLoadFailed = false;
    });
    try {
      final repo = context.read<OrdersRepository>();
      final info = await repo.getCustomerInfo(customerId: cid);

      if (!mounted) return;
      setState(() => _customer = info);
    } catch (_) {
      if (mounted) setState(() => _customerLoadFailed = true);
    } finally {
      if (mounted) setState(() => _customerLoading = false);
    }
  }

  Future<void> _loadStatuses() async {
    setState(() {
      _statusesLoading = true;
      _error = null;
    });

    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.getOrderStatuses();

      final items = [...res.items]..sort((a, b) => a.id.compareTo(b.id));

      setState(() {
        _statuses = items;

        final exists = items.any((s) => s.statusName == _selectedStatus);
        if (!exists && items.isNotEmpty) {
          _selectedStatus = items.first.statusName;
        }
      });
    } catch (_) {
      setState(() => _error = 'Не удалось загрузить список статусов');
    } finally {
      if (mounted) setState(() => _statusesLoading = false);
    }
  }


  Future<void> _changeStatus() async {
    final status = (_selectedStatus ?? '').trim();
    if (status.isEmpty) {
      setState(() => _error = 'Выбери статус');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = context.read<OrdersRepository>();
      await repo.changeStatus(
        orderId: _order.id,
        status: status, // отправляем код
        reason: _reasonCtrl.text.trim(),
      );

      setState(() => _order = _order.copyWith(status: status));
      _timelineKey.currentState?.refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Статус обновлён')));
    } catch (_) {
      setState(() => _error = 'Не удалось обновить статус');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: Text('Заказ #${_order.id} будет отменён.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Нет')),
          ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Отменить')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.cancelOrder(orderId: _order.id);

      if (!mounted) return;
      if (res.success) {
        setState(() => _order = _order.copyWith(status: 'canceled'));
        _timelineKey.currentState?.refresh();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message.isNotEmpty ? res.message : (res.success ? 'Заказ отменён' : 'Не удалось отменить'))),
      );
    } catch (_) {
      setState(() => _error = 'Не удалось отменить заказ');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _openRefundSheet() async {
    final total = _parseMoney(_order.totalAmount);

    final amountCtrl = TextEditingController(text: total.toStringAsFixed(2));
    final reasonCtrl = TextEditingController();

    final result = await showModalBottomSheet<_RefundPayload>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(c).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Возврат по заказу #${_order.id}', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Сумма возврата',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Причина возврата',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(c).pop(null),
                      child: const Text('Закрыть'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final amount = double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                        final reason = reasonCtrl.text.trim();

                        // жёсткая валидация — иначе будет мусор в бэке
                        if (amount <= 0) {
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Сумма должна быть > 0')));
                          return;
                        }
                        if (amount > total + 0.0001) {
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Сумма больше суммы заказа')));
                          return;
                        }
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Нужна причина возврата')));
                          return;
                        }

                        Navigator.of(c).pop(_RefundPayload(amount: amount, reason: reason));
                      },
                      child: const Text('Оформить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    amountCtrl.dispose();
    reasonCtrl.dispose();

    if (result == null) return;

    await _refundOrder(amount: result.amount, reason: result.reason);
  }

  Future<void> _changeItemQty(OrderItem item, int newQty) async {
    if (newQty < 1) return;
    if (_itemBusy.contains(item.id)) return;
    setState(() => _itemBusy.add(item.id));
    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.updateItemQty(
        orderId: _order.id,
        itemId: item.id,
        qty: newQty,
      );
      if (!mounted) return;
      final updatedItems = _order.items
          .map((it) => it.id == item.id
              ? it.copyWith(
                  qty: res.newQty ?? newQty,
                  total: res.newTotal.toStringAsFixed(2),
                )
              : it)
          .toList();
      setState(() {
        _order = _order.copyWith(
          items: updatedItems,
          totalAmount: (res.subtotal + res.deliverySum).toStringAsFixed(2),
        );
      });
      _timelineKey.currentState?.refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось изменить количество')),
      );
    } finally {
      if (mounted) setState(() => _itemBusy.remove(item.id));
    }
  }

  Future<void> _removeItem(OrderItem item) async {
    if (_itemBusy.contains(item.id)) return;
    if (_order.items.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нельзя удалить последний товар. Отмените заказ.'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(item.product.name ?? 'Товар ${item.productId}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _itemBusy.add(item.id));
    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.removeItem(
        orderId: _order.id,
        itemId: item.id,
      );
      if (!mounted) return;
      final updatedItems =
          _order.items.where((it) => it.id != item.id).toList();
      setState(() {
        _order = _order.copyWith(
          items: updatedItems,
          totalAmount: (res.subtotal + res.deliverySum).toStringAsFixed(2),
        );
      });
      _timelineKey.currentState?.refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить товар')),
      );
    } finally {
      if (mounted) setState(() => _itemBusy.remove(item.id));
    }
  }

  Future<void> _refundOrder({required double amount, required String reason}) async {
    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      final repo = context.read<OrdersRepository>();
      // Generated once per refund attempt — if the network blips and we
      // retry transparently elsewhere (or the admin re-taps), the same
      // key gets sent so the backend can dedupe (planned). Without this
      // a timeout + retry would risk two refunds.
      final idempotencyKey = const Uuid().v4();
      final res = await repo.refundOrder(
        orderId: _order.id,
        amount: amount,
        reason: reason,
        idempotencyKey: idempotencyKey,
      );

      if (!mounted) return;
      if (res.success) {
        final orderTotal = _parseMoney(_order.totalAmount);
        // If the refunded amount covers the whole order it's a full refund;
        // otherwise the backend keeps it in partially-refunded.
        final newStatus = (amount + 0.0001 >= orderTotal) ? 'refunded' : 'partially-refunded';
        setState(() => _order = _order.copyWith(status: newStatus));
        _timelineKey.currentState?.refresh();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message.isNotEmpty ? res.message : (res.success ? 'Возврат оформлен' : 'Не удалось оформить возврат'))),
      );
    } catch (_) {
      setState(() => _error = 'Не удалось оформить возврат');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _order.items;

    final storeState = context.watch<StoreCubit>().state;
    final StoreSelected? selectedStore = storeState is StoreSelected ? storeState : null;

    final cargoItems = items
        .map((it) => CargoItemDto(productId: it.productId, qty: it.qty))
        .toList();

    final totalAmount = _parseMoney(_order.totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: Text('Заказ #${_order.id}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_order),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusBadge(status: _order.status),
          const SizedBox(height: 16),
          Text('Покупатель', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),

          if (_customerLoading) ...[
            const LinearProgressIndicator(minHeight: 2),
          ] else if (_customerLoadFailed) ...[
            Row(
              children: [
                const Icon(Icons.error_outline, size: 16, color: Colors.orange),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Не удалось загрузить данные покупателя',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Повторить',
                  onPressed: _loadCustomer,
                ),
              ],
            ),
          ] else ...[
            Text('Имя: ${_customer?.fullName ?? '—'}'),
            Text('Телефон: ${(_customer?.phone.isNotEmpty == true) ? _customer!.phone : '—'}'),
            if ((_customer?.email ?? '').trim().isNotEmpty)
              Text('Email: ${_customer!.email}'),
          ],

          const SizedBox(height: 8),
          Text('Адрес: ${_order.deliveryAddress}'),
          if (_order.customerComment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Комментарий: ${_order.customerComment}'),
          ],
          const SizedBox(height: 12),
          Text('Сумма: ${formatTenge(totalAmount)}',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          Text('Доставка: ${formatTenge(_parseMoney(_order.deliverySum))}'),
          const SizedBox(height: 16),

          if (selectedStore == null) ...[
            const Text('Магазин не выбран (или не загружены данные магазина).'),
          ] else ...[
            YandexDeliverySection(
              orderId: _order.id,
              storeId: _order.storeId,
              totalAmount: totalAmount,
              shippingLat: _order.shippingLat,
              shippingLng: _order.shippingLng,
              shippingAddress: _order.deliveryAddress,
              storeCoordinates: selectedStore.coordinates,
              storeAddress: selectedStore.storeAddress,
              items: cargoItems,
              customerPhone: _customer?.phone,
              customerName: (_customer == null) ? null : _customer!.fullName == '—' ? null : _customer!.fullName,
            ),
          ],

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          Text('Действия', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _actionLoading ? null : _cancelOrder,
                  icon: const Icon(Icons.close, size: 18),
                  label: _actionLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Отменить'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _actionLoading ? null : _openRefundSheet,
                  icon: const Icon(Icons.replay, size: 18),
                  label: _actionLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Возврат'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Товары',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${items.length} ${_pluralItems(items.length)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (!_itemsEditable) ...[
            const SizedBox(height: 4),
            Text(
              'Редактирование доступно только в статусах "Оплачен" и "В обработке"',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...items.map((it) => OrderItemCard(
                item: it,
                editable: _itemsEditable,
                busy: _itemBusy.contains(it.id),
                onQtyChange: (newQty) => _changeItemQty(it, newQty),
                onRemove: () => _removeItem(it),
              )),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          OrderTimelineSection(key: _timelineKey, orderId: _order.id),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          Text('Изменить статус', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Статус',
                    border: OutlineInputBorder(),
                  ),
                  items: _statuses
                      .map((s) => DropdownMenuItem<String>(
                    value: s.statusName,
                    child: Text(orderStatusRu(s.statusName)),
                  ))
                      .toList(),
                  onChanged: (_saving || _statusesLoading)
                      ? null
                      : (v) => setState(() => _selectedStatus = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Обновить список статусов',
                onPressed: _statusesLoading ? null : _loadStatuses,
                icon: _statusesLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
            ],
          ),

          const SizedBox(height: 8),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(labelText: 'Причина (необязательно)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _changeStatus,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundPayload {
  final double amount;
  final String reason;
  _RefundPayload({required this.amount, required this.reason});
}

String _pluralItems(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'товар';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'товара';
  return 'товаров';
}

/// Prominent colored status badge at the top of order detail — replaces
/// the old "Статус: X" plain text so admin can read order state from
/// across the room (iPad in the warehouse).
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  // Maps the backend status code to a (background, foreground, icon) tuple.
  static const _colors = <String, ({Color bg, Color fg, IconData icon})>{
    'pending-payment': (bg: Color(0xFFFFF4E5), fg: Color(0xFFAD6800), icon: Icons.hourglass_empty),
    'paid':            (bg: Color(0xFFE3F2FD), fg: Color(0xFF1565C0), icon: Icons.payments_outlined),
    'processing':      (bg: Color(0xFFE8EAF6), fg: Color(0xFF283593), icon: Icons.inventory_2_outlined),
    'ready-for-delivery': (bg: Color(0xFFE0F7FA), fg: Color(0xFF006064), icon: Icons.local_shipping_outlined),
    'delivering':      (bg: Color(0xFFFFF8E1), fg: Color(0xFFE65100), icon: Icons.directions_bike),
    'delivered':       (bg: Color(0xFFE8F5E9), fg: Color(0xFF2E7D32), icon: Icons.check_circle_outline),
    'completed':       (bg: Color(0xFFE8F5E9), fg: Color(0xFF2E7D32), icon: Icons.check_circle),
    'canceled':        (bg: Color(0xFFFFEBEE), fg: Color(0xFFC62828), icon: Icons.cancel_outlined),
    'refunded':        (bg: Color(0xFFFCE4EC), fg: Color(0xFFAD1457), icon: Icons.replay),
    'partially-refunded': (bg: Color(0xFFFCE4EC), fg: Color(0xFFAD1457), icon: Icons.replay_circle_filled_outlined),
    'payment-failed':  (bg: Color(0xFFFFEBEE), fg: Color(0xFFC62828), icon: Icons.error_outline),
  };

  @override
  Widget build(BuildContext context) {
    final c = _colors[status] ??
        (bg: Colors.grey.shade200, fg: Colors.grey.shade700, icon: Icons.help_outline);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(c.icon, color: c.fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              orderStatusRu(status),
              style: TextStyle(
                color: c.fg,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
