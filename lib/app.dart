import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api/api_client.dart';
import 'core/api/api_config.dart';
import 'core/services/new_order_counter.dart';
import 'core/services/new_order_dialog_guard.dart';
import 'core/services/onesignal_service.dart';
import 'core/services/order_watcher.dart';
import 'core/services/sound_service.dart';
import 'core/storage/prefs_storage.dart';
import 'core/storage/token_storage.dart';

import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/state/auth_cubit.dart';
import 'features/banners/data/banners_repository.dart';
import 'features/banners/state/banners_cubit.dart';
import 'features/broadcast/data/broadcast_repository.dart';

import 'features/customers/data/customers_repository.dart';
import 'features/customers/state/customers_cubit.dart';
import 'features/delivery/data/delivery_repository.dart';
import 'features/delivery/state/delivery_cubit.dart';
import 'features/delivery_slots/data/delivery_slots_repository.dart';
import 'features/delivery_slots/state/slot_templates_cubit.dart';
import 'features/home/presentation/home_shell.dart';
import 'features/stores/data/stores_repository.dart';
import 'features/stores/presentation/store_picker_page.dart';
import 'features/stores/state/store_cubit.dart';

import 'features/orders/data/orders_repository.dart';
import 'features/orders/presentation/order_details_page.dart';
import 'features/orders/state/orders_cubit.dart';

import 'features/users/data/users_repository.dart';
import 'features/users/state/users_cubit.dart';

class App extends StatefulWidget {
  final OneSignalService oneSignalService;
  const App({super.key, required this.oneSignalService});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
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
  late final BannersRepository _bannersRepo;
  late final BroadcastRepository _broadcastRepo;
  late final DeliverySlotsRepository _slotsRepo;


  late final SoundService _sound;
  late final NewOrderCounter _newOrderCounter;
  OrderWatcher? _watcher;

  /// Which store [_watcher] was built for. A watcher only carries valid
  /// dedupe state for the store it was created against.
  int? _watcherStoreId;

  // A notification tap that arrived before the app was ready to navigate
  // (cold start: SDK click event fires before the navigator + auth exist).
  // Replayed once the app reaches Authenticated. Latest-tap-wins.
  int? _pendingOpenOrderId;

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle so we can restart the OrderWatcher when the
    // operator brings the app back from background. iOS suspends our
    // Dart timers when the app is sent to background; without an explicit
    // restart, the watcher's _sinceUtc cursor stays frozen at the
    // suspension time and orders that arrive in between get picked up as
    // a single batch only when the next tick runs — and even then, the
    // app's OneSignal foreground listener may already have fired without
    // a sound (the dialog appearing "only after closing+reopening the
    // app" symptom reported on launch day).
    WidgetsBinding.instance.addObserver(this);

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
    _bannersRepo = BannersRepository(api: _api);
    _broadcastRepo = BroadcastRepository(api: _api);
    _slotsRepo = DeliverySlotsRepository(api: _api);

    _sound = SoundService();
    _newOrderCounter = NewOrderCounter();

    _setupOneSignalForegroundHandler();
    _setupOneSignalClickHandler();
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
      // Bump the unread counter immediately — even if the dialog can't
      // open (no nav context, dialog guard busy), the operator should
      // still see the badge on the "Новые" tab next time they look.
      _newOrderCounter.bump();
      // Coordinate with OrderWatcher so push + poll don't stack
      // two new-order dialogs on top of each other.
      if (!newOrderDialogGuard.tryAcquire()) return;

      // Resolve the nav context BEFORE starting the siren: with no context
      // there is no dialog whose dismissal would ever stop it, so we must not
      // start an unstoppable loop. bump()/badge already recorded the order and
      // the OrderWatcher poll re-alerts once a context exists.
      final ctx = _navKey.currentContext;
      if (ctx == null) {
        newOrderDialogGuard.release();
        return;
      }

      // В foreground можно сразу играть звук и обновляться.
      await _sound.ring();
      // Haptic alongside the sound. On iPhone this is a strong tap;
      // on iPad it's a no-op except on Pro models with the Taptic
      // Engine — harmless either way. Picked up by the operator's
      // hand even when the iPad volume is low or muted.
      HapticFeedback.heavyImpact();

