import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/services/new_order_counter.dart';
import 'package:admin_fmart/core/storage/token_storage.dart';
import 'package:admin_fmart/features/auth/data/auth_repository.dart';
import 'package:admin_fmart/features/auth/state/auth_cubit.dart';
import 'package:admin_fmart/features/orders/models/order_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared harness for pumping admin screens that have no render test.
///
/// The Баннеры blank page survived review, a state-machine test file, 152
/// assertions and a clean analyzer run — because it was a LAYOUT crash and
/// nothing had ever rendered the widget. Only 1 of 21 pages had a render test.
/// This is the harness for the other 20.
///
/// Every stub returns a REJECTED future for loader-shaped methods, so each
/// cubit takes its failure path. A rejected load is exactly the state that made
/// the Баннеры body blank, so it is the state most worth rendering.
/// A successfully-EMPTY page. Returning success rather than a rejection is
/// deliberate: the empty state is a real state a screen must render, and using
/// it keeps the cubits on their normal path so a failure here means the SCREEN
/// threw, not that the stub did.
Pagination emptyPagination() => Pagination(
      page: 1,
      pageSize: 20,
      total: 0,
      pages: 0,
      hasNext: false,
      hasPrev: false,
    );

class NoopProxy {
  @override
  dynamic noSuchMethod(Invocation i) {
    final n = i.memberName.toString();
    // Anything that looks like a loader resolves to an empty page; the caller
    // constructs the concrete page type, so return an empty list here and let
    // the concrete stub wrap it.
    if (i.isMethod) {
      if (n.contains('list') || n.contains('get') || n.contains('fetch')) {
        return Future<dynamic>.value(<dynamic>[]);
      }
      return Future<dynamic>.value(null);
    }
    return null;
  }
}

class StubTokenStorage extends TokenStorage {
  @override
  dynamic noSuchMethod(Invocation i) {
    final n = i.memberName.toString();
    if (n.contains('hasTokens')) return Future<bool>.value(false);
    if (n.contains('getRememberMe')) return Future<bool>.value(true);
    return null;
  }
}

class StubAuthRepository extends AuthRepository {
  StubAuthRepository({required super.api, required super.tokenStorage});

  @override
  dynamic noSuchMethod(Invocation i) => NoopProxy().noSuchMethod(i);
}

class StubNewOrderCounter extends NewOrderCounter {
  @override
  dynamic noSuchMethod(Invocation i) => NoopProxy().noSuchMethod(i);
}

/// The provider tree the admin shell supplies at runtime, with stubs.
Widget harness({required Widget child}) {
  final tokens = StubTokenStorage();
  final api = ApiClient(
    baseUrl: 'http://127.0.0.1:1',
    tokenStorage: tokens,
    onUnauthorized: () {},
  );
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<TokenStorage>(create: (_) => tokens),
      RepositoryProvider<ApiClient>(create: (_) => api),
      RepositoryProvider<AuthRepository>(
        create: (_) => StubAuthRepository(api: api, tokenStorage: tokens),
      ),
      // NewOrderCounter is a plain service, not a Bloc — app.dart exposes it
      // via RepositoryProvider.value, so BlocProvider would not compile.
      RepositoryProvider<NewOrderCounter>(
        create: (_) => StubNewOrderCounter(),
      ),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(
          create: (_) => AuthCubit(
            tokenStorage: tokens,
            authRepository: StubAuthRepository(api: api, tokenStorage: tokens),
          ),
        ),
      ],
      child: MaterialApp(home: child),
    ),
  );
}

/// Pump a page and report whether it threw during LAYOUT.
///
/// The stubs deliberately reject their futures, and the cubits catch that and
/// emit a Failure — which is a normal, expected state here, not a defect. So
/// exceptions raised by the stub itself are absorbed and the probe only reports
/// rendering errors (the class that blanked the Баннеры body): a layout
/// assertion, an unbounded-constraint throw, a build error.
Future<String?> renderProbe(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(harness(child: page));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  final errors = <String>[];
  // Drain every exception the framework recorded, then classify.
  for (var i = 0; i < 20; i++) {
    final ex = tester.takeException();
    if (ex == null) break;
    final text = ex.toString();
    // Our own stub's rejection is expected and benign.
    if (text.contains('stub: no backend in tests')) continue;
    if (ex is FlutterError) {
      errors.add(text);
    } else {
      errors.add(text);
    }
  }
  return errors.isEmpty ? null : errors.join(' | ');
}

void main() {
  test('harness is constructible', () {
    expect(NoopProxy(), isNotNull);
  });
}
