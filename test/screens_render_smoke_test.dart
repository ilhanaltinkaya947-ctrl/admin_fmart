import 'package:admin_fmart/features/customers/data/customers_repository.dart';
import 'package:admin_fmart/features/customers/models/customer_models.dart';
import 'package:admin_fmart/features/customers/presentation/customers_list_page.dart';
import 'package:admin_fmart/features/customers/state/customers_cubit.dart';
import 'package:admin_fmart/features/users/data/users_repository.dart';
import 'package:admin_fmart/features/users/models/user_models.dart';
import 'package:admin_fmart/features/users/presentation/users_list_page.dart';
import 'package:admin_fmart/features/users/state/users_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart';

/// Screens that had NO render test before this file.
///
/// The Баннеры blank page survived a code review, a dedicated state-machine
/// test file, 152 assertions and a clean analyzer run — because it was a LAYOUT
/// crash and nothing had ever rendered the widget. Before this file exactly one
/// of 21 pages had a render test. These close the two most-used list screens.
///
/// They assert the paint is clean and that the screen shows a real state. They
/// are NOT feature tests.
class _StubCustomersRepo implements CustomersRepository {
  @override
  Future<CustomersPage> listCustomers({
    int page = 1,
    int perPage = 20,
    String? q,
  }) async =>
      CustomersPage(pagination: emptyPagination(), items: const []);

  @override
  dynamic noSuchMethod(Invocation i) => NoopProxy().noSuchMethod(i);
}

class _StubUsersRepo implements UsersRepository {
  @override
  Future<AdminUsersPage> list({
    int page = 1,
    int perPage = 20,
    String? q,
  }) async =>
      AdminUsersPage(pagination: emptyPagination(), items: const []);

  @override
  dynamic noSuchMethod(Invocation i) => NoopProxy().noSuchMethod(i);
}

void main() {
  testWidgets('CustomersListPage renders its empty state, no layout throw',
      (t) async {
    final err = await renderProbe(
      t,
      BlocProvider(
        create: (_) => CustomersCubit(repository: _StubCustomersRepo()),
        child: const CustomersListPage(),
      ),
    );
    expect(err, isNull, reason: err ?? '');
    expect(find.text('Клиенты не найдены'), findsOneWidget,
        reason: 'an empty result must render a message, not a blank body');
  });

  testWidgets('UsersListPage renders (role-gated for a non-admin session)',
      (t) async {
    final err = await renderProbe(
      t,
      BlocProvider(
        create: (_) => UsersCubit(repository: _StubUsersRepo()),
        child: const UsersListPage(),
      ),
    );
    expect(err, isNull, reason: err ?? '');
    // The harness has no authenticated admin, so the page shows its role gate.
    // Either way it must PAINT something — a blank body is the failure mode we
    // are guarding, and the gate is correct behaviour, not a defect.
    expect(
      find.text('Раздел доступен только администратору'),
      findsOneWidget,
      reason: 'unauthenticated users must see the gate, not a blank screen',
    );
  });
}
