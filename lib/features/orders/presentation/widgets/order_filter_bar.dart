import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../models/order_filters.dart';
import '../../state/orders_cubit.dart';
import 'order_status_filter_sheet.dart';

class OrderFilterBar extends StatefulWidget {
  const OrderFilterBar({super.key});

  @override
  State<OrderFilterBar> createState() => _OrderFilterBarState();
}

class _OrderFilterBarState extends State<OrderFilterBar> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = context.read<OrdersCubit>().filters.search;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersCubit, OrdersState>(
      buildWhen: (prev, curr) {
        final p = prev is OrdersLoaded ? prev.filters : OrderFilters.empty;
        final c = curr is OrdersLoaded ? curr.filters : OrderFilters.empty;
        return p != c;
      },
      builder: (ctx, state) {
        final filters = state is OrdersLoaded
            ? state.filters
            : context.read<OrdersCubit>().filters;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => context.read<OrdersCubit>().setSearchQuery(v),
                decoration: InputDecoration(
                  hintText: 'Поиск по № заказа или адресу',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: filters.search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            context.read<OrdersCubit>().setSearchQuery('');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _Chip(
                      label: _dateLabel(filters),
                      active: filters.dateFrom != null || filters.dateTo != null,
                      onTap: () => _pickDate(ctx, filters),
                      onClear: (filters.dateFrom == null && filters.dateTo == null)
                          ? null
                          : () => ctx.read<OrdersCubit>().applyFilters(
                                filters.copyWith(
                                  clearDateFrom: true,
                                  clearDateTo: true,
                                ),
                              ),
                    ),
                    const SizedBox(width: 8),
                    _Chip(
                      label: filters.statusIds.isEmpty
                          ? 'Статус'
                          : 'Статус (${filters.statusIds.length})',
                      active: filters.statusIds.isNotEmpty,
                      onTap: () => _pickStatus(ctx, filters),
                      onClear: filters.statusIds.isEmpty
                          ? null
                          : () => ctx.read<OrdersCubit>().applyFilters(
                                filters.copyWith(statusIds: const []),
                              ),
                    ),
                    if (!filters.isEmpty) ...[
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.clear, size: 16),
                        label: const Text('Сбросить всё'),
                        onPressed: () => ctx.read<OrdersCubit>().clearFilters(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _dateLabel(OrderFilters f) {
    if (f.dateFrom == null && f.dateTo == null) return 'Дата';
    final df = DateFormat('dd.MM');
    final from = f.dateFrom != null ? df.format(f.dateFrom!.toLocal()) : '';
    final to = f.dateTo != null ? df.format(f.dateTo!.toLocal()) : '';
    if (from.isNotEmpty && to.isNotEmpty) return '$from–$to';
    if (from.isNotEmpty) return 'с $from';
    return 'до $to';
  }

  Future<void> _pickDate(BuildContext context, OrderFilters current) async {
    final now = DateTime.now();
    final initial = (current.dateFrom != null && current.dateTo != null)
        ? DateTimeRange(start: current.dateFrom!, end: current.dateTo!)
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      locale: const Locale('ru'),
    );
    if (picked == null || !context.mounted) return;
    // Inclusive end-of-day for dateTo so orders on the picked day are included.
    final dateTo = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
      23,
      59,
      59,
    );
    context.read<OrdersCubit>().applyFilters(
          current.copyWith(dateFrom: picked.start, dateTo: dateTo),
        );
  }

  Future<void> _pickStatus(BuildContext context, OrderFilters current) async {
    final selected = await OrderStatusFilterSheet.show(
      context,
      initialSelected: current.statusIds,
    );
    if (selected == null || !context.mounted) return;
    context.read<OrdersCubit>().applyFilters(
          current.copyWith(statusIds: selected),
        );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      avatar: Icon(
        active ? Icons.check : Icons.tune,
        size: 16,
        color: active
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: onTap,
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 16),
      backgroundColor: active
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      labelStyle: TextStyle(
        color: active
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface,
        fontSize: 13,
      ),
      deleteIconColor: active
          ? Theme.of(context).colorScheme.onPrimary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
