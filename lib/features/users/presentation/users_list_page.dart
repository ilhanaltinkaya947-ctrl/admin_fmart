import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton_list.dart';
import '../../auth/state/auth_cubit.dart';
import '../models/user_models.dart';
import '../state/users_cubit.dart';
import 'user_edit_page.dart';

class UsersListPage extends StatefulWidget {
  const UsersListPage({super.key});

  @override
  State<UsersListPage> createState() => _UsersListPageState();
}

class _UsersListPageState extends State<UsersListPage> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >=
          _scroll.position.maxScrollExtent - 200) {
        context.read<UsersCubit>().loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UsersCubit>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCreate() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UserEditPage()),
    );
    if (saved == true && mounted) {
      context.read<UsersCubit>().refresh();
    }
  }

  Future<void> _openEdit(AdminUser u) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => UserEditPage(existing: u)),
    );
    if (saved == true && mounted) {
      context.read<UsersCubit>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthCubit>().state;
    final isAdmin = auth is Authenticated && auth.user.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Пользователи'),
        actions: [
          IconButton(
            onPressed: () => context.read<UsersCubit>().refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: const Text('Создать'),
            )
          : null,
      body: !isAdmin
          ? const _AdminOnlyBanner()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => context.read<UsersCubit>().setQuery(v),
                    decoration: InputDecoration(
                      hintText: 'Поиск по телефону, email или имени',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                context.read<UsersCubit>().setQuery('');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: BlocBuilder<UsersCubit, UsersState>(
                    builder: (ctx, state) {
                      if (state is UsersLoading) {
                        return const SkeletonList();
                      }
                      if (state is UsersFailure) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(state.message),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: () =>
                                    ctx.read<UsersCubit>().refresh(),
                                child: const Text('Повторить'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (state is UsersLoaded) {
                        if (state.items.isEmpty) {
                          return EmptyState(
                            icon: Icons.admin_panel_settings_outlined,
                            title: 'Пользователи не найдены',
                            subtitle: _searchCtrl.text.isEmpty
                                ? 'Создайте первого менеджера или администратора'
                                : 'Попробуйте другой запрос',
                          );
                        }
                        return RefreshIndicator(
                          onRefresh: () =>
                              ctx.read<UsersCubit>().refresh(),
                          child: ListView.separated(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: state.items.length +
                              (state.pagination.hasNext ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            if (i >= state.items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final u = state.items[i];
                            return _UserTile(
                              user: u,
                              onTap: () => _openEdit(u),
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

class _UserTile extends StatelessWidget {
  final AdminUser user;
  final VoidCallback onTap;
  const _UserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _initials(user);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: user.isAdmin
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer,
        child: Text(
          initials,
          style: TextStyle(
            color: user.isAdmin
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              user.fullName == '—' ? user.phone : user.fullName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _RoleBadge(role: user.role),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.phone),
          const SizedBox(height: 2),
          if (user.isAdmin)
            Text(
              'Доступ ко всем магазинам',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              user.assignedStoreIds.isEmpty
                  ? 'Магазины не назначены'
                  : 'Магазинов: ${user.assignedStoreIds.length}',
              style: TextStyle(
                fontSize: 12,
                color: user.assignedStoreIds.isEmpty
                    ? Colors.orange.shade700
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right),
    );
  }

  String _initials(AdminUser u) {
    final fn = (u.firstName ?? '').trim();
    final ln = (u.lastName ?? '').trim();
    final a = fn.isNotEmpty ? fn[0] : '';
    final b = ln.isNotEmpty ? ln[0] : '';
    final init = (a + b).toUpperCase();
    if (init.isNotEmpty) return init;
    final phone = u.phone.replaceAll(RegExp(r'\D'), '');
    return phone.isNotEmpty ? phone.substring(phone.length - 2) : '?';
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role.toLowerCase() == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin ? Colors.purple.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAdmin ? Colors.purple.shade200 : Colors.blue.shade200,
        ),
      ),
      child: Text(
        isAdmin ? 'Админ' : 'Менеджер',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color:
              isAdmin ? Colors.purple.shade800 : Colors.blue.shade800,
        ),
      ),
    );
  }
}

class _AdminOnlyBanner extends StatelessWidget {
  const _AdminOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'Раздел доступен только администратору',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
