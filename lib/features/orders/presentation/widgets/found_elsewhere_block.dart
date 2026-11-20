import 'package:flutter/material.dart';

/// 1.3.2 (case 19.11, Тулпар): an order searched by its full number that this
/// section does not list. Shown with where it is, instead of «Заказов нет».
class FoundElsewhereBlock extends StatelessWidget {
  final String label;
  final Widget child;

  const FoundElsewhereBlock({
    super.key,
    required this.label,
    required this.child,
  });

  static const _accent = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: _accent.withValues(alpha: 0.08),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.manage_search, size: 20, color: _accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 1.3.2: the list shows fewer statuses than its section (the «Статус» chip or
/// a dashboard drill-down). Says which, and puts the section back in one tap.
class NarrowedStatusStrip extends StatelessWidget {
  final List<String> statusNames;
  final VoidCallback onReset;

  const NarrowedStatusStrip({
    super.key,
    required this.statusNames,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final what = statusNames.isEmpty
        ? 'Показаны не все статусы раздела'
        : 'Показаны только: ${statusNames.join(', ')}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEE6F00).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined,
              size: 18, color: Color(0xFFEE6F00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              what,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onReset,
            child: const Text('Показать все статусы'),
          ),
        ],
      ),
    );
  }
}
