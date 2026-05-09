import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/state/auth_cubit.dart';
import '../../customers/presentation/customers_list_page.dart';
import '../../orders/presentation/orders_list_page.dart';
import '../../orders/state/orders_cubit.dart';
import '../../stores/state/store_cubit.dart';

/// Width above which we switch from bottom NavigationBar to side
/// NavigationRail. iPad portrait is ~810pt; phones are well below 600.
const double _kRailBreakpoint = 720;

enum _Section { newOrders, orderHistory, customers, users }

class HomeShell extends StatefulWidget {
  final int storeId;
  final String storeName;

  const HomeShell({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _Section _section = _Section.newOrders;

  @override
  void initState() {
    super.initState();
    // Default to the active-orders preset on first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrdersCubit>().applyTabPreset(OrdersTabPreset.active);
    });
  }

  void _select(_Section s) {
    if (s == _section) return;
    setState(() => _section = s);
    final cubit = context.read<OrdersCubit>();
    switch (s) {
      case _Section.newOrders:
        cubit.applyTabPreset(OrdersTabPreset.active);
        break;
      case _Section.orderHistory:
        cubit.applyTabPreset(OrdersTabPreset.closed);
        break;
      case _Section.customers:
      case _Section.users:
        break;
    }
  }

  Widget _bodyFor(_Section s) {
    switch (s) {
      case _Section.newOrders:
      case _Section.orderHistory:
        return OrdersListPage(
          storeId: widget.storeId,
          storeName: widget.storeName,
        );
      case _Section.customers:
        return const CustomersListPage();
      case _Section.users:
        return const _UsersPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final wide = constraints.maxWidth >= _kRailBreakpoint;
        final body = _bodyFor(_section);

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                _SideRail(
                  selected: _section,
                  onSelected: _select,
                  storeName: widget.storeName,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _section.index,
            onDestinationSelected: (i) => _select(_Section.values[i]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.fiber_new_outlined),
                selectedIcon: Icon(Icons.fiber_new),
                label: 'Новые',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'История',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Клиенты',
              ),
              NavigationDestination(
                icon: Icon(Icons.admin_panel_settings_outlined),
                selectedIcon: Icon(Icons.admin_panel_settings),
                label: 'Юзеры',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SideRail extends StatelessWidget {
  final _Section selected;
  final ValueChanged<_Section> onSelected;
  final String storeName;

  const _SideRail({
    required this.selected,
    required this.onSelected,
    required this.storeName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
      child: Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'F-Mart Admin',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      storeName,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _RailItem(
                icon: Icons.fiber_new_outlined,
                selectedIcon: Icons.fiber_new,
                label: 'Новые заказы',
                isSelected: selected == _Section.newOrders,
                onTap: () => onSelected(_Section.newOrders),
              ),
              _RailItem(
                icon: Icons.history_outlined,
                selectedIcon: Icons.history,
                label: 'История заказов',
                isSelected: selected == _Section.orderHistory,
                onTap: () => onSelected(_Section.orderHistory),
              ),
              _RailItem(
                icon: Icons.people_outline,
                selectedIcon: Icons.people,
                label: 'Клиенты',
                isSelected: selected == _Section.customers,
                onTap: () => onSelected(_Section.customers),
              ),
              _RailItem(
                icon: Icons.admin_panel_settings_outlined,
                selectedIcon: Icons.admin_panel_settings,
                label: 'Пользователи',
                isSelected: selected == _Section.users,
                onTap: () => onSelected(_Section.users),
              ),
              const Spacer(),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.store_outlined),
                title: const Text('Сменить магазин'),
                onTap: () => context.read<StoreCubit>().clearStore(),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Выйти'),
                onTap: () => context.read<AuthCubit>().logout(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isSelected
        ? theme.colorScheme.primaryContainer
        : Colors.transparent;
    final fg = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UsersPlaceholder extends StatelessWidget {
  const _UsersPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Пользователи')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              const Text(
                'Управление пользователями',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Раздел в разработке. Доступен только администратору.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
