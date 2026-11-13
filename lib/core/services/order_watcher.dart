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

/// True while a new-order alarm dialog (the watcher's or the push's) is on
/// screen: the red bar steps aside, so there is one «Открыть», not two, and a
/// bar tap can never open an order behind a ringing siren (UX review H2).
final ValueNotifier<bool> alarmShowing = ValueNotifier(false);

/// Order ids whose order screen is open right now (OrderDetailsPage adds and
/// removes itself). A bar tap for one opens nothing new (UX review L8), and a
/// reminder never rings over the order the cashier is looking at (critic M4).
final OpenOrderScreens openOrderScreens = OpenOrderScreens();

/// A counted set: the same order can be open twice (push «Открыть» over the
/// list's copy); closing one must not forget the other (critic round 2 LOW).
class OpenOrderScreens {
  final Map<int, int> _n = {};
  void add(int id) => _n[id] = (_n[id] ?? 0) + 1;
  void remove(int id) {
    final c = (_n[id] ?? 0) - 1;
    if (c <= 0) {
      _n.remove(id);
    } else {
      _n[id] = c;
    }
  }

  bool contains(int id) => _n.containsKey(id);
}

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

/// The reminder's body (UX review M6): how many wait, and the oldest one.
String reminderText(List<NewOrderItem> waiting, DateTime nowUtc) {
  final o = waiting.first;
  final m = waitedMinutes(o, nowUtc);
  if (waiting.length == 1) {
    return 'Заказ №${o.id} ждёт $m мин. Примите заказ, мы напомним снова через 3 минуты.';
  }
  return 'Не приняты заказы: ${waiting.length}. Самый ранний №${o.id} ждёт $m мин. '
      'Примите заказы, мы напомним снова через 3 минуты.';
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
  // Bumped by start()/stop(): a poll still in flight when the cashier logs out
  // must not repaint the bar or ring on the login screen (critic M3).
  int _generation = 0;

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
    _generation++;
    _consecutiveFailures = 0;
    _nextRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
    _tick();
    _timer = Timer.periodic(interval, (_) => _tick());
    // 1.3.0 S2: the iPad at the counter must not dim and lock while the store
    // is on duty, or a ringing order is a dark screen. Best effort.
    unawaited(WakelockPlus.enable().catchError((_) {}));
  }

  /// The push dialog closed (UX review H1): start the same snooze as our own
  /// dialog, or the next poll rings «ждёт 0 мин» ten seconds later.
  void snooze() => _remindAfter = DateTime.now().add(remindEvery);

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _generation++;
    unacceptedOrders.value = const [];
    unawaited(WakelockPlus.disable().catchError((_) {}));
    await sound.stop();
  }

  Future<void> _tick() async {
    // Keep polling while a dialog is open: a second order that arrives
    // meanwhile must still reach the list. Only the alarm waits.
    if (_inFlight) return;
    if (DateTime.now().isBefore(_nextRetryAt)) return;

    final gen = _generation;
    final storeId = await prefsStorage.getSelectedStoreId();
    if (storeId == null || gen != _generation) return;

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
      if (gen != _generation) return; // stopped (logout / store switch) meanwhile

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
      } else if (oldestFirst.any((o) => !openOrderScreens.contains(o.id)) &&
          !DateTime.now().isBefore(_remindAfter)) {
        // Never over the order the cashier already has open (critic M4).
        first = oldestFirst.firstWhere((o) => !openOrderScreens.contains(o.id));
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

      if (gen != _generation) {
        if (!reminder) {
          _alreadyNotified.remove(first.id);
          newOrderDialogGuard.unmarkShown(first.id);
        }
        newOrderDialogGuard.release();
        return;
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
      alarmShowing.value = true;

      try {
        await showDialog(
          context: ctx,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: Text(reminder ? 'Заказ ждёт принятия' : 'Новый заказ'),
            content: Text(reminder
                ? reminderText(oldestFirst, DateTime.now().toUtc())
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
        alarmShowing.value = false;
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
