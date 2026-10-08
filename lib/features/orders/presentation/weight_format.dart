import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/format/money.dart';
import '../models/order_models.dart';

/// Grams as the picker reads them: «300 г», «1 кг», «1,5 кг».
///
/// Grams below 1 kg, kilos at and above, with a comma decimal separator
/// because this is read in Russian. Deliberately NOT the customer app's
/// «300 г / 1,5 кг» label verbatim: the admin needs «до 330 г» style ceilings
/// too, so the formatter is the shared piece and the copy lives at the call
/// site.
String formatGrams(int g) {
  if (g < 1000) return '$g г';
  final kilos = g / 1000;
  // Trim a trailing ,0: «1 кг», not «1,0 кг».
  final s = kilos.toStringAsFixed(1).replaceAll('.', ',');
  return s.endsWith(',0') ? '${s.substring(0, s.length - 2)} кг' : '$s кг';
}

/// The weight-line label from the brief:
/// «Сыр Emsar для пиццы · 300 г · 3 105 ₸/кг · заказ 1 023 ₸ (до 330 г)».
///
/// Every number is the server's. Nothing is derived here — `ordered_g`,
/// `charged_g_cap` and `price_per_kg` all arrive on the line, and the app's job
/// is to display them, not to recompute them (thin client).
String weightLineSummary(OrderItem item) {
  final parts = <String>[];
  if (item.orderedG != null) parts.add(formatGrams(item.orderedG!));
  if (item.pricePerKg != null) {
    parts.add('${formatTenge(item.pricePerKg!)}/кг');
  }
  // The line total is what the customer was charged for this line.
  parts.add('заказ ${formatTenge(item.total)}');
  final cap = item.chargedGCap;
  final tail = cap != null ? ' (до ${formatGrams(cap)})' : '';
  return '${parts.join(' · ')}$tail';
}

/// The picker's scale reading for one weight line, with the live refund hint.
///
/// The hint has three states, and the distinction between them is the whole
/// point of the +10% buffer:
///
///   * below the ordered weight → the customer is owed money:
///     «Вернём клиенту 120 ₸»
///   * between the order and the cap → they already paid for the buffer, so
///     the difference is theirs: «Клиент доплатил заранее, возврат 16 ₸»
///   * above the cap → the cut is too big to accept, and the operator is told
///     exactly how much to take: «Больше лимита, берём только до 330 г»
///
/// `refundPreview` is the SERVER's figure for this line alone. It is an
/// estimate: the order ceiling and earlier refunds apply only at settlement.
/// The wording says «вернём» rather than a bare number for that reason.
class WeightLinePanel extends StatefulWidget {
  final OrderItem item;
  final ValueChanged<int>? onWeightSet;
  final bool busy;
  final double? refundPreview;
  final String? error;
  final bool settled;

  const WeightLinePanel({
    super.key,
    required this.item,
    this.onWeightSet,
    this.busy = false,
    this.refundPreview,
    this.error,
    this.settled = false,
  });

  @override
  State<WeightLinePanel> createState() => _WeightLinePanelState();
}

class _WeightLinePanelState extends State<WeightLinePanel> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    // Seeded from the server's stored reading, so reopening the screen shows
    // what was entered rather than an empty box.
    _ctrl = TextEditingController(
      text: widget.item.actualG?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant WeightLinePanel old) {
    super.didUpdateWidget(old);
    // The parent reloads the order after a save; reflect the authoritative
    // figure rather than keeping what was typed (they agree in the happy path,
    // and the server wins when they do not).
    final server = widget.item.actualG?.toString() ?? '';
    if (widget.item.actualG != old.item.actualG && _ctrl.text != server) {
      _ctrl.text = server;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final g = int.tryParse(_ctrl.text.trim());
    if (g == null) return;
    widget.onWeightSet?.call(g);
  }

  /// The hint for the CURRENTLY TYPED weight.
  ///
  /// Prefers the typed value over the stored one so the operator sees the
  /// consequence before committing — the field is the thing they are looking
  /// at. Falls back to the server's preview once the value is saved.
  String? _hintText(BuildContext context) {
    final cap = widget.item.chargedGCap;
    final ordered = widget.item.orderedG;
    final typed = int.tryParse(_ctrl.text.trim());
    final shown = typed ?? widget.item.actualG;

    if (cap != null && typed != null && typed > cap) {
      return 'Больше лимита, берём только до ${formatGrams(cap)}';
    }
    if (shown == null || ordered == null) return null;

    final preview = widget.refundPreview;
    if (preview == null) return null;
    if (preview <= 0.005) return null;

    if (shown < ordered) {
      return 'Вернём клиенту ${formatTenge(preview.toStringAsFixed(2))}';
    }
    return 'Клиент доплатил заранее, возврат '
        '${formatTenge(preview.toStringAsFixed(2))}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final editable = widget.onWeightSet != null && !widget.settled;

    final cap = item.chargedGCap;
    final typed = int.tryParse(_ctrl.text.trim());
    final overCap = cap != null && typed != null && typed > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A1: the weight line, never «N шт».
        Text(
          weightLineSummary(item),
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),

        if (editable)
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _ctrl,
                  enabled: !widget.busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                    signed: false,
                  ),
                  // Digits only: a scale reads whole grams, and the server
                  // rejects a non-integer with 422 rather than rounding it.
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Факт, г',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: overCap ? ' ' : null,
                    errorStyle: const TextStyle(fontSize: 0, height: 0),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton(
                  // Above the cap the server will refuse, so the button is
                  // disabled rather than letting the operator submit a weight
                  // that cannot be saved.
                  onPressed: (typed == null || overCap) ? null : _submit,
                  child: const Text('Сохранить'),
                ),
            ],
          )
        else if (item.actualG != null)
          Row(
            children: [
              Text(
                'Факт: ${formatGrams(item.actualG!)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.settled) ...[
                const SizedBox(width: 8),
                Text(
                  'расчёт выполнен',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),

        // A2: the live hint under the field.
        Builder(
          builder: (_) {
            final hint = _hintText(context);
            if (hint == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                hint,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: overCap ? scheme.error : scheme.primary,
                ),
              ),
            );
          },
        ),

        // The server's reason for refusing a weight, shown in place.
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.error!,
              style: TextStyle(fontSize: 12.5, color: scheme.error),
            ),
          ),
      ],
    );
  }
}
