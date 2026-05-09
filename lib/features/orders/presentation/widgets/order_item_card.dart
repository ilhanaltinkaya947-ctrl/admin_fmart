import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/order_models.dart';

/// Card row for one order item.
/// Shows image, name, barcode (copyable), qty x price, line total.
/// When [editable] is true, shows +/- and remove controls.
class OrderItemCard extends StatelessWidget {
  final OrderItem item;
  final bool editable;
  final bool busy;
  final ValueChanged<int>? onQtyChange;
  final VoidCallback? onRemove;

  const OrderItemCard({
    super.key,
    required this.item,
    this.editable = false,
    this.busy = false,
    this.onQtyChange,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = item.product.name ?? 'Товар ${item.productId}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      _StockBadge(inStock: item.product.inStock),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (item.product.sku != null && item.product.sku!.isNotEmpty)
                    _BarcodeChip(sku: item.product.sku!),
                  const SizedBox(height: 8),
                  if (editable)
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
                          label: '₸ ${item.price}',
                        ),
                        const Spacer(),
                        Text(
                          '₸ ${item.total}',
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
        _MetaPill(icon: Icons.attach_money, label: '₸ $price'),
        const Spacer(),
        Text(
          '₸ $total',
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
            constraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
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
            constraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
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

class _StockBadge extends StatelessWidget {
  final bool inStock;
  const _StockBadge({required this.inStock});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: inStock ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: inStock ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            inStock ? Icons.check_circle : Icons.cancel,
            size: 12,
            color: inStock ? Colors.green.shade700 : Colors.red.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            inStock ? 'В наличии' : 'Нет',
            style: TextStyle(
              fontSize: 11,
              color: inStock ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
