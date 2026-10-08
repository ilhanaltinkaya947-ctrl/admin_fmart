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
  // Up to three decimals, trailing zeros trimmed: «1 кг», «1,5 кг», and
  // «1,05 кг» for a 1 050 g cap. One decimal would round that cap to «1,1 кг»,
  // which is a weight the picker must NOT cut to.
  var s = (g / 1000).toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return '${s.replaceAll('.', ',')} кг';
}

/// The range the picker must hit: «Нужно: от 300 г до 315 г».
///
/// Both ends are the server's: `ordered_g` and `charged_g_cap`. The cap is
/// floor(ordered_g × 105 / 100) in order-service (`weight_settle.py`), and it is
/// never recomputed here.
String weightTargetText(int orderedG, int capG) =>
    'Нужно: от ${formatGrams(orderedG)} до ${formatGrams(capG)}';

/// The over-cap confirm: «Сохранить 330 г? Клиент заплатит только за 315 г,
/// остальное за счёт магазина.» True only on «Сохранить».
String overCapConfirmText(int actualG, int capG) =>
    'Сохранить ${formatGrams(actualG)}? Клиент заплатит только за '
    '${formatGrams(capG)}, остальное за счёт магазина.';

Future<bool?> confirmOverCapWeight(
  BuildContext context, {
  required int actualG,
  required int capG,
}) =>
    showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(overCapConfirmText(actualG, capG)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Сохранить'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

/// The refund «Сборка завершена» is about to send, for the confirm sheet.
///
/// An ESTIMATE, which is why the sheet says «примерно»: the server nets earlier
/// settlements and clamps to the capture. Per weighed line it takes the
/// server's own preview from the weight PUT when this screen has one, else the
/// settle formula from order-service `weight_settle.py`:
///   paid  = price × qty + buffer_amount
///   final = floor(price_per_kg × min(actual_g, charged_g_cap) / 1000)
///   line  = max(0, paid − final)
double estimateWeightRefund(
  Iterable<OrderItem> items, {
  Map<int, double> previews = const {},
}) {
  var sum = 0.0;
  for (final it in items) {
    if (!it.isWeightLine || it.actualG == null) continue;
    final preview = previews[it.id];
    if (preview != null) {
      sum += preview < 0 ? 0 : preview;
      continue;
    }
    final price = double.tryParse(it.price) ?? 0;
    final buffer = double.tryParse(it.bufferAmount ?? '') ?? 0;
    final perKg = double.tryParse(it.pricePerKg ?? '') ?? 0;
    final paid = price * it.qty + buffer;
    final billable =
        it.actualG! < it.chargedGCap! ? it.actualG! : it.chargedGCap!;
    final fin = (perKg * billable / 1000).floorToDouble();
    final line = paid - fin;
    if (line > 0) sum += line;
  }
  return (sum * 100).roundToDouble() / 100;
}

/// The body of the settle confirm.
String settleConfirmBody(double amount) => amount > 0.005
    ? 'Вернём клиенту примерно ${formatTenge(amount.toStringAsFixed(2))} '
        'за вес. После этого вес изменить нельзя.'
    : 'Возврат за вес не нужен. После этого вес изменить нельзя.';

/// «Завершить сборку?» sheet before the one action that moves weight money.
/// True only on «Завершить».
Future<bool?> confirmSettleWeights(BuildContext context, double amount) =>
    showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Завершить сборку?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                settleConfirmBody(amount),
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Завершить'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      ),
    );

/// The settle bar once the SERVER says the order is settled:
/// «Расчёт выполнен · Возврат 98 ₸». No amount, or zero, reads «Расчёт
/// выполнен» alone rather than promising «Возврат 0 ₸».
String settledBarText(String? weightRefundAmount) {
  final n = double.tryParse((weightRefundAmount ?? '').trim());
  if (n == null || n <= 0.005) return 'Расчёт выполнен';
  return 'Расчёт выполнен · Возврат ${formatTenge(n.toStringAsFixed(2))}';
}

/// How a typed or stored reading compares with the order.
enum WeightCheck { none, under80, underOrder, inRange, overCap }

/// Classify [actualG] against the order. Under 80% wins over «under order»:
/// it needs a phone call, not just a top-up.
WeightCheck weightCheck({int? actualG, int? orderedG, int? capG}) {
  if (actualG == null || orderedG == null) return WeightCheck.none;
  // Integer arithmetic: actual < 0.8 × ordered, without a float edge at 80%.
  if (actualG * 5 < orderedG * 4) return WeightCheck.under80;
  if (actualG < orderedG) return WeightCheck.underOrder;
  if (capG != null && actualG > capG) return WeightCheck.overCap;
  return WeightCheck.inRange;
}

/// The amber line for a cut below the order: «Меньше заказа на 30 г. Довесьте
/// до 300 г».
String weightUnderOrderText(int actualG, int orderedG) =>
    'Меньше заказа на ${orderedG - actualG} г. '
    'Довесьте до ${formatGrams(orderedG)}';

