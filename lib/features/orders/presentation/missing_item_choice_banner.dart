// «Если товара нет в наличии» (257): what the customer chose at checkout, for
// the picker. order-service also acts on it: «Заменить без звонка» applies a
// replacement at once; «Позвонить мне» applies it when the store could not get
// through (switch in the picker) or when the 20-minute answer window ends.
import 'package:flutter/material.dart';

import '_sub_tokens.dart';

/// The three values order-service stores; null on orders from older apps.
class MissingItemChoice {
  static const callThenReplace = 'call_then_replace';
  static const replace = 'replace';
  static const remove = 'remove';

  /// One line for the picker, or null when the customer made no choice.
  static String? label(String? v) => switch (v) {
        callThenReplace =>
          'Позвонить. Если не дозвонитесь, заменить на похожий',
        replace => 'Заменить на похожий без звонка',
        remove => 'Не звонить и не заменять: убрать товар',
        _ => null,
      };

  static IconData icon(String? v) => switch (v) {
        callThenReplace => Icons.phone_in_talk_outlined,
        replace => Icons.swap_horiz,
        _ => Icons.remove_circle_outline,
      };
}

/// «Если товара нет: …» — shown on the order and at the top of the picker.
class MissingItemChoiceBanner extends StatelessWidget {
  const MissingItemChoiceBanner({super.key, required this.choice});
  final String? choice;

  @override
  Widget build(BuildContext context) {
    final text = MissingItemChoice.label(choice);
    if (text == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('missing-item-choice-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ST.milk,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(MissingItemChoice.icon(choice), size: 18, color: ST.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(
                    text: 'Если нет товара: ',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: text),
              ]),
              style: const TextStyle(fontSize: 14, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
