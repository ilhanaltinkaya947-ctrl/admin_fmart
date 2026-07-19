import 'package:flutter/material.dart';

/// One delivery-slot template for a store.
///
/// Mirrors order-service `TemplateOut`. Times come back as 'HH:MM:SS'
/// strings from FastAPI; we parse to TimeOfDay because the editor needs
/// a TimeOfDay-shaped value.
class DeliverySlotTemplate {
  final int id;
  final int storeId;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int slotDurationMinutes;
  final int slotCap;
  final List<int>? daysOfWeek; // null = every day; else 1..7 ISO
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DeliverySlotTemplate({
    required this.id,
    required this.storeId,
    required this.startTime,
    required this.endTime,
    required this.slotDurationMinutes,
    required this.slotCap,
    required this.daysOfWeek,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DeliverySlotTemplate.fromJson(Map<String, dynamic> j) {
    return DeliverySlotTemplate(
      id: (j['id'] as num).toInt(),
      storeId: (j['store_id'] as num).toInt(),
      startTime: _parseTime(j['start_time'] as String),
      endTime: _parseTime(j['end_time'] as String),
      slotDurationMinutes: (j['slot_duration_minutes'] as num).toInt(),
      slotCap: (j['slot_cap'] as num).toInt(),
      daysOfWeek: (j['days_of_week'] as List?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      isActive: j['is_active'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Human-friendly summary for the list-row trailing slot count.
  /// e.g. "08:00–11:00 · 60 мин · до 15 заказов".
  String summary() {
    return '${_fmt(startTime)}–${_fmt(endTime)} · '
        '$slotDurationMinutes мин · до $slotCap заказов';
  }

  /// "Каждый день" / "Будни" / "Пн, Вт, Ср".
  String daysLabel() {
    if (daysOfWeek == null) return 'Каждый день';
    final s = daysOfWeek!.toSet();
    if (s.length == 5 && s.containsAll({1, 2, 3, 4, 5})) return 'Будни';
    if (s.length == 2 && s.containsAll({6, 7})) return 'Выходные';
    const names = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return daysOfWeek!.map((d) => names[d]).join(', ');
  }
}

TimeOfDay _parseTime(String hhmmss) {
  // Accept both 'HH:MM' and 'HH:MM:SS'.
  final parts = hhmmss.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
  );
}

String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Payload used by the create sheet — sent to POST /admin/delivery-slots/templates.
class TemplateDraft {
  final int storeId;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int slotDurationMinutes;
  final int slotCap;
  final List<int>? daysOfWeek;
  final bool isActive;

  TemplateDraft({
    required this.storeId,
    required this.startTime,
    required this.endTime,
    required this.slotDurationMinutes,
    required this.slotCap,
    this.daysOfWeek,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'store_id': storeId,
        'start_time': _fmt(startTime),
        'end_time': _fmt(endTime),
        'slot_duration_minutes': slotDurationMinutes,
        'slot_cap': slotCap,
        if (daysOfWeek != null) 'days_of_week': daysOfWeek,
        'is_active': isActive,
      };
}

/// Patch payload — only fields actually changing.
class TemplatePatch {
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final int? slotDurationMinutes;
  final int? slotCap;
  final List<int>? daysOfWeek;
  final bool? isActive;

  // We need to distinguish "user cleared days_of_week → null" from
  // "user didn't touch it → leave alone". `daysOfWeekSet` is true when
  // the form intends to send the field.
  final bool daysOfWeekSet;

  TemplatePatch({
    this.startTime,
    this.endTime,
    this.slotDurationMinutes,
    this.slotCap,
    this.daysOfWeek,
    this.isActive,
    this.daysOfWeekSet = false,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (startTime != null) m['start_time'] = _fmt(startTime!);
    if (endTime != null) m['end_time'] = _fmt(endTime!);
    if (slotDurationMinutes != null) {
      m['slot_duration_minutes'] = slotDurationMinutes;
    }
    if (slotCap != null) m['slot_cap'] = slotCap;
    if (daysOfWeekSet) m['days_of_week'] = daysOfWeek;
    if (isActive != null) m['is_active'] = isActive;
    return m;
  }
}
