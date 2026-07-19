import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton_list.dart';
import '../../auth/state/auth_cubit.dart';
import '../data/template_models.dart';
import '../state/slot_templates_cubit.dart';
import 'slot_template_edit_sheet.dart';

class SlotTemplatesListPage extends StatefulWidget {
  final int storeId;
  final String storeName;
  const SlotTemplatesListPage({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<SlotTemplatesListPage> createState() => _SlotTemplatesListPageState();
}

class _SlotTemplatesListPageState extends State<SlotTemplatesListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SlotTemplatesCubit>().load(widget.storeId);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SlotTemplatesListPage old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId) {
      context.read<SlotTemplatesCubit>().load(widget.storeId);
    }
  }

  Future<void> _openCreate() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SlotTemplateEditSheet(storeId: widget.storeId),
    );
    if (saved == true && mounted) {
      context.read<SlotTemplatesCubit>().load(widget.storeId);
    }
  }

  Future<void> _openEdit(DeliverySlotTemplate t) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SlotTemplateEditSheet(
        storeId: widget.storeId,
        existing: t,
      ),
    );
    if (saved == true && mounted) {
      context.read<SlotTemplatesCubit>().load(widget.storeId);
    }
  }

  Future<void> _confirmDelete(DeliverySlotTemplate t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить шаблон?'),
        content: Text(
          '${t.summary()}\n\n'
          'Существующие заказы в этих слотах сохранятся, но новые слоты по '
          'этому шаблону больше не будут создаваться.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await context.read<SlotTemplatesCubit>().remove(t.id, widget.storeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Шаблон удалён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthCubit>().state;
    final canEdit = auth is Authenticated && auth.user.isStaff;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Слоты доставки'),
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
            onPressed: () =>
                context.read<SlotTemplatesCubit>().load(widget.storeId),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: const Text('Новый слот'),
            )
          : null,
      body: !canEdit
          ? const _RoleBlocked()
          : BlocBuilder<SlotTemplatesCubit, SlotTemplatesState>(
              builder: (ctx, state) {
                if (state is SlotTemplatesLoading ||
                    state is SlotTemplatesInitial) {
                  return const SkeletonList();
                }
                if (state is SlotTemplatesFailure) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    title: 'Не удалось загрузить шаблоны',
                    subtitle: state.message,
                    action: FilledButton.tonal(
                      onPressed: () => context
                          .read<SlotTemplatesCubit>()
                          .load(widget.storeId),
                      child: const Text('Повторить'),
                    ),
                  );
                }
                if (state is SlotTemplatesLoaded) {
                  if (state.items.isEmpty) {
                    return EmptyState(
                      icon: Icons.schedule_outlined,
                      title: 'Нет шаблонов слотов',
                      subtitle:
                          'Добавьте первый временной диапазон, чтобы клиенты '
                          'могли выбирать время доставки на оформлении.',
                      action: FilledButton(
                        onPressed: _openCreate,
                        child: const Text('Создать первый'),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        context.read<SlotTemplatesCubit>().load(widget.storeId),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                      itemCount: state.items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = state.items[i];
                        return _TemplateCard(
                          template: t,
                          onEdit: () => _openEdit(t),
                          onDelete: () => _confirmDelete(t),
                        );
                      },
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final DeliverySlotTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = template.isActive
        ? null
        : cs.onSurfaceVariant.withValues(alpha: 0.6);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 56,
                decoration: BoxDecoration(
                  color: template.isActive ? cs.primary : cs.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_fmt(template.startTime)} – ${_fmt(template.endTime)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Chip(
                          label: '${template.slotDurationMinutes} мин',
                          icon: Icons.timer_outlined,
                        ),
                        _Chip(
                          label: 'до ${template.slotCap}',
                          icon: Icons.shopping_bag_outlined,
                        ),
                        _Chip(
                          label: template.daysLabel(),
                          icon: Icons.calendar_month_outlined,
                        ),
                        if (!template.isActive)
                          const _Chip(
                            label: 'выключен',
                            icon: Icons.toggle_off_outlined,
                            tone: _Tone.warn,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Удалить',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

enum _Tone { neutral, warn }

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final _Tone tone;
  const _Chip({
    required this.label,
    required this.icon,
    this.tone = _Tone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = tone == _Tone.warn ? Colors.orange.shade50 : cs.surfaceContainerHighest;
    final fg = tone == _Tone.warn ? Colors.orange.shade800 : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}

class _RoleBlocked extends StatelessWidget {
  const _RoleBlocked();
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
              'Управление слотами — для менеджеров и администраторов',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
