import 'dart:async';
import 'dart:math';

import 'package:admin_fmart/core/services/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/orders/data/orders_repository.dart';
import '../../features/orders/models/order_models.dart';
import '../../features/orders/presentation/order_details_page.dart';
import '../../features/orders/state/orders_cubit.dart';
import '../storage/prefs_storage.dart';
import 'new_order_dialog_guard.dart';

class OrderWatcher {
  final PrefsStorage prefsStorage;
  final OrdersRepository ordersRepository;
  final SoundService sound;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Called when a poll sees a paid order the orders list has not been
  /// refreshed for yet. The list never refreshes by itself otherwise, so
  /// without this the iPad rang but the order only showed after someone
  /// pulled the list down (order 1095, 2026-10-09).
  final void Function(int storeId)? onNewOrders;

  Timer? _timer;
  bool _dialogOpen = false;
  bool _inFlight = false;

  DateTime? _sinceUtc;
  // Capped FIFO of recently-shown order ids so we don't double-dialog
  // on the same order. Bounded so a long shift can't grow the set
  // unbounded.
  static const int _alreadyNotifiedCap = 200;
  final List<int> _alreadyNotified = <int>[];
  // Paid orders the list has already been refreshed for. Separate from
  // _alreadyNotified: the list must refresh even when no dialog can be shown.
  final List<int> _listRefreshedFor = <int>[];

  int _consecutiveFailures = 0;
  DateTime _nextRetryAt = DateTime.fromMillisecondsSinceEpoch(0);

  OrderWatcher({
    required this.prefsStorage,
    required this.ordersRepository,
    required this.sound,
    required this.navigatorKey,
    this.onNewOrders,
  });

  static void _remember(List<int> list, Iterable<int> ids) {
    for (final id in ids) {
      if (!list.contains(id)) list.add(id);
    }
    if (list.length > _alreadyNotifiedCap) {
      list.removeRange(0, list.length - _alreadyNotifiedCap);
    }
  }

  bool _wasAlerted(int id) =>
      _alreadyNotified.contains(id) || newOrderDialogGuard.wasShown(id);

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
    // Keep polling while a dialog is open: a second order that arrives
    // meanwhile must still reach the list. Only the alarm waits.
    if (_inFlight) return;
    if (DateTime.now().isBefore(_nextRetryAt)) return;

    final storeId = await prefsStorage.getSelectedStoreId();
    if (storeId == null) return;

    try {
      // Only the request is exclusive. The dialog below can stay open for
      // minutes and polling must carry on underneath it.
      final NewOrdersResponse resp;
      _inFlight = true;
      try {
        resp = await ordersRepository.getNewOrders(
          storeId: storeId,
          since: _sinceUtc,
          minutes: 10,
          limit: 20,
          statuses: const ['paid'],
          tz: 'Asia/Almaty',
        );
      } finally {
        _inFlight = false;
      }

      _consecutiveFailures = 0;

      _sinceUtc = DateTime.tryParse(resp.sinceUsed);

      if (!resp.hasNew || resp.orders.isEmpty) return;

      // 1. The list. The «Новый заказ» push is sent when the order is
      //    CREATED, a few seconds before it is paid, and the refresh that
      //    follows the push dialog runs before the order is in the paid list.
      //    Refresh again the first time a poll sees each paid order.
      final unseen = [
        for (final o in resp.orders)
          if (!_listRefreshedFor.contains(o.id)) o.id,
      ];
      if (unseen.isNotEmpty) {
        _remember(_listRefreshedFor, unseen);
        onNewOrders?.call(storeId);
      }

      // 2. The alarm.
      if (_dialogOpen) return;

      final first = resp.orders.firstWhere(
        (o) => !_wasAlerted(o.id),
        orElse: () => resp.orders.first,
      );
      if (_wasAlerted(first.id)) return;

      // Coordinate with the OneSignal foreground handler so push + poll
      // don't stack two dialogs on top of each other. If the slot is taken,
      // do NOT mark the order: it used to be marked first, so an order that
      // arrived while another dialog was open was never alarmed at all.
      // The next tick tries again.
      if (!newOrderDialogGuard.tryAcquire()) return;

      // No context means no dialog, and a siren with no dialog can never be
      // stopped. Leave the order unmarked for the next tick.
      final ctx = navigatorKey.currentContext;
      if (ctx == null) {
        newOrderDialogGuard.release();
        return;
      }

      _remember(_alreadyNotified, [first.id]);
      newOrderDialogGuard.markShown(first.id);

      await sound.ring();
      // The context can go away while the siren starts. Then there is no
      // dialog to stop it: stop now and leave the order for the next tick.
      if (!ctx.mounted) {
        await sound.stop();
        _alreadyNotified.remove(first.id);
        newOrderDialogGuard.unmarkShown(first.id);
        newOrderDialogGuard.release();
        return;
      }
      // Haptic alongside the sound for operators who feel the iPad
      // before they hear it (e.g., iPad sitting under a stack of
      // receipts). On models without the Taptic engine this is a
      // no-op — harmless. iPhones get a strong tap.
      HapticFeedback.heavyImpact();

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
                  // to a list refresh if the lookup fails (network
                  // blip, order moved out of the visible window) — same
                  // behavior as before this change, so admin always
                  // sees something when they tap "Открыть".
                  try {
                    final full = await ordersRepository.getOrderById(
                      storeId: storeId,
                      orderId: first.id,
                    );
                    if (full != null) {
                      navigatorKey.currentState?.push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailsPage(order: full),
                        ),
                      );
                      return;
                    }
                  } catch (_) {/* fall through to list refresh */}
                  final fallbackCtx = navigatorKey.currentContext;
                  if (fallbackCtx != null) {
                    fallbackCtx.read<OrdersCubit>().refresh(storeId: storeId);
                  }
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
