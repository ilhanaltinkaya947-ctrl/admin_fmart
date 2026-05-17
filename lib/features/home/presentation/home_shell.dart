import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/state/auth_cubit.dart';
import '../../banners/presentation/banners_list_page.dart';
import '../../customers/presentation/customers_list_page.dart';
import '../../orders/presentation/orders_list_page.dart';
import '../../orders/state/orders_cubit.dart';
import '../../reports/presentation/reports_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../stores/state/store_cubit.dart';
import '../../users/presentation/users_list_page.dart';
import 'dashboard_page.dart';

/// Width above which we switch from bottom NavigationBar to side
/// NavigationRail. iPad portrait is ~810pt; phones are well below 600.
const double _kRailBreakpoint = 720;

enum _Section {
  dashboard,
  newOrders,
  orderHistory,
  customers,
  reports,
  users,
  banners,
  settings,
}

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
  _Section _section = _Section.dashboard;

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
      case _Section.dashboard:
      case _Section.customers:
      case _Section.reports:
      case _Section.users:
      case _Section.banners:
      case _Section.settings:
        break;
    }
  }

  NavigationDestination _phoneDestination(_Section s) {
    switch (s) {
      case _Section.dashboard:
        return const NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Сегодня',
        );
      case _Section.newOrders:
        return const NavigationDestination(
          icon: Icon(Icons.fiber_new_outlined),
          selectedIcon: Icon(Icons.fiber_new),
          label: 'Новые',
        );
      case _Section.orderHistory:
        return const NavigationDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: 'История',
        );
      case _Section.customers:
        return const NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Клиенты',
        );
      case _Section.reports:
        return const NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: 'Отчёты',
        );
      case _Section.users:
        return const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Юзеры',
        );
      case _Section.banners:
        return const NavigationDestination(
          icon: Icon(Icons.image_outlined),
          selectedIcon: Icon(Icons.image),
          label: 'Баннеры',
        );
      case _Section.settings:
        return const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Настр.',
        );
    }
  }

  Widget _bodyFor(_Section s) {
    switch (s) {
      case _Section.dashboard:
        return DashboardPage(
          storeId: widget.storeId,
          storeName: widget.storeName,
        );
      case _Section.newOrders:
      case _Section.orderHistory:
        return OrdersListPage(
          storeId: widget.storeId,
          storeName: widget.storeName,
        );
      case _Section.customers:
        return const CustomersListPage();
      case _Section.reports:
        return ReportsPage(
          storeId: widget.storeId,
          storeName: widget.storeName,
        );
      case _Section.users:
        return const UsersListPage();
      case _Section.banners:
        return const BannersListPage();
      case _Section.settings:
        return const SettingsPage();
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

        // Phone bottom nav. The `_Section` enum may have more values than
        // we want to show on phone (e.g. Banners, admin-only). We compute
        // the visible-section list per role and map index↔section through
        // it so NavigationBar's selectedIndex never falls outside its
        // destinations and we don't show non-applicable items to managers.
        final auth = context.watch<AuthCubit>().state;
        final isAdmin = auth is Authenticated && auth.user.isAdmin;

        final visibleSections = <_Section>[
          _Section.dashboard,
          _Section.newOrders,
          _Section.orderHistory,
          _Section.customers,
          _Section.reports,
          // Users (staff management) and Banners are admin-only. The
          // pages self-gate their bodies, but the nav entries must be
          // gated too — otherwise a manager sees the tab, taps it, and
          // lands on an "admin only" banner.
          if (isAdmin) _Section.users,
          if (isAdmin) _Section.banners,
          _Section.settings,
        ];

        final selectedIndex = visibleSections.indexOf(_section);
        // If somehow the current section isn't visible (e.g. role flipped
        // mid-session), fall back to the first one to avoid an assertion.
        final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;

        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: safeIndex,
            onDestinationSelected: (i) => _select(visibleSections[i]),
            destinations: [
              for (final s in visibleSections) _phoneDestination(s),
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
                icon: Icons.dashboard_outlined,
                selectedIcon: Icons.dashboard,
                label: 'Сегодня',
                isSelected: selected == _Section.dashboard,
                onTap: () => onSelected(_Section.dashboard),
              ),
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
                icon: Icons.bar_chart_outlined,
                selectedIcon: Icons.bar_chart,
                label: 'Отчёты',
                isSelected: selected == _Section.reports,
                onTap: () => onSelected(_Section.reports),
              ),
              // Users (staff management) — admin role only. Manager
              // doesn't see this entry (the page self-gates too, but the
              // nav entry must match).
              Builder(builder: (ctx) {
                final auth = ctx.watch<AuthCubit>().state;
                final isAdmin = auth is Authenticated && auth.user.isAdmin;
                if (!isAdmin) return const SizedBox.shrink();
                return _RailItem(
                  icon: Icons.admin_panel_settings_outlined,
                  selectedIcon: Icons.admin_panel_settings,
                  label: 'Пользователи',
                  isSelected: selected == _Section.users,
                  onTap: () => onSelected(_Section.users),
                );
              }),
              // Banners — admin role only. Manager doesn't see this entry.
              Builder(builder: (ctx) {
                final auth = ctx.watch<AuthCubit>().state;
                final isAdmin = auth is Authenticated && auth.user.isAdmin;
                if (!isAdmin) return const SizedBox.shrink();
                return _RailItem(
                  icon: Icons.image_outlined,
                  selectedIcon: Icons.image,
                  label: 'Баннеры',
                  isSelected: selected == _Section.banners,
                  onTap: () => onSelected(_Section.banners),
                );
              }),
              _RailItem(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'Настройки',
                isSelected: selected == _Section.settings,
                onTap: () => onSelected(_Section.settings),
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

