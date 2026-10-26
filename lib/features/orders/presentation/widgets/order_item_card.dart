import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/format/money.dart';
import '../../models/order_models.dart';
import '../weight_format.dart';

/// What the picker chose in a line's «Проверьте наличие ▾» (26.10).
enum StockAnswer { present, missing, reset }

/// Card row for one order item.
/// Shows image, name, barcode (copyable), qty x price, line total.
/// When [editable] is true, shows +/- and remove controls.
///
/// A weight line (see [OrderItem.isWeightLine]) renders differently throughout:
/// its quantity is a weight, not a count, so «N шт» would be a lie, and it
/// carries the picker's «Факт, г» input instead of the ± stepper.
class OrderItemCard extends StatelessWidget {
  final OrderItem item;
  final bool editable;
  final bool busy;
  final ValueChanged<int>? onQtyChange;
  final VoidCallback? onRemove;
  // When non-null, shows a leading "picked" checkbox. Tapping it
  // toggles the pick state via this callback (true = mark picked).
  final ValueChanged<bool>? onPickedToggle;
  final bool pickedBusy;

  /// Called with the grams the picker typed. Null hides the field entirely
  /// (a settled order, or a caller that does not weigh).
  final ValueChanged<int>? onWeightSet;

  /// True while the weight PUT is in flight, so the field locks and shows a
  /// spinner rather than accepting a second reading.
  final bool weightBusy;

  /// What the server said this line alone would return, once a weight is in.
  /// Shown as the live hint under the field.
  final double? refundPreview;

  /// Set when the last attempt to save a weight was refused, so the operator
  /// sees the server's reason next to the field rather than a passing snackbar.
  final String? weightError;

  /// True once the order has been settled: weights are frozen by the server
  /// (a corrected figure would no longer match the money that went back), so
  /// the field is disabled and says so.
  final bool settled;

  /// The customer's phone, for the under-80% call prompt on a weight line.
  final String? customerPhone;

  /// «Проверьте наличие ▾» (26.10). Null shows the line's verdict read-only
  /// (the order is past picking). Only used when the line has a `stockCheck`;
  /// without one (older server) the card is exactly as before.
  final ValueChanged<StockAnswer>? onStockAnswer;

  /// False hides «Нет в наличии» from the menu (a substitution is already
  /// waiting on the customer for this line).
  final bool canMarkMissing;

  /// True while a stock answer for this line is being saved.
  final bool stockBusy;

