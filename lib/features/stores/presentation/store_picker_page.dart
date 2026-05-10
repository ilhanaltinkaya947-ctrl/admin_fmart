import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/state/auth_cubit.dart';
import '../state/store_cubit.dart';
import '../models/store_models.dart';

class StorePickerPage extends StatefulWidget {
  const StorePickerPage({super.key});

  @override
  State<StorePickerPage> createState() => _StorePickerPageState();
}

class _StorePickerPageState extends State<StorePickerPage> {
  @override
  void initState() {
    super.initState();
    context.read<StoreCubit>().loadStores();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Выбор магазина')),
      body: BlocBuilder<StoreCubit, StoreState>(
        builder: (ctx, state) {
          if (state is StoreLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is StoreFailure) {
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
                      onPressed: () => ctx.read<StoreCubit>().loadStores(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is StoreListLoaded) {
            // Managers can only access stores they're assigned to.
            // The previous version showed every store and 403'd on every
            // call until the user re-picked. Admins still see everything.
            final auth = context.watch<AuthCubit>().state;
            final isAdmin =
                auth is Authenticated && auth.user.isAdmin;
            final assigned = (auth is Authenticated)
                ? auth.user.assignedStoreIds.toSet()
                : <int>{};

            final visible = isAdmin
                ? state.stores
                : state.stores.where((s) => assigned.contains(s.storeId)).toList();

            if (visible.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store_outlined,
                          size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'Магазины не назначены',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Обратитесь к администратору, чтобы назначить магазин.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => context.read<AuthCubit>().logout(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Выйти'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: visible.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final StoreDto s = visible[i];
                return ListTile(
                  title: Text(s.storeName),
                  subtitle: Text(s.storeAddress),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.read<StoreCubit>().selectStore(s),
                );
              },
            );
          }

          // если StoreNotSelected — обычно тут не окажемся (мы уже загрузили список)
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
