import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/api/api_config.dart';
import '../../auth/state/auth_cubit.dart';
import '../../stores/state/store_cubit.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '—';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (_) {
      // Leave defaults; not worth surfacing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthCubit>().state;
    final store = context.watch<StoreCubit>().state;
    final theme = Theme.of(context);

    String role = '—';
    String userName = '—';
    String userPhone = '—';
    String userEmail = '';
    int? userId;
    bool isManagerNoStores = false;
    int assignedStoreCount = 0;

    if (auth is Authenticated) {
      role = auth.user.isAdmin ? 'Администратор' : 'Менеджер';
      userName = auth.user.fullName;
      userPhone = auth.user.phone;
      userEmail = auth.user.email ?? '';
      userId = auth.user.id;
      assignedStoreCount = auth.user.assignedStoreIds.length;
      isManagerNoStores = auth.user.isManager && assignedStoreCount == 0;
    }

    String storeName = '—';
    int? storeId;
    if (store is StoreSelected) {
      storeName = store.storeName;
      storeId = store.storeId;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isManagerNoStores)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Магазины не назначены. Обратитесь к администратору, '
                      'чтобы получить доступ к заказам.',
                    ),
                  ),
                ],
              ),
            ),
          _SectionHeader('Учётная запись'),
          _InfoCard(
            children: [
              _Row('Имя', userName),
              _Row('Телефон', userPhone),
              if (userEmail.isNotEmpty) _Row('Email', userEmail),
              _Row('Роль', role),
              if (userId != null) _Row('ID', '#$userId'),
              if (auth is Authenticated && auth.user.isManager)
                _Row(
                  'Магазинов назначено',
                  '$assignedStoreCount',
                ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader('Магазин'),
          _InfoCard(
            children: [
              _Row('Текущий магазин', storeName),
              if (storeId != null) _Row('ID магазина', '#$storeId'),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.store_outlined),
            title: const Text('Сменить магазин'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.read<StoreCubit>().clearStore(),
          ),
          const SizedBox(height: 16),
          _SectionHeader('Язык'),
          _InfoCard(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Русский'),
                trailing: const Icon(Icons.check, color: Colors.green),
                dense: true,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Қазақша'),
                subtitle: Text(
                  'Скоро',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                enabled: false,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader('Приложение'),
          _InfoCard(
            children: [
              _Row('Версия', _buildNumber.isEmpty ? _appVersion : '$_appVersion ($_buildNumber)'),
              _Row('Сервер', _displayHost(ApiConfig.baseUrl)),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Выйти из аккаунта'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.red.shade300),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _displayHost(String url) {
    return url
        .replaceFirst('https://', '')
        .replaceFirst('http://', '')
        .replaceAll(RegExp(r'/$'), '');
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Потребуется снова ввести телефон и пароль.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AuthCubit>().logout();
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
