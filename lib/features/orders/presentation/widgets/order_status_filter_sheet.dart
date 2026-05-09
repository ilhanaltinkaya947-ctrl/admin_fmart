import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/orders_repository.dart';
import '../../models/order_models.dart';

/// Bottom sheet that fetches order statuses from the backend and lets the
/// user multi-select. Returns the selected ids on confirm, `null` on cancel.
class OrderStatusFilterSheet extends StatefulWidget {
  final List<int> initialSelected;
  const OrderStatusFilterSheet({super.key, required this.initialSelected});

  static Future<List<int>?> show(
    BuildContext context, {
    required List<int> initialSelected,
  }) {
    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OrderStatusFilterSheet(initialSelected: initialSelected),
    );
  }

  @override
  State<OrderStatusFilterSheet> createState() => _OrderStatusFilterSheetState();
}

class _OrderStatusFilterSheetState extends State<OrderStatusFilterSheet> {
  late final Future<OrderStatusesResponse> _future;
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected.toSet();
    _future = context.read<OrdersRepository>().getOrderStatuses();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Статус заказа',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _selected.clear()),
                        child: const Text('Сбросить'),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: FutureBuilder<OrderStatusesResponse>(
                  future: _future,
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snap.hasError || snap.data == null) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Не удалось загрузить статусы')),
                      );
                    }
                    final statuses = snap.data!.items;
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: statuses.length,
                      itemBuilder: (_, i) {
                        final s = statuses[i];
                        final selected = _selected.contains(s.id);
                        final ru = orderStatusRu(s.statusName);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(s.id);
                              } else {
                                _selected.remove(s.id);
                              }
                            });
                          },
                          title: Text(ru),
                          subtitle: ru == s.statusName
                              ? null
                              : Text(
                                  s.statusName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_selected.toList()),
                        child: Text(
                          _selected.isEmpty
                              ? 'Применить'
                              : 'Применить (${_selected.length})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
