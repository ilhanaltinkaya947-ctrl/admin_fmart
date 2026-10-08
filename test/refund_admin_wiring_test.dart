// `_isAdmin` must come from AuthCubit, not from anything local.
//
// Round 4b LOW: `_canRefund` is only as good as the role it reads. If
// `_isAdmin` ever returned a constant, or read a cached/optimistic value, the
// completed-order rule would be enforced against the wrong person: a manager
// could see the button (or an admin could lose it) with every unit test still
// green, because those tests call `canRefund` directly and pass `isAdmin` in.
//
// This test therefore asserts the WIRING, not the rule: that the page's
// `_isAdmin` derives from `AuthCubit.state`, and specifically from
// `Authenticated.user.isAdmin`. Source-level because the alternative is pumping
// a 3,400-line page with a full DI graph to observe a getter.
//
// What it cannot do: prove the Cubit returns the right role for a given user —
// that is `CurrentUser.isAdmin`, checked in the sibling assertions.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File(
    'lib/features/orders/presentation/order_details_page.dart',
  ).readAsStringSync();

  group('_isAdmin is wired to AuthCubit', () {
    test('it reads AuthCubit', () {
      expect(page.contains("context.read<AuthCubit>()"),
          isTrue, reason: '_isAdmin no longer reads the auth cubit');
    });

    test('it reads the cubit STATE, not a cached field', () {
      expect(page.contains(".state"), isTrue);
      // the state must be inspected for Authenticated
      expect(page.contains("is Authenticated"), isTrue,
          reason: '_isAdmin must check it is in the Authenticated state');
    });

    test('it reads the user role, not a hardcoded value', () {
      expect(page.contains("auth.user.isAdmin"), isTrue,
          reason: '_isAdmin must come from the user, not a constant');
    });

    test('it fails CLOSED: a non-Authenticated state is not admin', () {
      // The expression must be an AND/guard, so loading/unauthenticated is
      // false. A bare `auth.user.isAdmin` would throw or default oddly.
      final i = page.indexOf('bool get _isAdmin');
      expect(i, greaterThan(-1));
      final body = page.substring(i, i + 400);
      expect(body.contains('&&'), isTrue,
          reason: 'the state check must guard the role read (fail closed)');
    });

    test('_canRefund passes BOTH the role and the closed flag', () {
      final i = page.indexOf('bool get _canRefund');
      final body = page.substring(i, i + 300);
      expect(body.contains('isAdmin: _isAdmin'), isTrue);
      expect(body.contains('closed: _order.closed'), isTrue,
          reason: 'the closed flag must reach canRefund or the rule is '
              'status-only again');
    });
  });

  group('CurrentUser.isAdmin is the exact comparison the server uses', () {
    final model = File(
      'lib/features/auth/models/current_user.dart',
    ).readAsStringSync();

    test('only the literal role "admin" counts (not "manager", not a prefix)', () {
      // order-service uses `.strip().lower() != "admin"`, so "Admin " is an
      // admin and "administrator"/"Adminn" are not. A startsWith or contains
      // check here would disagree with the server and offer a button that 403s.
      expect(model.contains("role.toLowerCase() == 'admin'"), isTrue,
          reason: 'the client role check must match the server exact comparison');
      expect(model.contains('startsWith'), isFalse);
      expect(model.contains('contains('), isFalse);
    });
  });
}
