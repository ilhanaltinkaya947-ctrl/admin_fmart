import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/held_products_repository.dart';

/// What is hidden from customers in this store, and why.
///
/// Holds are placed automatically when a picker reports a line missing, and
/// lift automatically when 1C reports a delivery. So this screen is not a
/// workflow — nobody has to visit it for the system to work.
///
/// It exists for the two questions nothing else can answer:
///   • "why has this stopped selling?"
///   • "we restocked it this morning, put it back now."
class HeldProductsPage extends StatefulWidget {
  final int storeId;
  final String storeName;

  const HeldProductsPage({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<HeldProductsPage> createState() => _HeldProductsPageState();
}

class _HeldProductsPageState extends State<HeldProductsPage> {
  List<HeldProduct>? _items;
  String? _error;
  bool _loading = false;
  final _busy = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant HeldProductsPage old) {
    super.didUpdateWidget(old);
    // The shell keeps this page alive across a store switch, so without this
    // the list would keep showing the previous store's hidden products.
    if (old.storeId != widget.storeId) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<HeldProductsRepository>();
      final list = await repo.list(storeId: widget.storeId);
      if (!mounted) return;
      setState(() => _items = list);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = describeHeldProductsError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить список');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _release(HeldProduct p) async {
    if (_busy.contains(p.productId)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Вернуть товар в продажу?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            // Deliberately not a promise that it appears instantly. Release
            // clears the hold but does NOT invent a quantity — the next sync
            // from 1C supplies the real number, usually within minutes. Saying
            // "готово" and having the product stay hidden for five minutes is
            // how an operator concludes the button is broken and taps it again.
            const Text(
              'Товар снова появится у покупателей, когда 1С пришлёт остаток — '
              'обычно в течение нескольких минут.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Назад'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Вернуть'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy.add(p.productId));
    try {
      final repo = context.read<HeldProductsRepository>();
      // The server returns the remaining list, so the row cannot linger.
      final list = await repo.release(
        storeId: widget.storeId,
        productIds: [p.productId],
      );
      if (!mounted) return;
      setState(() => _items = list);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${p.name}» вернётся в продажу')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeHeldProductsError(e))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось вернуть товар')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(p.productId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Scaffold(
      // AppBar, matching every other section page. Without one this screen
      // rendered UNDER the status bar — the count, which is the whole point of
      // the header, sat behind the clock. Seen on a simulator, invisible in
      // the diff.
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Скрытые товары'),
            Text(
              widget.storeName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (_) {
            if (items == null && _loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null && items == null) {
              return _Message(
                icon: Icons.error_outline,
                title: _error!,
                action: FilledButton(
                  onPressed: _load,
                  child: const Text('Повторить'),
                ),
              );
            }
            if (items == null || items.isEmpty) {
              return const _Message(
                icon: Icons.check_circle_outline,
                title: 'Ничего не скрыто',
                subtitle:
                    'Когда сборщик не находит товар на полке, он скрывается '
                    'здесь до следующего завоза.',
              );
            }
            return ListView.separated(
              // AlwaysScrollable so pull-to-refresh works on a short list too.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i == 0) return _Header(count: items.length);
                final p = items[i - 1];
                return _HeldRow(
                  product: p,
                  busy: _busy.contains(p.productId),
                  onRelease: () => _release(p),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Скрыто от покупателей: $count',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Вернутся сами, когда 1С пришлёт завоз.',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeldRow extends StatelessWidget {
  final HeldProduct product;
  final bool busy;
  final VoidCallback onRelease;

  const _HeldRow({
    required this.product,
    required this.busy,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name.isEmpty
                      ? 'Товар ${product.productId}'
                      : product.name,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 3),
                Text(
                  'скрыт ${_when(product.heldAt)}',
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
                // The 1C figure is the evidence, so it is shown when we have
                // it: the feed still claiming stock is exactly why the product
                // had to be hidden by hand.
                if (product.quantityReportedBy1c != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '1С показывает ${product.quantityReportedBy1c} шт',
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          busy
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: onRelease,
                  child: const Text('Вернуть'),
                ),
        ],
      ),
    );
  }

  /// Short and local. An operator reading this cares about "today" versus "a
  /// week ago", not a timestamp.
  static String _when(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'сегодня, $hhmm';
    if (days == 1) return 'вчера, $hhmm';
    return '$days ${_dayWord(days)} назад';
  }

  static String _dayWord(int n) {
    final m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'дней';
    switch (n % 10) {
      case 1:
        return 'день';
      case 2:
      case 3:
      case 4:
        return 'дня';
      default:
        return 'дней';
    }
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    // A ListView so pull-to-refresh still works on the empty and error states —
    // otherwise the only way out of a transient error is to leave the tab.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
          child: Column(
            children: [
              Icon(icon, size: 40,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
