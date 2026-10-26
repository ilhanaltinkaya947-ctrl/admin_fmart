import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/held_products_repository.dart' show describeHeldProductsError;
import '../data/morning_check_repository.dart';

/// «Утренняя проверка» (26.10): one question per hidden product, every
/// morning, for the store manager standing in the shop: is it on the shelf?
///
/// «Да, есть» puts it back on sale (unless 1C itself says 0), «Нет, ещё нет»
/// keeps it hidden one more day. Either answer can be changed by tapping the
/// other button. Nothing here is required for the system to work: an
/// unanswered hold lapses back to 1C on its own.
class MorningCheckPage extends StatefulWidget {
  final int storeId;
  final String storeName;

  const MorningCheckPage({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<MorningCheckPage> createState() => _MorningCheckPageState();
}

class _MorningCheckPageState extends State<MorningCheckPage> {
  MorningCheckList? _list;
  String? _error;
  bool _loading = false;
  final _busy = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant MorningCheckPage old) {
    super.didUpdateWidget(old);
    // Kept alive across a store switch: reload, or it shows the old store.
    if (old.storeId != widget.storeId) {
      _list = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<MorningCheckRepository>();
      final list = await repo.list(storeId: widget.storeId);
      if (!mounted) return;
      setState(() => _list = list);
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

  Future<void> _answer(MorningCheckItem item, bool present) async {
    if (_busy.contains(item.productId) || item.answer == present) return;
    setState(() => _busy.add(item.productId));
    try {
      final repo = context.read<MorningCheckRepository>();
      // The server answers with the fresh list.
      final list = await repo.answer(
        storeId: widget.storeId,
        productId: item.productId,
        present: present,
      );
      if (!mounted) return;
      setState(() => _list = list);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить ответ')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(item.productId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Утренняя проверка'),
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
        child: Builder(builder: (_) {
          if (list == null && _loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list == null) {
            return _Message(
              icon: Icons.error_outline,
              title: _error ?? 'Не удалось загрузить список',
              action: FilledButton(onPressed: _load, child: const Text('Повторить')),
            );
          }
          if (!list.enabled) {
            return const _Message(
              icon: Icons.pause_circle_outline,
              title: 'Утренняя проверка выключена',
            );
          }
          if (list.items.isEmpty) {
            return const _Message(
              icon: Icons.check_circle_outline,
              title: 'Сегодня проверять нечего',
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.items.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) {
                return MorningCheckHeader(
                  storeName: widget.storeName,
                  remaining: list.remaining,
                );
              }
              final item = list.items[i - 1];
              return MorningCheckRow(
                key: ValueKey('morning-row-${item.productId}'),
                item: item,
                busy: _busy.contains(item.productId),
                onAnswer: (present) => _answer(item, present),
              );
            },
          );
        }),
      ),
    );
  }
}

/// Store chip and «осталось N» / «готово».
class MorningCheckHeader extends StatelessWidget {
  final String storeName;
  final int remaining;

  const MorningCheckHeader({
    super.key,
    required this.storeName,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final done = remaining == 0;
    final tone = done ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(
            avatar: const Icon(Icons.store_outlined, size: 18),
            label: Text(storeName),
            visualDensity: VisualDensity.compact,
          ),
          Container(
            key: const ValueKey('morning-progress'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: tone.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tone.shade200),
            ),
            child: Text(
              done ? 'готово' : 'осталось $remaining',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tone.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One product: when it was hidden, the two answers, and what the answer did.
class MorningCheckRow extends StatelessWidget {
  final MorningCheckItem item;
  final bool busy;
  final ValueChanged<bool> onAnswer;

  const MorningCheckRow({
    super.key,
    required this.item,
    required this.busy,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final outcome = morningCheckOutcome(item);
    final held = item.heldAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumb(url: item.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name.isEmpty ? 'Товар ${item.productId}' : item.name,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
                ),
                if (held != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'скрыт с ${formatAlmaty(held)}',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ],
                if (item.answer == null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'без ответа',
                    style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800),
                  ),
                ],
                if (outcome != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    outcome,
                    key: const ValueKey('morning-outcome'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: item.answer == true
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _AnswerButton(
                      label: 'Да, есть',
                      tone: Colors.green,
                      selected: item.answer == true,
                      enabled: !busy,
                      onTap: () => onAnswer(true),
                    ),
                    _AnswerButton(
                      label: 'Нет, ещё нет',
                      tone: Colors.red,
                      selected: item.answer == false,
                      enabled: !busy,
                      onTap: () => onAnswer(false),
                    ),
                    if (busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final String label;
  final MaterialColor tone;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.label,
    required this.tone,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 44 high: tapped standing in an aisle.
    const size = Size(0, 44);
    if (selected) {
      return FilledButton.icon(
        key: ValueKey('morning-$label-selected'),
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: tone.shade600,
          foregroundColor: Colors.white,
          minimumSize: size,
        ),
        icon: const Icon(Icons.check, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton(
      key: ValueKey('morning-$label'),
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: tone.shade700,
        side: BorderSide(color: tone.shade200),
        minimumSize: size,
      ),
      child: Text(label),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  const _Thumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.shopping_basket_outlined, color: cs.onSurfaceVariant),
    );
    final u = url;
    if (u == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: u,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? action;

  const _Message({required this.icon, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    // A ListView so pull-to-refresh works on the empty and error states too.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
          child: Column(
            children: [
              Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
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
