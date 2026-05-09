import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../data/orders_repository.dart';
import '../../models/order_models.dart';

/// Self-contained section showing the audit timeline for one order.
/// Holds its own fetch state so the parent page doesn't need to coordinate it.
class OrderTimelineSection extends StatefulWidget {
  final int orderId;
  const OrderTimelineSection({super.key, required this.orderId});

  @override
  State<OrderTimelineSection> createState() => OrderTimelineSectionState();
}

class OrderTimelineSectionState extends State<OrderTimelineSection> {
  Future<OrderEventsResponse>? _future;

  @override
  void initState() {
    super.initState();
    _refetch();
  }

  /// Public so the parent can refresh after a status change without holding
  /// a reference to the future.
  void refresh() => _refetch();

  void _refetch() {
    setState(() {
      _future =
          context.read<OrdersRepository>().getOrderEvents(orderId: widget.orderId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'История изменений',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Обновить',
              onPressed: _refetch,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FutureBuilder<OrderEventsResponse>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            if (snap.hasError) {
              return Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Не удалось загрузить историю',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: _refetch,
                    child: const Text('Повторить'),
                  ),
                ],
              );
            }
            final events = snap.data?.events ?? const <OrderEvent>[];
            if (events.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Событий пока нет',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < events.length; i++)
                  _TimelineRow(
                    event: events[i],
                    isFirst: i == 0,
                    isLast: i == events.length - 1,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final OrderEvent event;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 12,
                  color: isFirst
                      ? Colors.transparent
                      : theme.colorScheme.outlineVariant,
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        if (event.fromStatusDisplay != null)
                          TextSpan(
                            text: '${event.fromStatusDisplay} → ',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        TextSpan(
                          text: event.toStatusDisplay,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${df.format(event.createdAt.toLocal())}  ·  user #${event.changedBy}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (event.comment != null && event.comment!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.comment!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
