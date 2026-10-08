// Shared harness for pumping the REAL OrderDetailsPage with a weighed order.
//
// Not a test file itself (no `_test` suffix). The page reads OrdersRepository,
// AuthCubit and StoreCubit; everything else it touches renders nothing without
// data. The fake repository records every money call so a test can assert
// "the settle POST went out exactly once" rather than trusting a flag.

import 'package:admin_fmart/core/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:admin_fmart/core/services/onesignal_service.dart';
import 'package:admin_fmart/core/storage/prefs_storage.dart';
import 'package:admin_fmart/features/auth/models/current_user.dart';
import 'package:admin_fmart/features/auth/state/auth_cubit.dart';
import 'package:admin_fmart/features/delivery/data/delivery_repository.dart';
import 'package:admin_fmart/features/delivery/models/delivery_models.dart';
import 'package:admin_fmart/features/delivery/state/delivery_cubit.dart';
import 'package:admin_fmart/features/orders/data/orders_repository.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:admin_fmart/features/orders/presentation/order_details_page.dart';
import 'package:admin_fmart/features/stores/data/stores_repository.dart';
import 'package:admin_fmart/features/stores/state/store_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart' show StubAuthRepository, StubTokenStorage;

/// One weighed cheese line (300 g ordered, cap 315 g) plus one piece line.
Map<String, dynamic> weighedOrderJson({
  String status = 'processing',
  int? actualG,
  bool closed = false,
  Object? weightSettled = _absent,
  Object? weightRefundAmount = _absent,
}) =>
    <String, dynamic>{
      'id': 1101,
      'customer_id': 78,
      'status': status,
      'total_amount': '1476.00',
      'captured_amount': '1476.00',
      'delivery_sum': '500.00',
      'shipping_lat': 42.3,
      'shipping_lng': 69.6,
      'store_id': 1,
      'store_name': 'F-Mart',
      'delivery_address': 'Шымкент, ул. Байтурсынова, 1',
      'customer_comment': '',
      'payment_method': 'card',
      'is_promo': false,
      'closed': closed,
      'created_at': '2026-10-08T09:00:00Z',
      'updated_at': '2026-10-08T09:05:00Z',
      'items': [
        {
          'id': 7,
          'product_id': 42,
          'qty': 6,
          'price': '155.00',
          'total': '976.00',
          'product': {'name': 'Сыр Emsar для пиццы', 'in_stock': true},
          'unit_g': 50,
          'price_per_kg': '3105.00',
          'ordered_g': 300,
          'buffer_amount': '46.00',
          'charged_g_cap': 315,
          if (actualG != null) 'actual_g': actualG,
          'uom': 'кг',
        },
      ],
      if (!identical(weightSettled, _absent)) 'weight_settled': weightSettled,
      if (!identical(weightRefundAmount, _absent))
        'weight_refund_amount': weightRefundAmount,
    };

const Object _absent = Object();

class FakeOrdersRepository extends OrdersRepository {
  FakeOrdersRepository({required super.api, required this.detail});

  /// What GET /admin/orders/{id} returns. Tests swap it to simulate a reload.
  Map<String, dynamic> detail;

  int settleCalls = 0;
  final List<int> weightPuts = [];
  final List<int> removeCalls = [];
  int refundCalls = 0;

  /// When set, the next call of that kind throws it.
  OrdersApiException? settleError;
  OrdersApiException? weightError;
  OrdersApiException? removeError;
  OrdersApiException? refundError;

  WeightSettleResult settleResult = WeightSettleResult(
    orderId: 1101,
    weightLines: 1,
    due: 98,
    alreadySettled: 0,
    refundAmount: 98,
    refundPublished: true,
    lines: const [],
  );

  @override
  Future<Order?> getOrderById({required int storeId, required int orderId}) async =>
      Order.fromJson(detail);

  @override
  Future<CustomerInfo> getCustomerInfo({required int customerId}) async =>
      CustomerInfo(
        id: customerId,
        phone: '+77011234567',
        firstName: 'Кирилл',
        lastName: 'Тест',
        role: 'customer',
        onesignalUserId: '',
      );

  @override
  Future<OrderStatusesResponse> getOrderStatuses() async =>
      OrderStatusesResponse(items: const []);

  @override
  Future<OrderEventsResponse> getOrderEvents({required int orderId}) async =>
      OrderEventsResponse(orderId: orderId, events: const []);

  @override
  Future<List<RefundHistoryEntry>> getRefundHistory({required int orderId}) async =>
      const [];

  @override
  Future<OrderItemWeightResult> setItemWeight({
    required int orderId,
    required int itemId,
    required int actualG,
  }) async {
    weightPuts.add(actualG);
    final e = weightError;
    if (e != null) throw e;
    return OrderItemWeightResult(
      orderId: orderId,
      itemId: itemId,
      actualG: actualG,
      orderedG: 300,
      chargedGCap: 315,
      weighedAt: DateTime.utc(2026, 10, 8, 9, 10),
      refundPreview: 98,
    );
  }

