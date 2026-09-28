import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/promo_repository.dart';
import '../state/promos_cubit.dart';

/// Create a promo code.
///
/// The type picker is built from [availableTypes], which the list page got from
/// the SERVER's `/admin/promos/types`. Nothing is hardcoded here: if the engine
/// gains a discount type, it appears in this dropdown with no app release, and
/// if it loses one this screen stops offering it.
class PromoEditPage extends StatefulWidget {
  final List<String> availableTypes;

  const PromoEditPage({super.key, required this.availableTypes});

  @override
  State<PromoEditPage> createState() => _PromoEditPageState();
}

class _PromoEditPageState extends State<PromoEditPage> {
  final _codeCtrl = TextEditingController();
  String? _type;
  bool _enabled = true;
  DateTime? _expiresAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.availableTypes.isNotEmpty ? widget.availableTypes.first : null;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Mirror the server's rules so the operator is told before the round trip.
  /// The server still enforces both — this only keeps their typing on screen.
  String? _validate() {
    final code = _codeCtrl.text.trim();
    if (code.length < 3) return 'Код должен быть не короче 3 символов';
    if (code.length > 64) return 'Код слишком длинный (максимум 64)';
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(code)) {
      return 'Только латинские буквы, цифры, дефис и подчёркивание';
    }
    if (_type == null || _type!.isEmpty) return 'Выберите тип промокода';
    if (_expiresAt != null && !_expiresAt!.isAfter(DateTime.now())) {
      return 'Дата окончания должна быть в будущем';
    }
    return null;
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresAt ?? now),
    );
    if (!mounted) return;
    setState(() {
      _expiresAt = DateTime(date.year, date.month, date.day, time?.hour ?? 23,
          time?.minute ?? 59);
    });
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<PromosCubit>().create(
            code: _codeCtrl.text.trim().toUpperCase(),
            promoType: _type!,
            enabled: _enabled,
            expiresAt: _expiresAt,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PromoValidationException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось создать: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = widget.availableTypes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый промокод'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Создать'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Код',
              helperText: 'Клиент вводит его в корзине. Латиница, без пробелов.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (types.isEmpty)
            const _Info(
              text: 'Не удалось получить список типов промокодов от сервера, '
                  'поэтому создать код нельзя. Обновите список и попробуйте снова.',
            )
          else
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Тип промокода',
                border: OutlineInputBorder(),
              ),
              items: types
                  .map((t) => DropdownMenuItem(value: t, child: Text(_label(t))))
                  .toList(),
              onChanged: (v) => setState(() => _type = v),
            ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            title: const Text('Включён'),
            subtitle: const Text('Выключенный код клиент применить не сможет'),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Действует до'),
            subtitle: Text(_expiresAt == null ? 'Без ограничения' : _fmt(_expiresAt!)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_expiresAt != null)
                  IconButton(
                    tooltip: 'Убрать дату',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _expiresAt = null),
                  ),
                IconButton(
                  tooltip: 'Выбрать дату',
                  icon: const Icon(Icons.event),
                  onPressed: _pickExpiry,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Say plainly what this type does, using the engine's real semantics.
          if (_type == 'FREE_DELIVERY_FIRST_ORDER')
            const _Info(
              text: 'Бесплатная доставка для первого заказа. Клиент может '
                  'применить код один раз — повторная попытка вернёт «уже использован».',
            )
          else if (_type == 'FREE_DELIVERY_TEST_UNLIMITED')
            const _Warning(
              text: 'ВНИМАНИЕ: тестовый тип. Работает только для аккаунтов из '
                  'белого списка на сервере. Обычные клиенты получат отказ — '
                  'для кампании этот тип не подходит.',
            ),
        ],
      ),
    );
  }

  static String _label(String type) => switch (type) {
        'FREE_DELIVERY_FIRST_ORDER' => 'Бесплатная доставка (первый заказ)',
        'FREE_DELIVERY_TEST_UNLIMITED' => 'Тестовый: доставка без ограничений',
        _ => type,
      };
}

class _Info extends StatelessWidget {
  final String text;
  const _Info({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;
  const _Warning({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined, size: 16, color: Color(0xFF8D6E00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6D5200))),
          ),
        ],
      ),
    );
  }
}
