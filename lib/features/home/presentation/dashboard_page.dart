import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/format/money.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/models/order_models.dart' show orderStatusRu;

/// Admin first-tab dashboard: today's KPIs for the currently-selected
/// store. One round-trip to /admin/dashboard/today returns total count,
/// non-cancelled revenue, and per-status breakdown. Tap "Обновить" or
/// pull-to-refresh to re-fetch.
///
/// [onDrillToOrders] is called when the operator taps a KPI tile or a
/// status row — null statusName means "just show me all orders", a
/// non-null name means "filter to this status". Wired in HomeShell to
/// flip the nav rail to the orders tab and apply the filter via the
/// shared OrdersCubit so the drill-down lands on the right view.
class DashboardPage extends StatefulWidget {
  final int storeId;
  final String storeName;
  final void Function({String? statusName})? onDrillToOrders;
  const DashboardPage({
    super.key,
    required this.storeId,
    required this.storeName,
    this.onDrillToOrders,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;
  DateTime? _lastUpdated;

  /// Periodic re-fetch so the wall-mounted iPad doesn't show stale numbers
  /// hours after the morning glance. Paused when the app is backgrounded
  /// (same lifecycle pattern as the order-detail polling) to avoid
  /// burning cellular while the screen is off.
  Timer? _refreshTimer;
  static const _refreshInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant DashboardPage old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId) {
      _load();
      _startRefreshTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_refreshTimer == null && mounted) {
        // Operator just unlocked — refresh once immediately so they see
        // fresh numbers instead of stale ones for the next minute.
        _load();
        _startRefreshTimer();
      }
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _load());
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
      setState(() {
        _data = data;
        _lastUpdated = DateTime.now();
      });
    } catch (_) {
      // Keep showing the last-good data on a transient blip — the
      // periodic refresh will recover within _refreshInterval. Only
      // surface the error banner when we have NOTHING to show yet (a
      // true initial-load failure), so a momentary upstream hiccup
      // (e.g. the rare /admin/dashboard/today 502 seen 2026-06-22)
      // doesn't flash a scary "Не удалось загрузить сводку" over an
      // otherwise-fine dashboard.
      if (mounted) {
        setState(() => _error = _data == null ? 'Не удалось загрузить сводку' : null);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Short Russian "обновлено …" string under the title. Refreshes every
  /// build so once a minute passes after the last successful fetch the
  /// stamp ticks over without any extra timer.
  String _freshnessLabel() {
    final ts = _lastUpdated;
    if (ts == null) return '';
    final mins = DateTime.now().difference(ts).inMinutes;
    if (mins <= 0) return 'обновлено только что';
    if (mins == 1) return 'обновлено 1 мин назад';
    if (mins < 60) return 'обновлено $mins мин назад';
    final hrs = mins ~/ 60;
    return 'обновлено $hrs ч назад';
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
            if (_lastUpdated != null) ...[
              Row(
                children: [
                  Icon(Icons.schedule, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    _freshnessLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
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
                    onTap: widget.onDrillToOrders == null
                        ? null
                        : () => widget.onDrillToOrders!(),
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
                    onTap: widget.onDrillToOrders == null
                        ? null
                        : () => widget.onDrillToOrders!(),
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
                onTapStatus: widget.onDrillToOrders == null
                    ? null
                    : (name) => widget.onDrillToOrders!(statusName: name),
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
  final VoidCallback? onTap;
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.grey.shade400,
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
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  final Map<String, dynamic> byStatus;
  final void Function(String statusName)? onTapStatus;
  const _StatusBreakdown({required this.byStatus, this.onTapStatus});

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
    // Sort by count desc so the biggest buckets surface first. Use
    // (v as num).toInt() defensively — if the backend ever sends a
    // float-typed bucket value, plain `as int` would throw and blank
    // the whole dashboard.
    final entries = byStatus.entries.toList()
      ..sort((a, b) => ((b.value as num?)?.toInt() ?? 0)
          .compareTo((a.value as num?)?.toInt() ?? 0));
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${(e.value as num?)?.toInt() ?? 0}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  if (onTapStatus != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ],
              ),
              onTap: onTapStatus == null ? null : () => onTapStatus!(e.key),
            ),
          ),
      ],
    );
  }
}
