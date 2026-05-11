import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton_list.dart';
import '../../stores/state/store_cubit.dart';
import '../models/customer_models.dart';
import '../state/customers_cubit.dart';
import 'customer_detail_page.dart';

class CustomersListPage extends StatefulWidget {
  const CustomersListPage({super.key});

  @override
  State<CustomersListPage> createState() => _CustomersListPageState();
}

class _CustomersListPageState extends State<CustomersListPage> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >=
          _scroll.position.maxScrollExtent - 200) {
        context.read<CustomersCubit>().loadMore();
      }
    });
    // Rebuild on every keystroke so the clear-X icon shows/hides reactively.
    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomersCubit>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Клиенты'),
        actions: [
          IconButton(
            onPressed: () => context.read<CustomersCubit>().refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => context.read<CustomersCubit>().setQuery(v),
              decoration: InputDecoration(
                hintText: 'Поиск по телефону, email или имени',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          context.read<CustomersCubit>().setQuery('');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: BlocBuilder<CustomersCubit, CustomersState>(
              builder: (ctx, state) {
                if (state is CustomersLoading) {
                  return const SkeletonList();
                }
                if (state is CustomersFailure) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () =>
                              context.read<CustomersCubit>().refresh(),
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  );
                }
                if (state is CustomersLoaded) {
                  if (state.items.isEmpty) {
                    return EmptyState(
                      icon: Icons.people_outline,
                      title: 'Клиенты не найдены',
                      subtitle: _searchCtrl.text.isEmpty
                          ? 'Пока никто не зарегистрировался'
                          : 'Попробуйте другой запрос',
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => ctx.read<CustomersCubit>().refresh(),
                    child: ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                      final c = state.items[i];
                      return _CustomerTile(customer: c, df: df);
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

class _CustomerTile extends StatelessWidget {
  final AdminCustomer customer;
  final DateFormat df;
  const _CustomerTile({required this.customer, required this.df});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(customer);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          initials,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        customer.fullName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${customer.phone}${customer.email == null || customer.email!.isEmpty ? '' : ' · ${customer.email}'}',
      ),
      trailing: Text(
        df.format(customer.createdAt.toLocal()),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      onTap: () {
        final storeState = context.read<StoreCubit>().state;
        if (storeState is! StoreSelected) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomerDetailPage(
              customerId: customer.id,
              storeId: storeState.storeId,
              fallbackName: customer.fullName,
            ),
          ),
        );
      },
    );
  }

  String _initials(AdminCustomer c) {
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
