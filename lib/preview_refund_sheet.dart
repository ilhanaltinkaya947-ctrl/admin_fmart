// Throwaway harness: renders the real order screen with a fabricated paid
// order, so the refund sheet's new out-of-stock picker can be LOOKED AT.
//
// Run:  flutter run -t lib/preview_refund_sheet.dart -d <simulator>
//
// Not referenced by the app and not shipped. Delete once the sheet is signed
// off — it exists because the alternative is judging a bottom sheet from a
// diff, and the last two UI mistakes on this project were both invisible in
// the diff and obvious on the screen.
import 'package:flutter/material.dart';
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/services/onesignal_service.dart';
import 'core/storage/prefs_storage.dart';
import 'core/storage/token_storage.dart';
import 'features/stores/data/stores_repository.dart';
import 'features/stores/state/store_cubit.dart';
import 'features/orders/data/orders_repository.dart';
import 'features/orders/models/order_models.dart';
import 'features/orders/presentation/order_details_page.dart';

void main() => runApp(const _PreviewApp());

/// A real-shaped order: long Russian product names, a weighed line, and enough
/// lines that the picker has to scroll — which is where a fixed-height list
/// would swallow the buttons.
final _order = Order.fromJson({
  'id': 4821,
  'customer_id': 12,
  'status': 'processing',
  'total_amount': '8450.00',
  'captured_amount': '8450.00',
  'store_id': 3,
  'items': [
    {
      'id': 1, 'product_id': 777, 'qty': 1, 'price': '1290.00',
      'total': '1290.00',
      'product': {'name': 'Кофе Jacobs monarch растворимый 300гр стеклянная банка'},
    },
    {
      'id': 2, 'product_id': 778, 'qty': 2, 'price': '890.00',
      'total': '1780.00',
      'product': {'name': 'Пюре Агуша яблоко 90гр дой/пак Россия'},
    },
    {
      'id': 3, 'product_id': 779, 'qty': 1, 'price': '2480.00',
      'total': '2480.00',
      'product': {'name': 'Помидоры розовые весовые'},
    },
    {
      'id': 4, 'product_id': 780, 'qty': 3, 'price': '300.00',
      'total': '900.00',
      'product': {'name': 'Вода Тассай негазированная 0.5л'},
    },
    {
      'id': 5, 'product_id': 781, 'qty': 1, 'price': '2000.00',
      'total': '2000.00',
      'product': {'name': 'Ополаскиватель Listerine total care 6в1 250мл'},
    },
  ],
});

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    // The page reads OrdersRepository from the tree. Nothing here calls it —
    // the sheet is pure UI until «Оформить» — but it must resolve or the
    // screen throws on first build.
    final api = ApiClient(
      baseUrl: 'http://localhost:1',   // never reached
      tokenStorage: TokenStorage(),
      onUnauthorized: () {},
    );
    final repo = OrdersRepository(api: api);
    return MultiProvider(
      providers: [
        Provider<OrdersRepository>.value(value: repo),
        // Deliberately NOT `..bootstrap()` — that fetches stores over the
        // network. The screen only reads the selected store id from this.
        BlocProvider(
          create: (_) => StoreCubit(
            storesRepository: StoresRepository(api: api),
            prefsStorage: PrefsStorage(),
            oneSignalService: OneSignalService(),
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: OrderDetailsPage(order: _order),
      ),
    );
  }
}
