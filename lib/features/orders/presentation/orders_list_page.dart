import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../auth/state/auth_cubit.dart';
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
                  return const Center(child: CircularProgressIndicator());
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
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Заказов нет'),
                          if (!state.filters.isEmpty) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  ctx.read<OrdersCubit>().clearFilters(),
                              icon: const Icon(Icons.clear),
                              label: const Text('Сбросить фильтры'),
                            ),
                          ],
                        ],
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
                      return ListTile(
                        title: Text(
                          'Заказ #${o.id} — ${orderStatusRu(o.status)}',
                        ),
                        subtitle: Text(
                          '${o.deliveryAddress}\n${df.format(o.createdAt.toLocal())}',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₸ ${o.totalAmount}'),
                            Text(
                              'дост: ₸ ${o.deliverySum}',
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
