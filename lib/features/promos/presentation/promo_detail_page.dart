import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/promo_models.dart';
import '../data/promo_repository.dart';
import '../state/promos_cubit.dart';

/// One promo code: its numbers, its schedule, and who used it.
///
/// The redemption trail is the part marketing could never see — 132 redemptions
/// have accumulated since May with no way to look at them. Showing order ids and
/// statuses makes "did the campaign work, and did anyone abuse it" answerable
/// without a SQL console.
class PromoDetailPage extends StatefulWidget {
  final AdminPromo promo;

  const PromoDetailPage({super.key, required this.promo});

  @override
  State<PromoDetailPage> createState() => _PromoDetailPageState();
}

class _PromoDetailPageState extends State<PromoDetailPage> {
  List<PromoRedemption>? _rows;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Re-read the code from the cubit so a toggle made on the list page is
    // reflected here rather than showing a stale snapshot taken at push time.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context.read<PromoRepository>().redemptions(widget.promo.code);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// The freshest version of this code, so the header cannot disagree with the
  /// list behind it.
  AdminPromo get _promo {
    final s = context.read<PromosCubit>().state;
    if (s is PromosLoaded) {
      for (final p in s.items) {
        if (p.code == widget.promo.code) return p;
      }
    }
    return widget.promo;
  }

  @override
  Widget build(BuildContext context) {
    final p = _promo;
    return Scaffold(
      appBar: AppBar(title: Text(p.code)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(promo: p),
          const SizedBox(height: 16),
          Text('Использование',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _UsageGrid(promo: p, onClearExpiry: p.expiresAt == null ? null : () => _clearExpiry(p.code)),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('История применений',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _Box(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: Colors.orange, size: 32),
                  const SizedBox(height: 8),
                  Text('Не удалось загрузить историю', textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Повторить')),
                ],
              ),
            )
          else if ((_rows ?? const []).isEmpty)
            const _Box(
              child: Text(
                'По этому промокоду ещё не было применений.',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            if ((_rows!.length) >= 100)
              const _Hint(
                text: 'Показаны последние 100 применений.',
              ),
            ..._rows!.map((r) => _RedemptionTile(r: r)),
          ],
        ],
      ),
    );
  }

  Future<void> _clearExpiry(String code) async {
    // Clearing is a distinct instruction from "set no date" — see the
    // repository's clearExpiry contract.
    await context.read<PromosCubit>().update(code, clearExpiry: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Срок действия снят')),
    );
  }
}

class _Header extends StatelessWidget {
  final AdminPromo promo;
  const _Header({required this.promo});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(promo.code,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 22, letterSpacing: 1)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: promo.state == AdminPromoState.live
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                promo.state.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: promo.state == AdminPromoState.live
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFC62828),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(promo.typeLabel,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (promo.isTestOnly) ...[
          const SizedBox(height: 10),
          _Hint(
            text: 'Тестовый тип — не для кампаний. Работает только для '
                'аккаунтов из белого списка; всем остальным клиентам сервер '
                'откажет в этом коде.',
          ),
        ],
      ],
    );
  }
}

class _UsageGrid extends StatelessWidget {
  final AdminPromo promo;
  final VoidCallback? onClearExpiry;
  const _UsageGrid({required this.promo, this.onClearExpiry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _Cell(label: 'Применений', value: '${promo.redemptions}')),
            Expanded(child: _Cell(label: 'Клиентов', value: '${promo.customers}')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _Cell(label: 'Применён', value: '${promo.committed}')),
            Expanded(child: _Cell(label: 'Освобождён', value: '${promo.released}')),
          ],
        ),
        const SizedBox(height: 8),
        // The distinction the old "131 redemptions" reading got wrong: one
        // customer can produce several rows.
        const _Hint(
          text: '«Применений» — это записи в базе. Один клиент может дать '
              'несколько записей, поэтому число клиентов обычно меньше.',
        ),
        const SizedBox(height: 12),
        _Box(
          child: Row(
            children: [
              const Icon(Icons.event, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  promo.expiresAt == null
                      ? 'Без ограничения по сроку'
                      : 'Действует до ${_fmt(promo.expiresAt!)}',
                ),
              ),
              if (onClearExpiry != null)
                TextButton(onPressed: onClearExpiry, child: const Text('Снять')),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  const _Cell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}

class _RedemptionTile extends StatelessWidget {
  final PromoRedemption r;
  const _RedemptionTile({required this.r});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (r.status) {
      'committed' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'reserved' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      _ => (const Color(0xFFF5F5F5), const Color(0xFF616161)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Заказ №${r.orderId}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      'Клиент №${r.userId}'
                      '${r.createdAt != null ? ' · ${_fmt(r.createdAt!)}' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (r.discountSum > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${r.discountSum.toStringAsFixed(0)} ${r.currency}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration:
                    BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  r.statusLabel,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Box extends StatelessWidget {
  final Widget child;
  const _Box({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
