import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/template_models.dart';
import '../state/slot_templates_cubit.dart';

const _kDurationChoices = [15, 30, 45, 60, 90, 120, 180];
const _kDayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

class SlotTemplateEditSheet extends StatefulWidget {
  final int storeId;
  final DeliverySlotTemplate? existing;

  const SlotTemplateEditSheet({
    super.key,
    required this.storeId,
    this.existing,
  });

  @override
  State<SlotTemplateEditSheet> createState() => _SlotTemplateEditSheetState();
}

class _SlotTemplateEditSheetState extends State<SlotTemplateEditSheet> {
  late TimeOfDay _start;
  late TimeOfDay _end;
  late int _duration;
  late int _cap;
  late bool _everyDay;
  late Set<int> _days; // ISO 1..7
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _start = e?.startTime ?? const TimeOfDay(hour: 10, minute: 0);
    _end = e?.endTime ?? const TimeOfDay(hour: 14, minute: 0);
    _duration = e?.slotDurationMinutes ?? 60;
    _cap = e?.slotCap ?? 15;
    _everyDay = e?.daysOfWeek == null;
    _days = e?.daysOfWeek?.toSet() ?? {1, 2, 3, 4, 5, 6, 7};
    _isActive = e?.isActive ?? true;
  }

  bool get _isEdit => widget.existing != null;

  int get _windowMinutes {
    final s = _start.hour * 60 + _start.minute;
    final e = _end.hour * 60 + _end.minute;
    return e - s;
  }

  String? get _validationError {
    if (_windowMinutes <= 0) return 'Окончание должно быть позже начала';
    if (_windowMinutes < _duration) {
      return 'Окно ($_windowMinutes мин) короче слота ($_duration мин)';
    }
    if (!_everyDay && _days.isEmpty) {
      return 'Выберите хотя бы один день недели';
    }
    return null;
  }

  int get _slotsGenerated => _windowMinutes ~/ _duration;

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      builder: (ctx, child) => MediaQuery(
        // Force 24h mode — KZ + RU convention, matches the rest of admin.
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_validationError != null) return;
    setState(() => _saving = true);

    final days = _everyDay ? null : (_days.toList()..sort());
    try {
      final cubit = context.read<SlotTemplatesCubit>();
      if (_isEdit) {
        await cubit.update(
          widget.existing!.id,
          TemplatePatch(
            startTime: _start,
            endTime: _end,
            slotDurationMinutes: _duration,
            slotCap: _cap,
            daysOfWeek: days,
            daysOfWeekSet: true,
            isActive: _isActive,
          ),
          widget.storeId,
        );
      } else {
        await cubit.create(TemplateDraft(
          storeId: widget.storeId,
          startTime: _start,
          endTime: _end,
          slotDurationMinutes: _duration,
          slotCap: _cap,
          daysOfWeek: days,
          isActive: _isActive,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final err = _validationError;
    final saveable = err == null && !_saving;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Drag handle + title strip
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 4, bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEdit ? 'Изменить слот' : 'Новый слот',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                _section('Время'),
                Row(
                  children: [
                    Expanded(
                      child: _TimeField(
                        label: 'Начало',
                        value: _start,
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeField(
                        label: 'Конец',
                        value: _end,
                        onTap: () => _pickTime(isStart: false),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                _section('Длительность слота'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kDurationChoices.map((d) {
                    final sel = d == _duration;
                    return ChoiceChip(
                      label: Text('$d мин'),
                      selected: sel,
                      onSelected: (_) => setState(() => _duration = d),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),
                _section('Максимум заказов в слоте'),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _cap > 1 ? () => setState(() => _cap--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '$_cap',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed:
                          _cap < 500 ? () => setState(() => _cap++) : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                Text(
                  '80 % порог («осталось мало мест») — при ${(_cap * 0.8).floor()} '
                  'заказах. Скрытие слота при $_cap.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),
                _section('Дни'),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Каждый день'),
                  value: _everyDay,
                  onChanged: (v) => setState(() => _everyDay = v),
                ),
                if (!_everyDay)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (i) {
                      final iso = i + 1;
                      final sel = _days.contains(iso);
                      return FilterChip(
                        label: Text(_kDayNames[i]),
                        selected: sel,
                        onSelected: (s) {
                          setState(() {
                            if (s) {
                              _days.add(iso);
                            } else {
                              _days.remove(iso);
                            }
                          });
                        },
                      );
                    }),
                  ),

                const SizedBox(height: 24),
                _section('Состояние'),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Шаблон активен'),
                  subtitle: Text(
                    _isActive
                        ? 'Слоты из этого шаблона будут выдаваться клиентам'
                        : 'Слоты не выдаются, но шаблон сохранён',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),

                const SizedBox(height: 16),
                // Live preview of how many slots this generates
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          err ??
                              'Будет создаваться $_slotsGenerated '
                                  '${_slotsGenerated == 1 ? 'слот' : 'слотов'} '
                                  'в день по этому шаблону',
                          style: TextStyle(
                            fontSize: 13,
                            color: err == null ? cs.onSurfaceVariant : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: saveable ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isEdit ? 'Сохранить' : 'Создать'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '${value.hour.toString().padLeft(2, '0')}:'
              '${value.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