  const OrderItemCard({
    super.key,
    required this.item,
    this.editable = false,
    this.busy = false,
    this.onQtyChange,
    this.onRemove,
    this.onPickedToggle,
    this.pickedBusy = false,
    this.onWeightSet,
    this.weightBusy = false,
    this.refundPreview,
    this.weightError,
    this.settled = false,
    this.customerPhone,
    this.onStockAnswer,
    this.canMarkMissing = true,
    this.stockBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = item.product.name ?? 'Товар ${item.productId}';
    final showPicker = onPickedToggle != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: item.isPicked
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.35)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPicker) ...[
              _PickedToggle(
                checked: item.isPicked,
                busy: pickedBusy,
                onToggle: (v) => onPickedToggle!(v),
              ),
              const SizedBox(width: 4),
            ],
            _Thumbnail(imageUrl: item.product.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 26.10: a line with the server's verdict gets the
                      // dropdown; without one (older server) the old badge.
                      if (item.stockCheck != null)
                        _StockCheckDropdown(
                          check: item.stockCheck!,
                          onAnswer: onStockAnswer,
                          canMarkMissing: canMarkMissing,
                          busy: stockBusy,
                        )
                      else
                        _StockBadge(inStock: item.product.inStock),
                    ],
                  ),
                  // Why it is worth a look, only while nobody has answered.
                  if (item.stockCheck?.unanswered == true &&
                      item.stockCheck!.reasons.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '⚠ ${item.stockCheck!.reasons.join(' · ')}',
                      key: const ValueKey('stock-check-reasons'),
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (item.product.sku != null && item.product.sku!.isNotEmpty)
                    _BarcodeChip(sku: item.product.sku!),
                  const SizedBox(height: 8),
                  if (item.isWeightLine)
                    WeightLinePanel(
                      item: item,
                      onWeightSet: onWeightSet,
                      busy: weightBusy,
                      refundPreview: refundPreview,
                      error: weightError,
                      settled: settled,
                      customerPhone: customerPhone,
                      // Same «Удалить» as a piece line, only while editable.
                      onRemove: editable ? onRemove : null,
                      removeBusy: busy,
                    )
                  else if (editable)
                    _EditableQtyRow(
                      qty: item.qty,
                      price: item.price,
                      total: item.total,
                      busy: busy,
                      onQtyChange: onQtyChange,
                      onRemove: onRemove,
                    )
                  else
                    Row(
                      children: [
                        _MetaPill(
                          icon: Icons.format_list_numbered,
                          label: '${item.qty} шт',
                        ),
                        const SizedBox(width: 8),
                        _MetaPill(
                          icon: Icons.attach_money,
                          label: formatTenge(item.price),
                        ),
                        const Spacer(),
                        Text(
                          formatTenge(item.total),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableQtyRow extends StatelessWidget {
  final int qty;
  final String price;
  final String total;
  final bool busy;
  final ValueChanged<int>? onQtyChange;
  final VoidCallback? onRemove;

  const _EditableQtyRow({
    required this.qty,
    required this.price,
    required this.total,
    required this.busy,
    required this.onQtyChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _QtyStepper(
          qty: qty,
          busy: busy,
          onChange: onQtyChange,
        ),
        const SizedBox(width: 8),
        _MetaPill(icon: Icons.attach_money, label: formatTenge(price)),
        const Spacer(),
        Text(
          formatTenge(total),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Удалить',
          onPressed: busy ? null : onRemove,
          icon: const Icon(Icons.delete_outline),
          color: Colors.red.shade600,
          iconSize: 20,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int qty;
  final bool busy;
  final ValueChanged<int>? onChange;

  const _QtyStepper({
    required this.qty,
    required this.busy,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = busy || onChange == null;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: disabled || qty <= 1
                ? null
                : () => onChange!(qty - 1),
            icon: const Icon(Icons.remove),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            // 44 is the platform minimum. These are used one-handed, standing,
            // pushing a trolley, and the left one moves money.
            constraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            padding: EdgeInsets.zero,
          ),
          SizedBox(
            width: 36,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '$qty',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          IconButton(
            onPressed: disabled ? null : () => onChange!(qty + 1),
            icon: const Icon(Icons.add),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            // 44 is the platform minimum. These are used one-handed, standing,
            // pushing a trolley, and the left one moves money.
            constraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? imageUrl;
  const _Thumbnail({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.shopping_basket_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _BarcodeChip extends StatelessWidget {
  final String sku;
  const _BarcodeChip({required this.sku});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: sku));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Штрих-код $sku скопирован'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.qr_code_2,
                size: 16,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              SelectableText(
                sku,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.copy,
                size: 14,
                color: theme.colorScheme.onPrimaryContainer
                    .withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickedToggle extends StatelessWidget {
  final bool checked;
  final bool busy;
  final ValueChanged<bool> onToggle;

  const _PickedToggle({
    required this.checked,
    required this.busy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 40,
      height: 56,
      child: Center(
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : InkResponse(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onToggle(!checked);
                },
                radius: 24,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: checked ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: checked ? scheme.primary : scheme.outline,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: checked
                      ? Icon(Icons.check, size: 20, color: scheme.onPrimary)
                      : null,
                ),
              ),
      ),
    );
  }
}

/// The catalog's yes/no, for a line without a server verdict (older
/// order-service). Exactly the pre-26.10 badge.
class _StockBadge extends StatelessWidget {
  final bool inStock;
  const _StockBadge({required this.inStock});

  @override
  Widget build(BuildContext context) {
    final MaterialColor tone = inStock ? Colors.green : Colors.red;
    final label = inStock ? 'В наличии' : 'Нет';
    return Container(
      key: ValueKey('stock-badge-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(inStock ? Icons.check_circle : Icons.cancel, size: 12, color: tone.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: tone.shade800, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// «Проверьте наличие ▾» (26.10): the line's verdict as a chip that opens the
/// picker's answers. «В наличии» and «Сбросить ответ» are a plain POST;
/// «Нет в наличии» is handed to the page, which runs the out-of-stock flow
/// (it moves money and hides the product, so it keeps its own confirmations).
///
/// A «нет» is read-only: it came with a substitution or a refund and a hold,
/// which a menu tap here cannot undo.
class _StockCheckDropdown extends StatelessWidget {
  final StockCheck check;
  final ValueChanged<StockAnswer>? onAnswer;
  final bool canMarkMissing;
  final bool busy;

  const _StockCheckDropdown({
    required this.check,
    required this.onAnswer,
    required this.canMarkMissing,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final (MaterialColor tone, IconData icon, String label) = check.missing
        ? (Colors.red, Icons.cancel, 'Нет в наличии')
        : check.confirmed
            ? (Colors.green, Icons.check_circle, 'В наличии')
            : (Colors.orange, Icons.help, 'Проверьте наличие');

    final options = <StockAnswer>[
      if (!check.confirmed) StockAnswer.present,
      if (canMarkMissing) StockAnswer.missing,
      if (check.confirmed) StockAnswer.reset,
    ];
    final interactive = onAnswer != null && !check.missing && options.isNotEmpty;

    final chip = Container(
      key: ValueKey('stock-check-$label'),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: interactive ? 6 : 3),
      decoration: BoxDecoration(
        color: tone.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: tone.shade700),
            )
          else
            Icon(icon, size: 12, color: tone.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: tone.shade800, fontWeight: FontWeight.w500),
          ),
          if (interactive) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: tone.shade800),
          ],
        ],
      ),
    );
    if (!interactive) return chip;

    return PopupMenuButton<StockAnswer>(
      key: const ValueKey('stock-check-menu'),
      enabled: !busy,
      tooltip: 'Ответ по наличию',
      onSelected: onAnswer,
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem<StockAnswer>(
            value: o,
            child: switch (o) {
              StockAnswer.present => _menuRow(Icons.check_circle, Colors.green, 'В наличии'),
              StockAnswer.missing => _menuRow(Icons.cancel, Colors.red, 'Нет в наличии'),
              StockAnswer.reset => _menuRow(Icons.undo, Colors.grey, 'Сбросить ответ'),
            },
          ),
      ],
      child: chip,
    );
  }

  static Widget _menuRow(IconData icon, MaterialColor tone, String label) => Row(
        children: [
          Icon(icon, size: 18, color: tone.shade700),
          const SizedBox(width: 10),
          Text(label),
        ],
      );
}
