import 'dart:async';

import 'package:admin_fmart/core/services/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/orders/data/orders_repository.dart';
import '../../features/orders/state/orders_cubit.dart';
import '../storage/prefs_storage.dart';

class OrderWatcher {
  final PrefsStorage prefsStorage;
  final OrdersRepository ordersRepository;
  final SoundService sound;
  final GlobalKey<NavigatorState> navigatorKey;

  Timer? _timer;
  bool _dialogOpen = false;

  // важное: since между тиками
  DateTime? _sinceUtc;
  final Set<int> _alreadyNotified = {};

  OrderWatcher({
    required this.prefsStorage,
    required this.ordersRepository,
    required this.sound,
    required this.navigatorKey,
  });

  void start({Duration interval = const Duration(seconds: 10)}) {
    _timer?.cancel();
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

    final storeId = await prefsStorage.getSelectedStoreId();
    if (storeId == null) return;

    try {
      final resp = await ordersRepository.getNewOrders(
        storeId: storeId,
        since: _sinceUtc,
        minutes: 10,
        limit: 20,
        statuses: const ['paid',],
        tz: 'Asia/Almaty',
      );

      _sinceUtc = DateTime.tryParse(resp.sinceUsed);

      if (!resp.hasNew || resp.orders.isEmpty) return;

      // выбираем первый еще не показанный
      final first = resp.orders.firstWhere(
            (o) => !_alreadyNotified.contains(o.id),
        orElse: () => resp.orders.first,
      );

      if (_alreadyNotified.contains(first.id)) return;
      _alreadyNotified.add(first.id);

      // звук
      await sound.ring();

      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;

      _dialogOpen = true;

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

                // Тут можно триггернуть refresh списка заказов:
                ctx.read<OrdersCubit>().refresh(storeId: storeId);
              },
              child: const Text('Открыть'),
            ),
          ],
        ),
      );

      _dialogOpen = false;
    } catch (_) {
      // не падаем, просто пропускаем тик
    }
  }
}
