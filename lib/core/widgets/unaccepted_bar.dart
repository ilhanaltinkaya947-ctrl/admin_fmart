import 'package:flutter/material.dart';

import '../../features/orders/models/order_models.dart';
import '../services/order_watcher.dart';

/// «2 заказа», «5 заказов», «21 заказ».
String ordersWord(int n) {
  final m100 = n % 100, m10 = n % 10;
  if (m100 >= 11 && m100 <= 14) return '$n заказов';
  if (m10 == 1) return '$n заказ';
  if (m10 >= 2 && m10 <= 4) return '$n заказа';
  return '$n заказов';
}

/// The bar's text, e.g. «Не приняты: 2 заказа · ждут 12 мин».
String unacceptedText(List<NewOrderItem> list, DateTime nowUtc) {
  final waited = list.isEmpty ? 0 : waitedMinutes(list.first, nowUtc);
  final who = list.length == 1 ? 'Не принят: ${ordersWord(1)} · ждёт' : 'Не приняты: ${ordersWord(list.length)} · ждут';
  return '$who $waited мин';
}

/// Store app 1.3.0 S2: a red bar above EVERY screen while any paid order is
/// not accepted. Tapping it opens the order that has waited longest. Wraps the
/// whole app (MaterialApp.builder), so no screen can hide it.
class UnacceptedBarFrame extends StatelessWidget {
  const UnacceptedBarFrame({super.key, required this.child, required this.onOpen});

  final Widget child;
  final void Function(int orderId) onOpen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<NewOrderItem>>(
      valueListenable: unacceptedOrders,
      builder: (context, list, _) {
        if (list.isEmpty) return child;
        final top = MediaQuery.of(context).padding.top;
        return Column(children: [
          Material(
            color: const Color(0xFFC62828),
            child: InkWell(
              onTap: () => onOpen(list.first.id),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, top + 8, 16, 10),
                child: Row(children: [
                  const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      unacceptedText(list, DateTime.now().toUtc()),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Text('Открыть', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ]),
              ),
            ),
          ),
          // The screens below must not pad for the status bar a second time.
          Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
        ]);
      },
    );
  }
}
