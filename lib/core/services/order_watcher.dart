import 'dart:async';
import 'dart:math';

import 'package:admin_fmart/core/services/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../features/orders/data/orders_repository.dart';
import '../../features/orders/models/order_models.dart';
import '../../features/orders/presentation/order_details_page.dart';
import '../../features/orders/state/orders_cubit.dart';
import '../storage/prefs_storage.dart';
import 'new_order_dialog_guard.dart';

/// 1.3.0 S2: every PAID order of the store = paid and not yet accepted by the
/// store, oldest first. Updated by the watcher each tick; drives the red bar on
/// every screen and the 3-minute reminder. Empty when nobody is watching.
final ValueNotifier<List<NewOrderItem>> unacceptedOrders = ValueNotifier(const []);

/// How long «Напомнить через 3 мин» (or opening the order) quiets the alarm
/// while an order is still not accepted.
const Duration kRemindEvery = Duration(minutes: 3);

/// Minutes an order has waited, from its creation (≈ payment) time.
int waitedMinutes(NewOrderItem o, DateTime nowUtc) {
  final c = DateTime.tryParse(o.createdGmt ?? '');
  if (c == null) return 0;
  final m = nowUtc.difference(c.toUtc()).inMinutes;
  return m < 0 ? 0 : m;
}

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

  /// 1.3.0 S2: how long a dismissed, still-unaccepted order stays quiet.
  final Duration remindEvery;

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
  // 1.3.0 S2: the next moment a still-unaccepted order may ring again.
  DateTime _remindAfter = DateTime.fromMillisecondsSinceEpoch(0);

  OrderWatcher({
    required this.prefsStorage,
    required this.ordersRepository,
    required this.sound,
    required this.navigatorKey,
    this.onNewOrders,
    this.remindEvery = kRemindEvery,
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
    // 1.3.0 S2: the iPad at the counter must not dim and lock while the store
    // is on duty, or a ringing order is a dark screen. Best effort.
    unawaited(WakelockPlus.enable().catchError((_) {}));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    unacceptedOrders.value = const [];
    unawaited(WakelockPlus.disable().catchError((_) {}));
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
      final NewOrdersResponse waiting;
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
        // 1.3.0 S2: EVERY order still not accepted (paid within 24 h), however
        // old. The poll above only sees the last 10 minutes, which is how an
        // order dismissed with «Позже» used to drop out and never ring again.
        waiting = await ordersRepository.getNewOrders(
          storeId: storeId,
          minutes: 24 * 60,
          limit: 50,
          statuses: const ['paid'],
          tz: 'Asia/Almaty',
        );
      } finally {
        _inFlight = false;
      }

      _consecutiveFailures = 0;

      _sinceUtc = DateTime.tryParse(resp.sinceUsed);

      final oldestFirst = [...waiting.orders]
        ..sort((a, b) => (a.createdGmt ?? '').compareTo(b.createdGmt ?? ''));
      unacceptedOrders.value = List.unmodifiable(oldestFirst);

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

      // 2. The alarm: a NEW order rings at once; otherwise the oldest order
      //    still not accepted rings again every kRemindEvery (1.3.0 S2).
      if (_dialogOpen) return;

      final fresh = [for (final o in resp.orders) if (!_wasAlerted(o.id)) o];
      NewOrderItem first;
      var reminder = false;
      if (fresh.isNotEmpty) {
        first = fresh.first;
      } else if (oldestFirst.isNotEmpty && !DateTime.now().isBefore(_remindAfter)) {
        first = oldestFirst.first;
        reminder = true;
      } else {
        return;
      }

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

      if (!reminder) {
        _remember(_alreadyNotified, [first.id]);
        newOrderDialogGuard.markShown(first.id);
      }

      await sound.ring();
      // The context can go away while the siren starts. Then there is no
      // dialog to stop it: stop now and leave the order for the next tick.
      if (!ctx.mounted) {
        await sound.stop();
        if (!reminder) {
          _alreadyNotified.remove(first.id);
          newOrderDialogGuard.unmarkShown(first.id);
        }
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
            title: Text(reminder ? 'Заказ ждёт принятия' : 'Новый заказ'),
            content: Text(reminder
                ? 'Заказ №${first.id} ждёт ${waitedMinutes(first, DateTime.now().toUtc())} мин. '
                    'Примите его, иначе напомним снова через 3 минуты.'
                : 'Заказ №${first.id}'),
            actions: [
              TextButton(
                onPressed: () async {
                  await sound.stop();
                  if (c.mounted) Navigator.of(c).pop();
                },
                // 1.3.0 S2: never «Позже» — an order cannot be silenced, only
                // snoozed while it waits.
                child: const Text('Напомнить через 3 мин'),
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
        // Whatever closed the dialog (snooze, «Открыть», OS), the next ring for
        // a still-unaccepted order is kRemindEvery from now.
        _remindAfter = DateTime.now().add(remindEvery);
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
