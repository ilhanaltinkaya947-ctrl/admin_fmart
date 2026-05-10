import 'dart:async';
import 'dart:math';

import 'package:admin_fmart/core/services/sound_service.dart';
import 'package:flutter/material.dart';

import '../../features/orders/data/orders_repository.dart';
import '../../features/orders/presentation/order_details_page.dart';
import '../storage/prefs_storage.dart';
import 'new_order_dialog_guard.dart';

class OrderWatcher {
  final PrefsStorage prefsStorage;
  final OrdersRepository ordersRepository;
  final SoundService sound;
  final GlobalKey<NavigatorState> navigatorKey;

  Timer? _timer;
  bool _dialogOpen = false;

  DateTime? _sinceUtc;
  // Capped FIFO of recently-shown order ids so we don't double-dialog
  // on the same order. Bounded so a long shift can't grow the set
  // unbounded.
  static const int _alreadyNotifiedCap = 200;
  final List<int> _alreadyNotified = <int>[];

  int _consecutiveFailures = 0;
  DateTime _nextRetryAt = DateTime.fromMillisecondsSinceEpoch(0);

  OrderWatcher({
    required this.prefsStorage,
    required this.ordersRepository,
    required this.sound,
    required this.navigatorKey,
  });

  void start({Duration interval = const Duration(seconds: 10)}) {
    _timer?.cancel();
    _consecutiveFailures = 0;
    _nextRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
    _tick();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await sound.stop();
  }

  Future<void> _tick() async {
    if (_dialogOpen) return;

    if (DateTime.now().isBefore(_nextRetryAt)) return;

    final storeId = await prefsStorage.getSelectedStoreId();
    if (storeId == null) return;

    try {
      final resp = await ordersRepository.getNewOrders(
        storeId: storeId,
        since: _sinceUtc,
        minutes: 10,
        limit: 20,
        statuses: const ['paid'],
        tz: 'Asia/Almaty',
      );

      _consecutiveFailures = 0;

      _sinceUtc = DateTime.tryParse(resp.sinceUsed);

      if (!resp.hasNew || resp.orders.isEmpty) return;

      final first = resp.orders.firstWhere(
        (o) => !_alreadyNotified.contains(o.id),
        orElse: () => resp.orders.first,
      );

      if (_alreadyNotified.contains(first.id)) return;
      _alreadyNotified.add(first.id);
      // Trim the oldest entries when we exceed the cap so the list
      // never grows past _alreadyNotifiedCap during a long shift.
      if (_alreadyNotified.length > _alreadyNotifiedCap) {
        _alreadyNotified.removeRange(
          0,
          _alreadyNotified.length - _alreadyNotifiedCap,
        );
      }

      // Coordinate with the OneSignal foreground handler so push + poll
      // don't stack two dialogs on top of each other.
      if (!newOrderDialogGuard.tryAcquire()) return;

      await sound.ring();

      final ctx = navigatorKey.currentContext;
      if (ctx == null) {
        newOrderDialogGuard.release();
        return;
      }

      _dialogOpen = true;

      try {
        await showDialog(
          context: ctx,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: const Text('Новый заказ'),
            content: Text('Заказ #${first.id} • ${first.status}'),
            actions: [
              TextButton(
                onPressed: () async {
                  await sound.stop();
                  if (c.mounted) Navigator.of(c).pop();
                },
                child: const Text('Позже'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await sound.stop();
                  if (c.mounted) Navigator.of(c).pop();
                  // getNewOrders returns NewOrderItem (lightweight summary),
                  // not the full Order that OrderDetailsPage needs. Fetch
                  // the full record by id and push detail. Falls back
                  // silently if the lookup fails (e.g. the order moved
                  // out of the visible window).
                  try {
                    final full = await ordersRepository.getOrderById(
                      storeId: storeId,
                      orderId: first.id,
                    );
                    if (full == null) return;
                    navigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailsPage(order: full),
                      ),
                    );
                  } catch (_) {/* swallow — admin can still find via list */}
                },
                child: const Text('Открыть'),
              ),
            ],
          ),
        );
      } finally {
        _dialogOpen = false;
        await sound.stop(); // catches OS-level dismissal too
        newOrderDialogGuard.release();
      }
    } catch (e, st) {
      _consecutiveFailures++;
      final backoffSeconds = min(10 * pow(2, _consecutiveFailures - 1).toInt(), 120);
      _nextRetryAt = DateTime.now().add(Duration(seconds: backoffSeconds));
      debugPrint('[OrderWatcher] tick error (failures=$_consecutiveFailures, retry in ${backoffSeconds}s): $e\n$st');
    }
  }
}
