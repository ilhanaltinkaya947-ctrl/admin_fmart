import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/format/money.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/models/order_models.dart';

/// Admin Reports tab — sales-by-day line chart + top-10 products table.
/// One date range drives both reports; refreshing fetches both in parallel.
class ReportsPage extends StatefulWidget {
  final int storeId;
  final String storeName;

  const ReportsPage({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTimeRange _range;
  bool _loading = false;
  String? _error;
  SalesByDayResponse? _sales;
  TopProductsResponse? _top;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day - 29),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<OrdersRepository>();
      final results = await Future.wait([
        repo.getSalesByDay(
          storeId: widget.storeId,
          dateFrom: _range.start,
          dateTo: _range.end,
        ),
        repo.getTopProducts(
          storeId: widget.storeId,
          dateFrom: _range.start,
          dateTo: _range.end,
          limit: 10,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _sales = results[0] as SalesByDayResponse;
        _top = results[1] as TopProductsResponse;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить отчёт. Попробуйте обновить.';
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now(),
      locale: const Locale('ru'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _range = DateTimeRange(
          start: picked.start,
          end: DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
            23,
            59,
            59,
          ),
        ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчёты'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RangeBar(range: _range, onPick: _pickRange, storeName: widget.storeName),
            const SizedBox(height: 16),
            if (_error != null)
              _ErrorBox(message: _error!, onRetry: _load)
            else ...[
              _SectionCard(
                title: 'Выручка по дням',
                subtitle: _sales == null
                    ? null
                    : _buildSalesSummary(_sales!),
                child: _SalesChart(
                  loading: _loading,
                  response: _sales,
                  range: _range,
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Топ-10 товаров по выручке',
                child: _TopProductsTable(
                  loading: _loading,
                  response: _top,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _buildSalesSummary(SalesByDayResponse r) {
    if (r.rows.isEmpty) return 'Нет данных за выбранный период';
    final totalRevenue =
        r.rows.fold<double>(0, (acc, row) => acc + row.revenue);
    final totalOrders =
        r.rows.fold<int>(0, (acc, row) => acc + row.orderCount);
    return 'Заказов: $totalOrders · Выручка: ${formatTenge(totalRevenue)}';
  }
}

class _RangeBar extends StatelessWidget {
  final DateTimeRange range;
  final VoidCallback onPick;
  final String storeName;

  const _RangeBar({
    required this.range,
    required this.onPick,
    required this.storeName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM yyyy', 'ru');
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.store_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    storeName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${fmt.format(range.start)} — ${fmt.format(range.end)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.date_range),
              label: const Text('Период'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SalesChart extends StatelessWidget {
  final bool loading;
  final SalesByDayResponse? response;
  final DateTimeRange range;

  const _SalesChart({
    required this.loading,
    required this.response,
    required this.range,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && response == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (response == null || response!.rows.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Нет заказов за выбранный период',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Zero-fill missing days — fl_chart wants a continuous x-axis to
    // draw a meaningful line; gaps would otherwise compress visually.
    final byDate = <String, double>{
      for (final r in response!.rows)
        DateFormat('yyyy-MM-dd').format(r.date): r.revenue,
    };
    final days = <DateTime>[];
    final startDay = DateTime(range.start.year, range.start.month, range.start.day);
    final endDay = DateTime(range.end.year, range.end.month, range.end.day);
    for (var d = startDay;
        !d.isAfter(endDay);
        d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < days.length; i++) {
      final key = DateFormat('yyyy-MM-dd').format(days[i]);
      spots.add(FlSpot(i.toDouble(), byDate[key] ?? 0.0));
    }

    final maxY = spots.map((s) => s.y).fold<double>(0, (a, b) => a > b ? a : b);
    final yMax = maxY == 0 ? 1000.0 : maxY * 1.15;
    final theme = Theme.of(context);

    // Show at most ~6 x-axis labels so they don't overlap on iPhone.
    final step = (days.length / 6).ceil().clamp(1, days.length);
    final shortFmt = DateFormat('d MMM', 'ru');

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: yMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yMax / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                getTitlesWidget: (v, meta) {
                  if (v == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      _compactMoney(v),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: step.toDouble(),
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      shortFmt.format(days[i]),
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 2.5,
              color: theme.colorScheme.primary,
              dotData: FlDotData(show: spots.length <= 14),
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => touched.map((t) {
                final i = t.x.toInt();
                final label = (i >= 0 && i < days.length)
                    ? DateFormat('d MMM', 'ru').format(days[i])
                    : '';
                return LineTooltipItem(
                  '$label\n${formatTenge(t.y)}',
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _compactMoney(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }
}

class _TopProductsTable extends StatelessWidget {
  final bool loading;
  final TopProductsResponse? response;

  const _TopProductsTable({required this.loading, required this.response});

  @override
  Widget build(BuildContext context) {
    if (loading && response == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (response == null || response!.rows.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Нет продаж за выбранный период',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final rows = response!.rows;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _ProductRow(rank: i + 1, row: rows[i]),
          if (i < rows.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  final int rank;
  final TopProductRow row;

  const _ProductRow({required this.rank, required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          _Thumbnail(imageUrl: row.imageUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (row.sku != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    row.sku!,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatTenge(row.revenue),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                '${row.qty} шт',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? imageUrl;
  const _Thumbnail({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.shopping_basket_outlined,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
