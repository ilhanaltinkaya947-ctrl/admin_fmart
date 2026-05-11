import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/format/money.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/models/order_models.dart' show orderStatusRu;

/// Admin first-tab dashboard: today's KPIs for the currently-selected
/// store. One round-trip to /admin/dashboard/today returns total count,
/// non-cancelled revenue, and per-status breakdown. Tap "Обновить" or
/// pull-to-refresh to re-fetch.
class DashboardPage extends StatefulWidget {
  final int storeId;
  final String storeName;
  const DashboardPage({super.key, required this.storeId, required this.storeName});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardPage old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<OrdersRepository>();
      final data = await repo.getDashboardToday(storeId: widget.storeId);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось загрузить сводку');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Сегодня — ${widget.storeName}'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: _KpiCard(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Заказов сегодня',
                    value: _loading
                        ? '…'
                        : '${(_data?['total'] as int?) ?? 0}',
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiCard(
                    icon: Icons.payments_outlined,
                    label: 'Выручка',
                    value: _loading
                        ? '…'
                        : formatTenge((_data?['revenue'] as num?) ?? 0),
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'По статусам',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_loading && _data == null)
              const LinearProgressIndicator(minHeight: 2)
            else
              _StatusBreakdown(
                byStatus: (_data?['by_status'] as Map?)?.cast<String, dynamic>() ?? const {},
              ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  final Map<String, dynamic> byStatus;
  const _StatusBreakdown({required this.byStatus});

  @override
  Widget build(BuildContext context) {
    if (byStatus.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Сегодня пока нет заказов.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    // Sort by count desc so the biggest buckets surface first.
    final entries = byStatus.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    return Column(
      children: [
        for (final e in entries)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 3),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: ListTile(
              dense: true,
              title: Text(orderStatusRu(e.key)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${e.value}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
