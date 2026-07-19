import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/feature_flags.dart';
import '../../../core/services/new_order_counter.dart';
import '../../auth/state/auth_cubit.dart';
import '../../orders/data/orders_repository.dart';
import '../../banners/presentation/banners_list_page.dart';
import '../../delivery_slots/presentation/slot_templates_list_page.dart';
import '../../customers/presentation/customers_list_page.dart';
import '../../orders/presentation/orders_list_page.dart';
import '../../orders/state/orders_cubit.dart';
import '../../broadcast/presentation/broadcast_page.dart';
import '../../reports/presentation/reports_page.dart';
import '../../reviews/presentation/reviews_page.dart';
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
  // Off-hours parked orders. Customer paid; picking waits until 09:00
  // when a manager hits the Release button. Lives between Новые and
  // История so it surfaces alongside the live workload.
  scheduled,
  orderHistory,
  customers,
  reports,
  reviews,
  users,
  banners,
  // Editor for delivery time slots — per-store template list with start/
  // end window, slot duration, capacity cap. Customer app reads
  // /delivery/slots and renders these as the checkout slot picker.
  deliverySlots,
  broadcast,
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
      // Load staged-rollout feature flags (review reply, substitution UI) so a
      // backend env flip takes effect on next app open, no rebuild.
      final ordersRepo = context.read<OrdersRepository>();
      ordersRepo.getFeatures().then((f) {
        AdminFeatureFlags.instance.set(f);
      }).catchError((_) {
        // Keep the safe all-off default on any error.
      });
    });
  }

  /// Switch from Dashboard to the orders tab with an optional filter.
  /// Called by [DashboardPage] KPI taps and status-row taps. Without a
  /// status name we go to the "active" preset so the manager lands on
  /// something useful (the active queue); with one, we filter precisely
  /// to that status via the shared OrdersCubit.
  void _drillToOrdersFromDashboard({String? statusName}) {
    setState(() => _section = _Section.newOrders);
    final cubit = context.read<OrdersCubit>();
    if (statusName == null) {
      cubit.applyTabPreset(OrdersTabPreset.active);
    } else {
      cubit.applyStatusByName(statusName);
    }
  }

  void _select(_Section s) {
    if (s == _section) return;
    setState(() => _section = s);
    final cubit = context.read<OrdersCubit>();
    switch (s) {
      case _Section.newOrders:
        // Clear the badge as soon as the operator opens the tab — even
        // if they don't actually scroll the list, having seen the tab
        // counts as "they know about the new orders" for badge purposes.
        context.read<NewOrderCounter>().reset();
        cubit.applyTabPreset(OrdersTabPreset.active);
        break;
      case _Section.scheduled:
        cubit.applyTabPreset(OrdersTabPreset.scheduled);
        break;
      case _Section.orderHistory:
        cubit.applyTabPreset(OrdersTabPreset.closed);
        break;
      case _Section.dashboard:
      case _Section.customers:
      case _Section.reports:
      case _Section.reviews:
      case _Section.users:
      case _Section.banners:
      case _Section.deliverySlots:
      case _Section.broadcast:
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
        // Wrap the icon in a ValueListenableBuilder so the badge count
        // refreshes whenever app.dart bumps the counter from the
        // OneSignal foreground handler. Showing a number rather than a
        // dot so a busy morning ("12") reads at a glance from across
        // the warehouse.
        return NavigationDestination(
          icon: _NewOrdersBadge(
            child: const Icon(Icons.fiber_new_outlined),
          ),
          selectedIcon: _NewOrdersBadge(
            child: const Icon(Icons.fiber_new),
          ),
          label: 'Новые',
        );
      case _Section.scheduled:
        return const NavigationDestination(
          icon: Icon(Icons.schedule_outlined),
          selectedIcon: Icon(Icons.schedule),
          label: 'Заплан.',
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
      case _Section.reviews:
        return const NavigationDestination(
          icon: Icon(Icons.star_outline),
          selectedIcon: Icon(Icons.star),
          label: 'Отзывы',
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
      case _Section.deliverySlots:
        return const NavigationDestination(
          icon: Icon(Icons.access_time_outlined),
          selectedIcon: Icon(Icons.access_time_filled),
          label: 'Слоты',
        );
      case _Section.broadcast:
        return const NavigationDestination(
          icon: Icon(Icons.campaign_outlined),
          selectedIcon: Icon(Icons.campaign),
          label: 'Рассылка',
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
          onDrillToOrders: _drillToOrdersFromDashboard,
        );
      case _Section.newOrders:
      case _Section.scheduled:
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
      case _Section.reviews:
        return ReviewsPage(
          storeId: widget.storeId,
          storeName: widget.storeName,
        );
      case _Section.users:
        return const UsersListPage();
      case _Section.banners:
        return const BannersListPage();
      case _Section.deliverySlots:
        return SlotTemplatesListPage(
          storeId: widget.storeId,
          storeName: widget.storeName,
        );
      case _Section.broadcast:
        return const BroadcastPage();
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
          _Section.scheduled,
          _Section.orderHistory,
          _Section.customers,
          _Section.reports,
          _Section.reviews,
          // Users (staff management) and Banners are admin-only. The
          // pages self-gate their bodies, but the nav entries must be
          // gated too — otherwise a manager sees the tab, taps it, and
          // lands on an "admin only" banner.
          if (isAdmin) _Section.users,
          if (isAdmin) _Section.banners,
          // Slot config is per-store; managers run their store day-to-day,
          // so they can tune their own caps. Admin gets it too.
          _Section.deliverySlots,
          if (isAdmin) _Section.broadcast,
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
                badgeBuilder: (child) => _NewOrdersBadge(child: child),
              ),
              _RailItem(
                icon: Icons.schedule_outlined,
                selectedIcon: Icons.schedule,
                label: 'Запланированные',
                isSelected: selected == _Section.scheduled,
                onTap: () => onSelected(_Section.scheduled),
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
              _RailItem(
                icon: Icons.star_outline,
                selectedIcon: Icons.star,
                label: 'Отзывы',
                isSelected: selected == _Section.reviews,
                onTap: () => onSelected(_Section.reviews),
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
              // Delivery slots — staff (admin + manager).
              Builder(builder: (ctx) {
                final auth = ctx.watch<AuthCubit>().state;
                final isStaff = auth is Authenticated && auth.user.isStaff;
                if (!isStaff) return const SizedBox.shrink();
                return _RailItem(
                  icon: Icons.access_time_outlined,
                  selectedIcon: Icons.access_time_filled,
                  label: 'Слоты доставки',
                  isSelected: selected == _Section.deliverySlots,
                  onTap: () => onSelected(_Section.deliverySlots),
                );
              }),
              // Broadcast — admin role only. Sends a push to ALL customers,
              // so we keep it behind the same gate as Banners.
              Builder(builder: (ctx) {
                final auth = ctx.watch<AuthCubit>().state;
                final isAdmin = auth is Authenticated && auth.user.isAdmin;
                if (!isAdmin) return const SizedBox.shrink();
                return _RailItem(
                  icon: Icons.campaign_outlined,
                  selectedIcon: Icons.campaign,
                  label: 'Рассылка',
                  isSelected: selected == _Section.broadcast,
                  onTap: () => onSelected(_Section.broadcast),
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

/// Wraps any child widget with a Material 3 Badge whose count is the
/// current [NewOrderCounter] value — used for both the nav rail icon
/// and the bottom-nav destination so the unread indicator stays in
/// lock-step with the push handler. Zero count renders as the plain
/// child (no badge bubble).
class _NewOrdersBadge extends StatelessWidget {
  final Widget child;
  const _NewOrdersBadge({required this.child});

  @override
  Widget build(BuildContext context) {
    final counter = context.read<NewOrderCounter>();
    return ValueListenableBuilder<int>(
      valueListenable: counter.listenable,
      builder: (_, count, ic) {
        if (count <= 0) return ic!;
        return Badge.count(
          count: count,
          // Cap shown number visually — 99+ keeps the badge from
          // stretching the nav icon's bounds.
          isLabelVisible: true,
          child: ic,
        );
      },
      child: child,
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  /// Optional wrapper around the icon — used to layer a Badge on top
  /// (e.g. the "Новые" tab unread count). Null = render the icon plain.
  final Widget Function(Widget child)? badgeBuilder;

  const _RailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeBuilder,
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
                () {
                  final iconWidget = Icon(
                    isSelected ? selectedIcon : icon,
                    color: fg,
                  );
                  return badgeBuilder == null
                      ? iconWidget
                      : badgeBuilder!(iconWidget);
                }(),
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

