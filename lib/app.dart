import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api/api_client.dart';
import 'core/api/api_config.dart';
import 'core/services/onesignal_service.dart';
import 'core/services/order_watcher.dart';
import 'core/services/sound_service.dart';
import 'core/storage/prefs_storage.dart';
import 'core/storage/token_storage.dart';

import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/state/auth_cubit.dart';

import 'features/customers/data/customers_repository.dart';
import 'features/customers/state/customers_cubit.dart';
import 'features/delivery/data/delivery_repository.dart';
import 'features/delivery/state/delivery_cubit.dart';
import 'features/home/presentation/home_shell.dart';
import 'features/stores/data/stores_repository.dart';
import 'features/stores/presentation/store_picker_page.dart';
import 'features/stores/state/store_cubit.dart';

import 'features/orders/data/orders_repository.dart';
import 'features/orders/state/orders_cubit.dart';

import 'features/users/data/users_repository.dart';
import 'features/users/state/users_cubit.dart';

class App extends StatefulWidget {
  final OneSignalService oneSignalService;
  const App({super.key, required this.oneSignalService});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _navKey = GlobalKey<NavigatorState>();

  late final TokenStorage _tokenStorage;
  late final PrefsStorage _prefsStorage;
  late final ApiClient _api;

  late final AuthRepository _authRepo;
  late final StoresRepository _storesRepo;
  late final OrdersRepository _ordersRepo;
  late final DeliveryRepository _deliveryRepo;
  late final CustomersRepository _customersRepo;
  late final UsersRepository _usersRepo;


  late final SoundService _sound;
  OrderWatcher? _watcher;

  @override
  void initState() {
    super.initState();

    _tokenStorage = TokenStorage();
    _prefsStorage = PrefsStorage();

    _api = ApiClient(
      baseUrl: ApiConfig.baseUrl,
      tokenStorage: _tokenStorage,
      onUnauthorized: _handleUnauthorized,
    );

    _authRepo = AuthRepository(api: _api, tokenStorage: _tokenStorage);
    _deliveryRepo = DeliveryRepository(api: _api);
    _storesRepo = StoresRepository(api: _api);
    _ordersRepo = OrdersRepository(api: _api);
    _customersRepo = CustomersRepository(api: _api);
    _usersRepo = UsersRepository(api: _api);

    _sound = SoundService();

    _setupOneSignalForegroundHandler();
  }

  void _handleUnauthorized() {
    // выкидываем в логин при "мертвом" refresh
    final ctx = _navKey.currentContext;
    if (ctx == null) return;

    final authCubit = ctx.read<AuthCubit?>();
    authCubit?.logout();
  }

  void _setupOneSignalForegroundHandler() {
    widget.oneSignalService.onForegroundNotification = (data) async {
      // В foreground можно сразу играть звук и обновляться.
      await _sound.ring();

      // Попробуем найти order_id в payload (если ты его добавишь на бэке)
      final int? orderId = widget.oneSignalService.tryExtractOrderId(data);

      final ctx = _navKey.currentContext;
      if (ctx == null) return;

      // покажем диалог
      await showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('Новый заказ'),
          content: Text(orderId != null ? 'Заказ #$orderId' : 'Поступил новый заказ'),
          actions: [
            TextButton(
              onPressed: () async {
                await _sound.stop();
                if (c.mounted) Navigator.of(c).pop();
              },
              child: const Text('Позже'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _sound.stop();
                if (c.mounted) Navigator.of(c).pop();

                // просто инициируем перезагрузку списка
                final storeId = await _prefsStorage.getSelectedStoreId();
                if (storeId == null) return;
                if (ctx.mounted) ctx.read<OrdersCubit>().refresh(storeId: storeId);
              },
              child: const Text('Открыть'),
            ),
          ],
        ),
      );
    };
  }

  Future<void> _startWatcherIfPossible() async {
    final storeId = await _prefsStorage.getSelectedStoreId();
    if (storeId == null) return;

    // Stop the previous watcher before creating a new one to prevent timer leak.
    await _watcher?.stop();

    _watcher = OrderWatcher(
      prefsStorage: _prefsStorage,
      ordersRepository: _ordersRepo,
      sound: _sound,
      navigatorKey: _navKey,
    );

    _watcher!.start(interval: const Duration(seconds: 30));
  }

  Future<void> _stopWatcher() async {
    await _watcher?.stop();
    _watcher = null;
  }

  @override
  void dispose() {
    _watcher?.stop();
    _watcher = null;
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: _authRepo),
        RepositoryProvider.value(value: _storesRepo),
        RepositoryProvider.value(value: _ordersRepo),
        RepositoryProvider.value(value: _customersRepo),
        RepositoryProvider.value(value: _usersRepo),
        RepositoryProvider.value(value: _prefsStorage),
        RepositoryProvider.value(value: _deliveryRepo),
        RepositoryProvider.value(value: widget.oneSignalService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AuthCubit(
              tokenStorage: _tokenStorage,
              authRepository: _authRepo,
            )..bootstrap(),
          ),
          BlocProvider(
            create: (_) => StoreCubit(
              storesRepository: _storesRepo,
              prefsStorage: _prefsStorage,
              oneSignalService: widget.oneSignalService,
            )..bootstrap(),
          ),
          BlocProvider(
            create: (_) => OrdersCubit(
              ordersRepository: _ordersRepo,
            ),
          ),
          BlocProvider(
            create: (_) => CustomersCubit(repository: _customersRepo),
          ),
          BlocProvider(
            create: (_) => UsersCubit(repository: _usersRepo),
          ),
          BlocProvider(create: (_) => DeliveryCubit(repo: _deliveryRepo))
        ],
        child: MaterialApp(
          navigatorKey: _navKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFEE6F00)),
            useMaterial3: true,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ru'),
            Locale('en'),
            Locale('kk'),
          ],
          locale: const Locale('ru'),
          home: BlocListener<AuthCubit, AuthState>(
            listener: (ctx, state) async {
              if (state is Authenticated) {
                _startWatcherIfPossible();
              }
              if (state is Unauthenticated) {
                await _stopWatcher();
              }
            },
            child: const _RootRouter(),
          ),
        ),
      ),
    );
  }
}

class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthCubit>().state;
    final storeState = context.watch<StoreCubit>().state;

    if (auth is AuthLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (auth is Unauthenticated) {
      return const LoginPage();
    }

    // Авторизован: если магазин выбран — главный экран, иначе — экран выбора магазина
    if (storeState is StoreSelected) {
      context.read<OrdersCubit>().ensureLoaded(storeId: storeState.storeId);
      return HomeShell(
        storeId: storeState.storeId,
        storeName: storeState.storeName,
      );
    }

    // StoreNotSelected / StoreLoading / StoreListLoaded / StoreFailure — всё сюда
    return const StorePickerPage();
  }
}
