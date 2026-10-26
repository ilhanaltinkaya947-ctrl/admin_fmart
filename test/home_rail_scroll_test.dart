// The iPad side menu must scroll when it does not fit (26.10 review LOW-2).
// iPad mini in landscape is ~744 pt tall; with «Утренняя проверка» added the
// rail no longer fit, and a Column with a Spacer overflowed and pushed
// «Сменить магазин» / «Выйти» off the bottom, unreachable.
import 'package:admin_fmart/core/services/morning_check_push.dart';
import 'package:admin_fmart/core/services/new_order_counter.dart';
import 'package:admin_fmart/core/services/onesignal_service.dart';
import 'package:admin_fmart/core/storage/prefs_storage.dart';
import 'package:admin_fmart/features/auth/state/auth_cubit.dart';
import 'package:admin_fmart/features/home/presentation/home_shell.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/state/orders_cubit.dart';
import 'package:admin_fmart/features/stores/data/stores_repository.dart';
import 'package:admin_fmart/features/stores/state/store_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart' show StubAuthRepository, StubTokenStorage;
import 'weight_page_harness.dart';

Future<void> _pump(WidgetTester t, Size size, {MorningCheckLauncher? launcher}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final repo = fakeRepo(weighedOrderJson());
  final api = repo.api;
  final tokens = StubTokenStorage();
  await t.pumpWidget(MultiRepositoryProvider(
    providers: [
      RepositoryProvider<OrdersRepository>.value(value: repo),
      RepositoryProvider<NewOrderCounter>(create: (_) => NewOrderCounter()),
      if (launcher != null) RepositoryProvider<MorningCheckLauncher>.value(value: launcher),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(
          create: (_) => TestAuthCubit(
            tokenStorage: tokens,
            authRepository: StubAuthRepository(api: api, tokenStorage: tokens),
            role: 'manager',
          ),
        ),
        BlocProvider<StoreCubit>(
          create: (_) => TestStoreCubit(
            storesRepository: StoresRepository(api: api),
            prefsStorage: PrefsStorage(),
            oneSignalService: OneSignalService(),
          ),
        ),
        BlocProvider<OrdersCubit>(
          create: (_) => OrdersCubit(ordersRepository: repo, autoRefreshEvery: null),
        ),
      ],
      child: const MaterialApp(home: HomeShell(storeId: 1, storeName: 'F-Mart')),
    ),
  ));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a short iPad: no overflow, «Выйти» on screen, the sections scroll', (t) async {
    await _pump(t, const Size(1133, 600));
    expect(t.takeException(), isNull);
    expect(t.getRect(find.text('Выйти')).bottom, lessThanOrEqualTo(600));
    expect(t.getRect(find.text('Сменить магазин')).bottom, lessThanOrEqualTo(600));
    // The last section is reachable by scrolling the list above them.
    final settings = find.text('Настройки');
    await t.dragUntilVisible(settings, find.text('Сегодня').first, const Offset(0, -200));
    await t.pump();
    expect(t.getRect(settings).bottom, lessThan(t.getRect(find.text('Сменить магазин')).top));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a tall iPad: the bottom items stay pinned to the bottom', (t) async {
    await _pump(t, const Size(1024, 1366));
    expect(t.takeException(), isNull);
    expect(t.getRect(find.text('Выйти')).bottom, greaterThan(1250));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a push request switches the shell to «Утренняя проверка»', (t) async {
    final launcher = MorningCheckLauncher()..request(); // cold start: already pending
    await _pump(t, const Size(1024, 1366), launcher: launcher);
    await t.pump();
    expect(find.widgetWithText(AppBar, 'Утренняя проверка'), findsOneWidget);
    expect(launcher.pending, isFalse);
    await t.pumpWidget(const SizedBox());
  });
}
