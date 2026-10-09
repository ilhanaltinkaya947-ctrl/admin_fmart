import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../data/pickup_stores_repository.dart';

/// Which shops hand orders over at a counter.
///
/// This screen replaces a deploy. Collection used to be decided by
/// `kPickupStoreIds = {3}` compiled into the customer app and
/// `PICKUP_STORE_IDS` in cart-service's environment, so opening самовывоз at
/// Адырбекова needed an App Store release, or at best an SSH session and a
/// restart — neither available to the person who knows the counter is staffed.
class PickupStoresPage extends StatefulWidget {
  final PickupStoresRepository repo;
  const PickupStoresPage({super.key, required this.repo});

  @override
  State<PickupStoresPage> createState() => _PickupStoresPageState();
}

class _PickupStoresPageState extends State<PickupStoresPage> {
  List<AdminStore>? _stores;
  String? _error;

  /// Shops with a write in flight. Their switch is disabled rather than
  /// optimistically flipped: until the server answers, the honest rendering is
  /// "we are asking", not "done".
  final Set<int> _busy = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.repo.list();
      if (!mounted) return;
      setState(() => _stores = rows);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = describePickupStoresError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить магазины');
    }
  }

  Future<void> _toggle(AdminStore store, bool enabled) async {
    setState(() => _busy.add(store.storeId));
    try {
      final updated =
          await widget.repo.setPickup(storeId: store.storeId, enabled: enabled);
      if (!mounted) return;
      setState(() {
        final list = _stores;
        if (list != null) {
          final i = list.indexWhere((s) => s.storeId == updated.storeId);
          // Rendered from the SERVER's answer, never from `enabled`. If the
          // write were refused the row must go back to the truth rather than
          // sit there showing what we asked for.
          if (i != -1) list[i] = updated;
        }
      });
      _say(updated.pickupAvailable
          ? 'Самовывоз включён: ${updated.storeName}'
          : 'Самовывоз выключен: ${updated.storeName}');
    } on DioException catch (e) {
      if (!mounted) return;
      _say(describePickupStoresError(e));
    } catch (_) {
      if (!mounted) return;
      _say('Не удалось сохранить');
    } finally {
      if (mounted) setState(() => _busy.remove(store.storeId));
    }
  }

  void _say(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Самовывоз')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    final err = _error;
    if (err != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Icon(Icons.error_outline,
              size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(err, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: _load,
              child: const Text('Повторить'),
            ),
          ),
        ],
      );
    }

    final stores = _stores;
    if (stores == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (stores.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 64),
          Center(child: Text('Магазинов нет')),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: stores.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == stores.length) return const _Footer();
        final s = stores[i];
        final busy = _busy.contains(s.storeId);
        return SwitchListTile(
          value: s.pickupAvailable,
          // Disabled while in flight so a second tap cannot race the first.
          onChanged: busy ? null : (v) => _toggle(s, v),
          title: Text(s.storeName),
          subtitle: Text(
            s.isActive
                ? s.storeAddress
                // Said plainly, because switching collection on at a hidden
                // shop otherwise looks like the toggle silently failed.
                : '${s.storeAddress}\nМагазин скрыт в приложении',
          ),
          isThreeLine: !s.isActive,
          secondary: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.storefront_outlined),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Text(
        'Изменения действуют сразу, обновлять приложение не нужно. '
        'Клиент увидит самовывоз при следующем открытии корзины.',
        style: style,
      ),
    );
  }
}