const String kWeightUnder80Text = 'Меньше 80% заказа. Позвоните клиенту';

/// Amber for «under the order»: a warning, not an error. Dark enough to read
/// on white (amber 800).
const Color kWeightAmber = Color(0xFFB45309);

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
/// point of the +5% buffer:
///
///   * below the ordered weight → the customer is owed money:
///     «Вернём клиенту 120 ₸»
///   * between the order and the cap → they already paid for the buffer, so
///     the difference is theirs: «Клиент доплатил заранее, возврат 16 ₸»
///   * above the cap → ALLOWED (Ilhan 08.10): saving asks first, «Сохранить
///     330 г? Клиент заплатит только за 315 г, остальное за счёт магазина.»
///     The server bills at most the cap, so the true weight is recorded and
///     the store absorbs the rest.
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

  /// The customer's phone, shown with «Скопировать номер» when a cut falls
  /// under 80% of the order. Null or empty hides the number, never the warning.
  final String? customerPhone;

  /// Removes the line from the order (the card's existing «Удалить», which
  /// confirms and refunds the line). Shown only while the weight can still
  /// change: an unweighed cheese that is not on the shelf must be removable,
  /// or the order can never be settled.
  final VoidCallback? onRemove;

  /// True while a remove or another edit of this line is in flight.
  final bool removeBusy;

  const WeightLinePanel({
    super.key,
    required this.item,
    this.onWeightSet,
    this.busy = false,
    this.refundPreview,
    this.error,
    this.settled = false,
    this.customerPhone,
    this.onRemove,
    this.removeBusy = false,
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

  Future<void> _submit() async {
    final g = int.tryParse(_ctrl.text.trim());
    if (g == null) return;
    final cap = widget.item.chargedGCap;
    if (cap != null && g > cap) {
      final ok = await confirmOverCapWeight(context, actualG: g, capG: cap);
      if (ok != true || !mounted) return;
    }
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

    if (cap != null && shown != null && shown > cap) return null;
    if (shown == null || ordered == null) return null;
    // Below the order is a rule broken, not a refund to announce: the amber
    // and red warnings below say so, and this hint stays out of their way.
    if (shown < ordered) return null;

    final preview = widget.refundPreview;
    if (preview == null) return null;
    if (preview <= 0.005) return null;

    return 'Клиент доплатил заранее, возврат '
        '${formatTenge(preview.toStringAsFixed(2))}';
  }

  /// The reading the warnings judge: what is typed, else what is stored.
  int? get _shownG =>
      int.tryParse(_ctrl.text.trim()) ?? widget.item.actualG;

  Future<void> _copyPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Номер скопирован')),
    );
  }

  Widget _under80Block(ColorScheme scheme) {
    final phone = (widget.customerPhone ?? '').trim();
    return Container(
      key: const ValueKey('weight-under80'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_outlined, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  kWeightUnder80Text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  phone,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // No «Позвонить»: the admin app has no url_launcher, and an
                // iPad without a SIM cannot place the call anyway. The picker
                // copies the number to a phone.
                OutlinedButton.icon(
                  onPressed: () => _copyPhone(phone),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Скопировать номер'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final editable = widget.onWeightSet != null && !widget.settled;

    final cap = item.chargedGCap;
    final typed = int.tryParse(_ctrl.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A1: the weight line, never «N шт».
        Text(
          weightLineSummary(item),
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        // The range to hit, while there is still a cut to make.
        if (editable && item.orderedG != null && cap != null) ...[
          const SizedBox(height: 4),
          Text(
            weightTargetText(item.orderedG!, cap),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
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
                  ),
                  // Rebuild on every keystroke so the warnings below follow
                  // the figure being typed, not the last one saved.
                  onChanged: (_) => setState(() {}),
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
                  // Above the cap is allowed: _submit asks first. Never
                  // disabled for weight, or a candy portion that cannot be
                  // trimmed forces the picker to type a false figure.
                  onPressed: typed == null ? null : _submit,
                  child: const Text('Сохранить'),
                ),
              if (widget.onRemove != null) ...[
                const Spacer(),
                IconButton(
                  tooltip: 'Удалить',
                  onPressed:
                      (widget.busy || widget.removeBusy) ? null : widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red.shade600,
                  iconSize: 20,
                ),
              ],
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
                  color: scheme.primary,
                ),
              ),
            );
          },
        ),

        // Under the order: amber, top up. Under 80%: red, call the customer.
        // Only while the weight can still change; on a frozen order the cut
        // is made and the instruction can no longer help.
        if (editable)
          Builder(
            builder: (_) {
              final shown = _shownG;
              switch (weightCheck(
                actualG: shown,
                orderedG: item.orderedG,
                capG: cap,
              )) {
                case WeightCheck.under80:
                  return _under80Block(scheme);
                case WeightCheck.underOrder:
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      weightUnderOrderText(shown!, item.orderedG!),
                      key: const ValueKey('weight-under-order'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kWeightAmber,
                      ),
                    ),
                  );
                default:
                  return const SizedBox.shrink();
              }
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
