import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/promo_models.dart';
import '../state/promos_cubit.dart';
import 'promo_detail_page.dart';
import 'promo_edit_page.dart';

/// Промокоды — the screen marketing has never had.
///
/// The promo engine has been live since May (132 redemptions across two codes)
/// with no UI at all: every campaign needed engineering. This is the first
/// surface where a manager can see a code's usage and turn one off.
///
/// NOTE ON RENDERING: every return in this widget's builder paints something.
/// A blank body under a normal AppBar is the failure mode that hid the banner
/// defect for days, so the empty case has its own explicit branch and no
/// early-return-paints-nothing path exists.
class PromosListPage extends StatefulWidget {
  const PromosListPage({super.key});

  @override
  State<PromosListPage> createState() => _PromosListPageState();
}

class _PromosListPageState extends State<PromosListPage> {
  /// Last write error already shown, so a rebuild does not re-toast the same
  /// message. Cleared implicitly when a different error arrives.
  String? _shownWriteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PromosCubit>().load();
    });
  }

  Future<void> _openCreate(List<String> types) async {
    final cubit = context.read<PromosCubit>();
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: PromoEditPage(availableTypes: types),
        ),
      ),
    );
    if (created == true && mounted) cubit.load();
  }

  Future<void> _openDetail(AdminPromo promo) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<PromosCubit>(),
          child: PromoDetailPage(promo: promo),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Промокоды'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<PromosCubit>().load(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final s = context.read<PromosCubit>().state;
          _openCreate(s is PromosLoaded ? s.types : const []);
        },
        icon: const Icon(Icons.add),
        label: const Text('Новый промокод'),
      ),
      body: BlocBuilder<PromosCubit, PromosState>(
        builder: (context, state) {
          if (state is PromosLoading || state is PromosInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is PromosFailure) {
            return _Message(
              icon: Icons.error_outline,
              colour: Colors.orange,
              title: 'Не удалось загрузить промокоды',
              body: state.message,
              actionLabel: 'Повторить',
              onAction: () => context.read<PromosCubit>().load(),
            );
          }
          if (state is PromosLoaded && state.items.isEmpty) {
            return _Message(
              icon: Icons.local_offer_outlined,
              colour: Colors.grey,
              title: 'Промокодов пока нет',
              body: 'Создайте первый промокод — он появится здесь.',
              actionLabel: 'Создать',
              onAction: () => _openCreate(state.types),
            );
          }
          if (state is PromosLoaded) {
            // A failed WRITE arrives attached to the loaded list rather than
            // replacing it, so surface it as a snackbar after the frame. Doing
            // it here (not in the cubit) keeps the state layer free of UI.
            final writeError = state.writeError;
            if (writeError != null && writeError != _shownWriteError) {
              _shownWriteError = writeError;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(writeError),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              });
            }
            return RefreshIndicator(
              onRefresh: () => context.read<PromosCubit>().load(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: state.items.length,
                itemBuilder: (_, i) => _PromoTile(
                  promo: state.items[i],
                  onTap: () => _openDetail(state.items[i]),
                  onToggle: (v) =>
                      context.read<PromosCubit>().update(state.items[i].code, enabled: v),
                ),
              ),
            );
          }
          // Unreachable today, but a return that paints nothing is exactly how
          // the banner page went blank. Say so instead.
          return _Message(
            icon: Icons.help_outline,
            colour: Colors.orange,
            title: 'Не удалось показать список',
            body: '${state.runtimeType}',
            actionLabel: 'Обновить',
            onAction: () => context.read<PromosCubit>().load(),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final Color colour;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _Message({
    required this.icon,
    required this.colour,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: colour),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoTile extends StatelessWidget {
  final AdminPromo promo;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  const _PromoTile({
    required this.promo,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      promo.code,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  _StateChip(state: promo.state),
                  Switch(
                    value: promo.enabled,
                    onChanged: onToggle,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                promo.typeLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // Two numbers, labelled, because they are NOT the same thing:
              // one customer can redeem several times.
              Row(
                children: [
                  _Stat(label: 'Применений', value: '${promo.redemptions}'),
                  const SizedBox(width: 20),
                  _Stat(label: 'Клиентов', value: '${promo.customers}'),
                  if (promo.expiresAt != null) ...[
                    const SizedBox(width: 20),
                    _Stat(label: 'Действует до', value: _d(promo.expiresAt!)),
                  ],
                ],
              ),
              if (promo.isTestOnly) ...[
                const SizedBox(height: 8),
                const _Warning(
                  text: 'Тестовый тип: работает только для тестовых '
                      'пользователей — обычные клиенты не смогут его применить.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;
  const _Warning({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: Color(0xFF8D6E00)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6D5200)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final AdminPromoState state;
  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (state) {
      AdminPromoState.live => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      AdminPromoState.expired => (const Color(0xFFF3E5F5), const Color(0xFF6A1B9A)),
      AdminPromoState.disabled => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        state.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
