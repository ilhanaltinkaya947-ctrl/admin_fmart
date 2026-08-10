import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/format/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton_list.dart';
import '../../auth/state/auth_cubit.dart';
import '../data/orders_repository.dart';
import '../../stores/state/store_cubit.dart';
import '../state/orders_cubit.dart';
import '../models/order_models.dart';
import 'order_details_page.dart';
import 'widgets/order_filter_bar.dart';

class OrdersListPage extends StatefulWidget {
  final int storeId;
  final String storeName;

  const OrdersListPage({super.key, required this.storeId, required this.storeName});

  @override
  State<OrdersListPage> createState() => _OrdersListPageState();
}

class _OrdersListPageState extends State<OrdersListPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        context.read<OrdersCubit>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Pull a CSV of orders matching the current cubit filters, copy it
  /// to the clipboard, and toast the row count. Pragmatic for v1 —
  /// admin pastes into Excel/Google Sheets. share_plus / file save can
  /// come post-launch if the row count outgrows clipboard.
  Future<void> _exportCsv(BuildContext ctx) async {
    final cubit = ctx.read<OrdersCubit>();
    final repo = ctx.read<OrdersRepository>();
    final messenger = ScaffoldMessenger.of(ctx);

    messenger.showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Формирование экспорта…'),
      ]),
      duration: Duration(seconds: 10),
    ));

    try {
      final f = cubit.filters;
      final csv = await repo.exportOrdersCsv(
        storeId: widget.storeId,
        dateFrom: f.dateFrom,
        dateTo: f.dateTo,
        statusIds: f.statusIds,
        search: f.search,
      );
      final rowCount = csv.split('\n').length - 1; // minus header
      await Clipboard.setData(ClipboardData(text: csv));
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        content: Text('CSV скопирован ($rowCount строк). Вставьте в Excel.'),
      ));
    } catch (_) {
      messenger.clearSnackBars();
      messenger.showSnackBar(const SnackBar(
        content: Text('Не удалось выгрузить экспорт'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text('Заказы — ${widget.storeName}'),
        actions: [
          IconButton(
            onPressed: () => context.read<OrdersCubit>().refresh(storeId: widget.storeId),
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
          IconButton(
            onPressed: () => _exportCsv(context),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Экспорт CSV',
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'change_store') {
                await context.read<StoreCubit>().clearStore();
              }
              if (v == 'logout') {
                await context.read<AuthCubit>().logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'change_store', child: Text('Сменить магазин')),
              PopupMenuItem(value: 'logout', child: Text('Выйти')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const OrderFilterBar(),
          Expanded(
            child: BlocBuilder<OrdersCubit, OrdersState>(
              builder: (ctx, state) {
                if (state is OrdersLoading) {
                  return const SkeletonList();
                }

                if (state is OrdersFailure) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                          const SizedBox(height: 12),
                          Text(state.message, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => ctx.read<OrdersCubit>().refresh(storeId: widget.storeId),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state is OrdersLoaded) {
                  if (state.items.isEmpty) {
                    return EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Заказов нет',
                      subtitle: state.filters.isEmpty
                          ? 'Здесь появятся заказы покупателей'
                          : 'Под текущие фильтры ничего не нашлось',
                      action: state.filters.isEmpty
                          ? null
                          : OutlinedButton.icon(
                              onPressed: () =>
                                  ctx.read<OrdersCubit>().clearFilters(),
                              icon: const Icon(Icons.clear),
                              label: const Text('Сбросить фильтры'),
                            ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () =>
                        ctx.read<OrdersCubit>().refresh(storeId: widget.storeId),
                    child: ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount:
                        state.items.length + (state.pagination.hasNext ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      if (i >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final Order o = state.items[i];
                      final display = orderRowDisplay(o);
                      return ListTile(
                        title: Text(
                          'Заказ #${o.id} — '
                          '${orderStatusRu(o.status, fulfillmentType: o.fulfillmentType)}',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (display.showsCustomerAddress)
                              Tooltip(
                                message: o.deliveryAddress,
                                child: Text(
                                  o.deliveryAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            else
                              // The address column holds the STORE's address on
                              // a pickup order, so showing it here would tell
                              // the manager the customer lives at our shop.
                              // Same orange vocabulary as the scheduled row
                              // below, so the row has one accent colour and not
                              // two competing ones.
                              Row(
                                children: [
                                  // Flexible: the chip Container had no width
                                  // guard, only the text beside it did. There
                                  // is no textScaler clamp anywhere in lib/, so
                                  // at ~3x accessibility text in iPad Split
                                  // View «САМОВЫВОЗ» alone exceeds the subtitle
                                  // width and overflows.
                                  Flexible(
                                    child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEE6F00)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'САМОВЫВОЗ',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFEE6F00),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Flexible(
                                    child: Text(
                                      'Клиент заберёт сам',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 2),
                            Text(
                              df.format(o.createdAt.toLocal()),
                              style: const TextStyle(fontSize: 12),
                            ),
                            // Customer-picked delivery slot OR off-hours
                            // auto-scheduled time. Two variants:
                            //   - status=scheduled → off-hours order
                            //     parked until 09:00 release; prefix
                            //     "Выпустить:" so manager knows the
                            //     Запланированные-tab action.
                            //   - any other status with scheduledForAt
                            //     → customer chose a specific slot;
                            //     prefix "К доставке:" so picker can
                            //     plan their day at a glance.
                            if (o.scheduledForAt != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.schedule_outlined,
                                    size: 12,
                                    color: Color(0xFFEE6F00),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${o.status == "scheduled" ? "Выпустить" : "К доставке"}: ${df.format(o.scheduledForAt!.toLocal())}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFEE6F00),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatTenge(o.totalAmount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            // Omitted for pickup: delivery_sum is 0 there, and
                            // «дост: 0 ₸» under a total reads as a discount the
                            // customer received rather than as "there is no
                            // delivery".
                            if (display.showsDeliveryFee)
                              Text(
                                'дост: ${formatTenge(o.deliverySum)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                        onTap: () async {
                          final updated =
                              await Navigator.of(context).push<Order?>(
                            MaterialPageRoute(
                              builder: (_) => OrderDetailsPage(order: o),
                            ),
                          );
                          if (updated != null && context.mounted) {
                            context
                                .read<OrdersCubit>()
                                .updateOrderInList(updated);
                          }
                        },
                      );
                    },
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}
