import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/format/money.dart';
import '../../orders/models/order_models.dart';
import '../data/customers_repository.dart';
import '../models/customer_note.dart';
import '../../orders/presentation/order_details_page.dart';
import '../data/customers_repository.dart';
import '../state/customer_detail_cubit.dart';

class CustomerDetailPage extends StatelessWidget {
  final int customerId;
  final int storeId;
  final String? fallbackName;

  const CustomerDetailPage({
    super.key,
    required this.customerId,
    required this.storeId,
    this.fallbackName,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => CustomerDetailCubit(
        repository: ctx.read<CustomersRepository>(),
      )..load(customerId: customerId, storeId: storeId),
      child: _CustomerDetailScaffold(
        customerId: customerId,
        storeId: storeId,
        fallbackName: fallbackName,
      ),
    );
  }
}

class _CustomerDetailScaffold extends StatelessWidget {
  final int customerId;
  final int storeId;
  final String? fallbackName;

  const _CustomerDetailScaffold({
    required this.customerId,
    required this.storeId,
    this.fallbackName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fallbackName ?? 'Клиент #$customerId'),
        actions: [
          IconButton(
            onPressed: () => context
                .read<CustomerDetailCubit>()
                .load(customerId: customerId, storeId: storeId),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocBuilder<CustomerDetailCubit, CustomerDetailState>(
        builder: (ctx, state) {
          if (state is CustomerDetailLoading ||
              state is CustomerDetailInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is CustomerDetailFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ctx
                        .read<CustomerDetailCubit>()
                        .load(customerId: customerId, storeId: storeId),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }
          if (state is CustomerDetailLoaded) {
            return _Body(
              customer: state.customer,
              orders: state.orders,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final CustomerInfo customer;
  final OrdersPage orders;

  const _Body({required this.customer, required this.orders});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final stats = _aggregateStats(orders.items);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ProfileCard(customer: customer),
        const SizedBox(height: 12),
        _StatsRow(
          totalOrders: orders.pagination.total,
          totalSpend: stats.totalSpend,
          lastOrderAt: stats.lastOrderAt,
        ),
        const SizedBox(height: 16),
        _NotesSection(customerId: customer.id),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'История заказов',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Всего: ${orders.pagination.total}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (orders.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('У клиента нет заказов в этом магазине')),
          )
        else
          ...orders.items.map((o) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text('Заказ #${o.id} — ${orderStatusRu(o.status)}'),
                  subtitle: Text(
                    '${df.format(o.createdAt.toLocal())}\n${o.deliveryAddress}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    formatTenge(o.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailsPage(order: o),
                    ),
                  ),
                ),
              )),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final CustomerInfo customer;
  const _ProfileCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    _initials(customer),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.fullName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '#${customer.id} · ${customer.role}',
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _kv('Телефон', customer.phone),
            if (customer.email != null && customer.email!.isNotEmpty)
              _kv('Email', customer.email!),
            _kv('Роль', customer.role.isEmpty ? '—' : customer.role),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  String _initials(CustomerInfo c) {
    final fn = (c.firstName ?? '').trim();
    final ln = (c.lastName ?? '').trim();
    final a = fn.isNotEmpty ? fn[0] : '';
    final b = ln.isNotEmpty ? ln[0] : '';
    final init = (a + b).toUpperCase();
    if (init.isNotEmpty) return init;
    final phone = c.phone.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) return '?';
    return phone.length >= 2 ? phone.substring(phone.length - 2) : phone;
  }
}

class _StatsRow extends StatelessWidget {
  final int totalOrders;
  final double totalSpend;
  final DateTime? lastOrderAt;

  const _StatsRow({
    required this.totalOrders,
    required this.totalSpend,
    required this.lastOrderAt,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy');
    return Row(
      children: [
        Expanded(child: _StatCard(label: 'Заказов', value: '$totalOrders')),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Сумма',
            value: formatTenge(totalSpend.round()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Последний',
            value: lastOrderAt != null
                ? df.format(lastOrderAt!.toLocal())
                : '—',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AggregateStats {
  final double totalSpend;
  final DateTime? lastOrderAt;
  _AggregateStats({required this.totalSpend, required this.lastOrderAt});
}

_AggregateStats _aggregateStats(List<Order> orders) {
  double total = 0;
  DateTime? last;
  for (final o in orders) {
    total += double.tryParse(o.totalAmount) ?? 0;
    if (last == null || o.createdAt.isAfter(last)) {
      last = o.createdAt;
    }
  }
  return _AggregateStats(totalSpend: total, lastOrderAt: last);
}

/// Staff-internal notes section on the customer detail page. Loads its
/// own data so the surrounding screen doesn't have to pass anything in,
/// and so it can refresh independently after a save/delete.
class _NotesSection extends StatefulWidget {
  final int customerId;
  const _NotesSection({required this.customerId});

  @override
  State<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<_NotesSection> {
  List<CustomerNote> _notes = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<CustomersRepository>();
      final list = await repo.listNotes(widget.customerId);
      if (!mounted) return;
      setState(() => _notes = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось загрузить заметки');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Новая заметка'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Внутренний комментарий…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (body == null || body.isEmpty) return;

    try {
      final repo = context.read<CustomersRepository>();
      final created = await repo.createNote(widget.customerId, body);
      if (!mounted) return;
      setState(() => _notes = [created, ..._notes]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить заметку')),
      );
    }
  }

  Future<void> _delete(CustomerNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Действие необратимо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final repo = context.read<CustomersRepository>();
      await repo.deleteNote(widget.customerId, note.id);
      if (!mounted) return;
      setState(() => _notes = _notes.where((n) => n.id != note.id).toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                'Заметки',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_notes.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '(${_notes.length})',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'Добавить',
                icon: const Icon(Icons.add),
                onPressed: _addNote,
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade400, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!)),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _load,
                ),
              ],
            ),
          ),
        if (!_loading && _error == null && _notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'Заметок пока нет.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        for (final n in _notes)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.body),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${df.format(n.createdAt.toLocal())} · #${n.createdBy}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Удалить',
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _delete(n),
                        icon: Icon(Icons.delete_outline,
                            color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