      // Попробуем найти order_id в payload (если ты его добавишь на бэке)
      final int? orderId = widget.oneSignalService.tryExtractOrderId(data);

      // If the context unmounted while the siren was starting, stop it and
      // bail — otherwise the loop would have no dialog to end it.
      if (!ctx.mounted) {
        unawaited(_sound.stop());
        newOrderDialogGuard.release();
        return;
      }

      try {
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
                  // If the push payload included an order_id, jump straight to
                  // that order's detail. Shared with the background/killed push
                  // TAP path so both routes behave identically. The outer
                  // refresh below still fires regardless, keeping the list
                  // fresh for when the operator backs out of detail.
                  if (orderId != null) {
                    await _openOrderById(orderId);
                  }
                },
                child: const Text('Открыть'),
              ),
            ],
          ),
        );

        // After the dialog closes — regardless of whether the operator
        // tapped "Позже" or "Открыть" — always refresh the orders list.
        // Without this, "Позже" left the list stale until the next 30s
        // background poll landed, which violates the "operator sees new
        // orders within seconds" SLA on busy days. Idempotent: if
        // "Открыть" already triggered a refresh in its branch (via
        // navigating to detail), running it again here is harmless and
        // covers the case where navigation failed.
        final storeId = await _prefsStorage.getSelectedStoreId();
        if (storeId != null && ctx.mounted) {
          ctx.read<OrdersCubit>().refresh(storeId: storeId);
        }
      } finally {
        await _sound.stop(); // safety: catches OS-level dismissal
        newOrderDialogGuard.release();
      }
    };
  }

  /// Resolve the selected store, look up the order, and push its detail page.
  /// Shared by the foreground "Открыть" dialog button and the background/killed
  /// notification-tap handler so both routes behave identically. Silent on
  /// failure (missing store / lookup error) — the orders list stays the
  /// fallback surface.
  Future<void> _openOrderById(int orderId) async {
    final storeId = await _prefsStorage.getSelectedStoreId();
    if (storeId == null) return;
    try {
      final order = await _ordersRepo.getOrderById(
        storeId: storeId,
        orderId: orderId,
      );
      if (order != null) {
        _navKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => OrderDetailsPage(order: order),
          ),
        );
      }
    } catch (_) {/* lookup failed — operator can still find it in the list */}
  }

  void _setupOneSignalClickHandler() {
    widget.oneSignalService.onNotificationClick = (data) async {
      // Push TAPPED while backgrounded or killed. Record it for the badge, then
      // route to the order. On a cold start the click can fire before the
      // navigator + auth exist; if so, stash the id and let the AuthCubit
      // listener replay it once Authenticated.
      _newOrderCounter.bump();
      final int? orderId = widget.oneSignalService.tryExtractOrderId(data);
      if (orderId == null) return;

      final navCtx = _navKey.currentContext;
      final navReady = _navKey.currentState != null && navCtx != null;
      final isAuthed =
          navReady && navCtx.read<AuthCubit?>()?.state is Authenticated;
      if (!navReady || !isAuthed) {
        _pendingOpenOrderId = orderId;
        return;
      }
      await _openOrderById(orderId);
    };
  }

  Future<void> _startWatcherIfPossible() async {
    final storeId = await _prefsStorage.getSelectedStoreId();
    if (storeId == null) return;

    // REUSE the watcher when the store has not changed.
    //
    // This is called on every resume, and it used to stop and RECONSTRUCT,
    // which threw away the watcher's memory of what it had already alarmed
    // for. On an iPad that is locked and unlocked dozens of times a shift,
    // an order still sitting in `paid` re-alarmed on every single unlock:
    // looping siren plus a full-screen, non-dismissible dialog, again and
    // again, until somebody moved the order out of `paid`. The server
    // legitimately keeps returning it, so nothing downstream can save us;
    // the dedupe list is the only thing that does, and it lived on the
    // instance being destroyed.
    //
    // That is worse than an annoyance. This is the one alert channel the
    // store has to trust, and an alarm that cries wolf on every unlock
    // teaches staff to mute it, which is exactly when a real order is missed.
    //
    // start() is safe on a live watcher: it cancels and restarts the timer
    // and ticks immediately, but leaves the dedupe list and the cursor alone.
    if (_watcher != null && _watcherStoreId == storeId) {
      _watcher!.start(interval: const Duration(seconds: 10));
      return;
    }

    // Store actually changed (or first start). Now a fresh watcher is correct:
    // the dedupe list refers to another store's orders.
    await _watcher?.stop();
    _watcherStoreId = storeId;

    _watcher = OrderWatcher(
      prefsStorage: _prefsStorage,
      ordersRepository: _ordersRepo,
      sound: _sound,
      navigatorKey: _navKey,
    );

    // 10s matches the customer-app polling cadence and the "operator sees
    // new orders within seconds" expectation. 30s left a real gap where a
    // walk-up customer order could sit invisible long enough for the
    // operator to assume the system was dead.
    _watcher!.start(interval: const Duration(seconds: 10));
  }

  Future<void> _stopWatcher() async {
    await _watcher?.stop();
    _watcher = null;
    _watcherStoreId = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Resume = operator pulled the iPad out of background or unlocked it
    // with the admin app in foreground. Cheap to call: if no auth/store
    // is selected yet, _startWatcherIfPossible early-returns.
    if (state == AppLifecycleState.resumed) {
      debugPrint('[lifecycle] resumed — restarting OrderWatcher');
      _startWatcherIfPossible();
      // Re-assert the OneSignal binding on resume. bootstrap() re-binds on a
      // COLD start only; a manager who enables notifications while the app is
      // merely backgrounded returns via a RESUME (no bootstrap) and would stay
      // unsubscribed until a full kill+relaunch — exactly the store 15/16 case
      // (2026-07-06). Idempotent + best-effort; no-op if not authenticated.
      final ctx = _navKey.currentContext;
      if (ctx != null) {
        ctx.read<AuthCubit>().reassertPushBinding();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watcher?.stop();
    _watcher = null;
    _newOrderCounter.dispose();
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
        RepositoryProvider.value(value: _broadcastRepo),
        RepositoryProvider.value(value: widget.oneSignalService),
        RepositoryProvider.value(value: _newOrderCounter),
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
          BlocProvider(create: (_) => DeliveryCubit(repo: _deliveryRepo)),
          BlocProvider(create: (_) => BannersCubit(repo: _bannersRepo)),
          BlocProvider(create: (_) => SlotTemplatesCubit(repo: _slotsRepo)),
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
                // Replay a notification tap that arrived during cold start,
                // before the navigator/auth were ready. Defer a frame so the
                // router has swapped to the authenticated tree and _navKey has
                // a live navigator to push onto.
                final pending = _pendingOpenOrderId;
                if (pending != null) {
                  _pendingOpenOrderId = null;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _openOrderById(pending);
                  });
                }
              }
              if (state is Unauthenticated) {
                await _stopWatcher();
                // Wipe user-scoped state so the next admin signing in
                // on the same device doesn't briefly see the previous
                // user's orders / customer list / selected store, etc.
                // Tokens are already cleared by AuthCubit.logout(); this
                // clears the in-memory cubits + the persisted store
                // selection.
                await ctx.read<StoreCubit>().clearStore();
                ctx.read<OrdersCubit>().reset();
                ctx.read<CustomersCubit>().reset();
                ctx.read<UsersCubit>().reset();
                ctx.read<BannersCubit>().reset();
                ctx.read<DeliveryCubit>().reset();
                ctx.read<SlotTemplatesCubit>().reset();
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

    // Reject non-staff identities. An authenticated token with an
    // unknown/empty/`customer` role must NOT reach the admin shell —
    // previously the router only checked Authenticated, so any valid
    // token got in. Force a logout (post-frame, so we don't mutate the
    // cubit during build) and show a clear message; the next build
    // resolves to LoginPage.
    if (auth is Authenticated && !auth.user.isStaff) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AuthCubit>().logout();
      });
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Этот аккаунт не имеет доступа к админ-приложению.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
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
