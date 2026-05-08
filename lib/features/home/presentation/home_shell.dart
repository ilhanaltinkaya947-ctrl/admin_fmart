import 'package:flutter/material.dart';

import '../../customers/presentation/customers_list_page.dart';
import '../../orders/presentation/orders_list_page.dart';

class HomeShell extends StatefulWidget {
  final int storeId;
  final String storeName;

  const HomeShell({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      OrdersListPage(storeId: widget.storeId, storeName: widget.storeName),
      const CustomersListPage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Заказы',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Клиенты',
          ),
        ],
      ),
    );
  }
}
