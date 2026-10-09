// Throwaway harness for the held-products screen, with a stubbed repository so
// it renders without a backend. Same reason as preview_refund_sheet.dart: the
// last three UI faults on this project were invisible in the diff.
//
// Run:  flutter run -t lib/preview_held_products.dart -d <simulator>
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/api/api_client.dart';
import 'core/storage/token_storage.dart';
import 'features/stock/data/held_products_repository.dart';
import 'features/stock/presentation/held_products_page.dart';

/// Returns a fixed list instead of calling the gateway.
class _StubRepo extends HeldProductsRepository {
  _StubRepo()
      : super(
          api: ApiClient(
            baseUrl: 'http://localhost:1',
            tokenStorage: TokenStorage(),
            onUnauthorized: () {},
          ),
        );

  final _items = <HeldProduct>[
    HeldProduct(
      productId: 777,
      name: 'Кофе Jacobs monarch растворимый 300гр стеклянная банка',
      quantityReportedBy1c: 54,
      heldAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    HeldProduct(
      productId: 778,
      name: 'Помидоры розовые весовые',
      quantityReportedBy1c: 571,
      heldAt: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
    ),
    HeldProduct(
      productId: 779,
      name: 'Ополаскиватель Listerine total care 6в1 250мл пл/бут',
      quantityReportedBy1c: null,
      heldAt: DateTime.now().subtract(const Duration(days: 6)),
    ),
  ];

  @override
  Future<List<HeldProduct>> list({required int storeId}) async => _items;

  @override
  Future<List<HeldProduct>> release({
    required int storeId,
    required List<int> productIds,
  }) async {
    _items.removeWhere((e) => productIds.contains(e.productId));
    return _items;
  }
}

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<HeldProductsRepository>.value(value: _StubRepo()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: const HeldProductsPage(storeId: 3, storeName: 'F-Mart Фиркан Сити'),
      ),
    );
  }
}