  @override
  Future<WeightSettleResult> settleOrderWeight({required int orderId}) async {
    settleCalls++;
    final e = settleError;
    if (e != null) throw e;
    return settleResult;
  }

  @override
  Future<OrderItemEditResult> removeItem({
    required int orderId,
    required int itemId,
  }) async {
    removeCalls.add(itemId);
    final e = removeError;
    if (e != null) throw e;
    throw StateError('removeItem success path not faked');
  }

  @override
  Future<SimpleActionResponse> refundOrder({
    required int orderId,
    required double amount,
    required String reason,
    required String idempotencyKey,
    List<int> oosProductIds = const [],
  }) async {
    refundCalls++;
    final e = refundError;
    if (e != null) throw e;
    return SimpleActionResponse(success: true, message: 'Возврат оформлен');
  }
}

/// No courier claim yet (a 404), answered at once: the real repository would
/// reach for secure storage and the network.
class FakeDeliveryRepository extends DeliveryRepository {
  FakeDeliveryRepository({required super.api});

  @override
  Future<GetClaimsResponseDto> getClaimByOrder(int orderId) async {
    final req = RequestOptions(path: '/gw/delivery/$orderId/claim');
    throw DioException(
      requestOptions: req,
      response: Response(requestOptions: req, statusCode: 404),
    );
  }
}

class TestAuthCubit extends AuthCubit {
  TestAuthCubit({
    required super.tokenStorage,
    required super.authRepository,
    required String role,
  }) {
    emit(Authenticated(
      user: CurrentUser(
        id: 1,
        phone: '+70000000000',
        email: null,
        firstName: 'Тест',
        lastName: null,
        role: role,
        assignedStoreIds: const [1],
      ),
    ));
  }
}

/// A store is always selected in the running app, and the page's 8 s poll
/// (the path that brings `weight_settled` after a reload) only runs then.
class TestStoreCubit extends StoreCubit {
  TestStoreCubit({
    required super.storesRepository,
    required super.prefsStorage,
    required super.oneSignalService,
  }) {
    emit(const StoreSelected(
      storeId: 1,
      storeName: 'F-Mart',
      storeAddress: 'Шымкент',
      coordinates: [69.6, 42.3],
    ));
  }
}

/// The page on an iPad-sized surface, seeded like the list would seed it
/// (without the weight_* keys), then polled to the [repo]'s detail.
Future<void> pumpOrderPage(
  WidgetTester t,
  FakeOrdersRepository repo, {
  String role = 'manager',
  Size size = const Size(1024, 1366),
  Map<String, dynamic>? seed,
  ThemeData? theme,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  final tokens = StubTokenStorage();
  final api = repo.api;
  final seedJson = Map<String, dynamic>.from(seed ?? repo.detail)
    ..remove('weight_settled')
    ..remove('weight_refund_amount');

  await t.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<OrdersRepository>.value(value: repo),
        RepositoryProvider<DeliveryRepository>(
          create: (_) => FakeDeliveryRepository(api: api),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>(
            create: (_) => TestAuthCubit(
              tokenStorage: tokens,
              authRepository: StubAuthRepository(api: api, tokenStorage: tokens),
              role: role,
            ),
          ),
          BlocProvider<DeliveryCubit>(
            create: (_) =>
                DeliveryCubit(repo: FakeDeliveryRepository(api: api)),
          ),
          BlocProvider<StoreCubit>(
            create: (_) => TestStoreCubit(
              storesRepository: StoresRepository(api: api),
              prefsStorage: PrefsStorage(),
              oneSignalService: OneSignalService(),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // As app.dart: the admin app's seed colour, Russian locale.
          theme: theme ??
              ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xFFEE6F00)),
                useMaterial3: true,
              ),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OrderDetailsPage(order: Order.fromJson(seedJson)),
        ),
      ),
    ),
  );
  await settle(t);
}

/// Pump enough frames for the immediate poll + customer load to land, without
/// pumpAndSettle (the page keeps an 8 s periodic poll alive).
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Unmount the page so its poll timer is cancelled before the test ends.
Future<void> disposePage(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump();
}

FakeOrdersRepository fakeRepo(Map<String, dynamic> detail) {
  final api = ApiClient(
    baseUrl: 'http://127.0.0.1:1',
    tokenStorage: StubTokenStorage(),
    onUnauthorized: () {},
  );
  return FakeOrdersRepository(api: api, detail: detail);
}

/// Scroll the page's list until [finder] is built and visible.
Future<void> scrollTo(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(
    finder,
    300,
    // The page's own vertical list; other scrollables (horizontal chips, a
    // text field's) come and go with role and status.
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await t.pump();
}

