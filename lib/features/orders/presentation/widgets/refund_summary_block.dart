import 'package:flutter/material.dart';

import '../../models/refund_summary.dart';

/// 1.3.1 order screen: how much went back against how much the customer is
/// owed, from the server's `refund_summary`. One line a manager can repeat to
/// a customer, plus what is still on its way, what is left, and an overshoot.
///
/// Built only when the server sent the summary (an older order-service sends
/// nothing and this never appears).
class RefundSummaryBlock extends StatelessWidget {
  final RefundSummary summary;
  const RefundSummaryBlock({super.key, required this.summary});

  static const _ink = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _orange = Color(0xFFEE6F00);

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final settled = s.refunded > 0 &&
        s.remainingOwed <= 0 &&
        s.overBy <= 0 &&
        s.pending <= 0;
    return Container(
      key: const ValueKey('refund-summary'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                settled ? Icons.check_circle_outline : Icons.replay,
                size: 22,
                color: settled ? const Color(0xFF2E7D32) : _orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  refundedOfOwedText(s),
                  key: const ValueKey('refund-summary-line'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          if (s.pending > 0 || s.remainingOwed > 0 || s.overBy > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (s.overBy > 0)
                  _Pill(
                    key: const ValueKey('refund-summary-over'),
                    text: refundOverByChipText(s.overBy),
                    icon: Icons.warning_amber_rounded,
                    bg: const Color(0xFFFFEBEE),
                    fg: const Color(0xFFC62828),
                  ),
                if (s.remainingOwed > 0)
                  _Pill(
                    key: const ValueKey('refund-summary-remaining'),
                    text: refundRemainingOwedText(s.remainingOwed),
                    icon: Icons.schedule,
                    bg: const Color(0xFFFFF3E0),
                    fg: const Color(0xFFE65100),
                  ),
                if (s.pending > 0)
                  _Pill(
                    key: const ValueKey('refund-summary-pending'),
                    text: refundPendingBankText(s.pending),
                    icon: Icons.hourglass_top,
                    bg: const Color(0xFFFFF8E1),
                    fg: const Color(0xFF8D6E00),
                  ),
              ],
            ),
          ],
          if (s.refunded <= 0 && s.pending <= 0 && s.owed > 0) ...[
            const SizedBox(height: 4),
            const Text(
              'Возвратов по заказу ещё не было',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color bg;
  final Color fg;
  const _Pill({
    super.key,
    required this.text,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
