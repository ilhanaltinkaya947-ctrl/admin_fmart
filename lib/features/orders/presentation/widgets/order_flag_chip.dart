import 'package:flutter/material.dart';

/// Small warning chips on an order (store app 1.3.0, S6/S7). Same look on the
/// order list row and the order screen, so the cashier learns one sign.
class OrderFlagChip extends StatelessWidget {
  const OrderFlagChip._(this.text, this.icon, this.fg, this.bg, {this.otherOrderId});

  /// S7: the order contains alcohol (weak or strong, as cart stamped it).
  const OrderFlagChip.alcohol()
      : this._('Алкоголь', Icons.local_bar_rounded, const Color(0xFFC62828), const Color(0xFFFFEBEE));

  /// S6: the same customer has another active order placed within 3 h.
  const OrderFlagChip.duplicate(int otherOrderId)
      : this._('Похоже на повтор №', Icons.content_copy_rounded,
            const Color(0xFFE65100), const Color(0xFFFFF3E0), otherOrderId: otherOrderId);

  final String text;
  final IconData icon;
  final Color fg;
  final Color bg;
  final int? otherOrderId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 4),
        Text(otherOrderId == null ? text : '$text$otherOrderId', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}
