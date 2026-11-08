// 08.11 bug: an admin changed a manager's password in Пользователи → user
// edit → «Новый пароль», and the old password stayed.
//
// Cause: auth-service only accepts a staff password of 12+ characters with a
// digit and a letter (AuthService._validate_staff_password) and answers
// anything else with a 400 carrying a Russian `detail`. The edit screen had no
// such check, and turned EVERY 400 into «Проверь данные. Возможно, такой
// пользователь уже есть.», so the admin never learned the password was the
// problem. The success toast never mentioned the password either.
//
// These drive the REAL UserEditPage, UsersRepository and ApiClient through a
// stub HTTP adapter that answers like auth-service does. The page is opened
// from a second pushed route, the way users_list_page opens it.

import 'dart:convert';
import 'dart:typed_data';

import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/storage/token_storage.dart';
import 'package:admin_fmart/features/auth/data/auth_repository.dart';
import 'package:admin_fmart/features/auth/state/auth_cubit.dart';
import 'package:admin_fmart/features/stores/data/stores_repository.dart';
import 'package:admin_fmart/features/users/data/users_repository.dart';
import 'package:admin_fmart/features/users/models/staff_password.dart';
import 'package:admin_fmart/features/users/models/user_models.dart';
import 'package:admin_fmart/features/users/presentation/user_edit_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tokens extends TokenStorage {
  @override
  Future<String?> getAccessToken() async => 'test-access-token';
  @override
  Future<bool> hasTokens() async => false;
}

class _Req {
  final String method;
  final String path;
  final Object? data;
  _Req(this.method, this.path, this.data);
}

/// Answers like auth-service: the staff password rule, a 400 with a Russian
/// detail when it fails, the user row on success.
class _FakeAuthService implements HttpClientAdapter {
  final requests = <_Req>[];
  String? refusePasswordWith; // a server refusal the app cannot predict
  bool storesFail = false;
  bool dropUserPut = false; // the request leaves, no answer comes back

  static const _user = {
    'id': 7,
    'phone': '+77011234567',
    'first_name': 'Айгерим',
    'last_name': 'Менеджер',
    'role': 'manager',
    'assigned_store_ids': [3],
    'created_at': '2026-11-01T10:00:00',
  };

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _,
      Future<void>? __) async {
    requests.add(_Req(o.method, o.path, o.data));
    if (o.path == '/gw/catalog/stores') return _json(200, <Object>[]);
    if (o.method == 'PUT' && o.path == '/gw/auth/admin/users/7') {
      if (dropUserPut) {
        throw DioException(
            requestOptions: o, type: DioExceptionType.receiveTimeout);
      }
      final body = o.data as Map;
      final pw = body['password'];
      if (pw is String) {
        if (pw.length < 12) {
          return _json(400, {'detail': 'Пароль должен содержать не менее 12 символов'});
        }
        if (refusePasswordWith != null) {
          return _json(400, {'detail': refusePasswordWith});
        }
      }
      return _json(200, _user);
    }
    if (o.method == 'PUT' && o.path == '/gw/auth/admin/users/7/stores') {
      if (storesFail) return _json(500, {'detail': 'Internal Server Error'});
      return _json(200, _user);
    }
    return _json(404, {'detail': 'Not Found'});
  }

  @override
  void close({bool force = false}) {}

  List<_Req> get userPuts => requests
      .where((r) => r.method == 'PUT' && r.path == '/gw/auth/admin/users/7')
      .toList();
}

final _manager = AdminUser.fromJson(const {
  'id': 7,
  'phone': '+77011234567',
  'first_name': 'Айгерим',
  'last_name': 'Менеджер',
  'role': 'manager',
  'assigned_store_ids': [3],
  'created_at': '2026-11-01T10:00:00',
});

/// What the editor popped with (users_list_page reloads on `true`).
Object? _popResult = 'not popped';

Future<_FakeAuthService> _openEditor(WidgetTester tester) async {
  _popResult = 'not popped';
  final server = _FakeAuthService();
  final tokens = _Tokens();
  final api = ApiClient(
    baseUrl: 'http://stub.invalid',
    tokenStorage: tokens,
    onUnauthorized: () {},
  );
  api.dio.httpClientAdapter = server;
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<UsersRepository>(
            create: (_) => UsersRepository(api: api)),
        RepositoryProvider<StoresRepository>(
            create: (_) => StoresRepository(api: api)),
      ],
      child: BlocProvider<AuthCubit>(
        create: (_) => AuthCubit(
          tokenStorage: tokens,
          authRepository: AuthRepository(api: api, tokenStorage: tokens),
        ),
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    _popResult = await Navigator.of(ctx).push(
                      MaterialPageRoute<bool>(
                        builder: (_) => UserEditPage(existing: _manager),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(UserEditPage), findsOneWidget);
  return server;
}

Finder _passwordField() => find.byWidgetPredicate(
    (w) => w is TextField && (w.obscureText));

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(ElevatedButton, 'Сохранить');
  await tester.ensureVisible(save);
  await tester.tap(save);
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
      'a short new password is refused BEFORE the call, naming the 12 character rule',
      (tester) async {
    final server = await _openEditor(tester);
    await tester.enterText(_passwordField(), 'abc123');
    await _save(tester);

    expect(server.userPuts, isEmpty,
        reason: 'the server would refuse it; nothing should be sent');
    expect(find.textContaining('не менее 12 символов'), findsWidgets);
    expect(find.textContaining('такой пользователь уже есть'), findsNothing);
    expect(find.byType(UserEditPage), findsOneWidget, reason: 'stays open');
  });

  testWidgets('a valid new password is sent as `password` and the toast says so',
      (tester) async {
    final server = await _openEditor(tester);
    await tester.enterText(_passwordField(), 'Shymkent2026x');
    await _save(tester);

    expect(server.userPuts, hasLength(1));
    expect((server.userPuts.single.data as Map)['password'], 'Shymkent2026x');
    expect(find.textContaining('Новый пароль для Айгерим Менеджер действует'),
        findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(UserEditPage), findsNothing, reason: 'closed on success');
  });

  testWidgets(
      'a server refusal is shown as the server wrote it and says the old password stays',
      (tester) async {
    final server = await _openEditor(tester);
    server.refusePasswordWith = 'Пароль слишком простой';
    await tester.enterText(_passwordField(), 'Shymkent2026x');
    await _save(tester);

    expect(server.userPuts, hasLength(1));
    expect(
        find.text('Не сохранено, старый пароль действует. Пароль слишком простой'),
        findsWidgets);
    expect(find.textContaining('такой пользователь уже есть'), findsNothing);
    expect(find.byType(UserEditPage), findsOneWidget);
  });

  testWidgets(
      'password saved but the shop list failed: says the password IS saved',
      (tester) async {
    final server = await _openEditor(tester);
    server.storesFail = true;
    await tester.enterText(_passwordField(), 'Shymkent2026x');
    await _save(tester);

    expect(server.userPuts, hasLength(1));
    expect(find.textContaining('Новый пароль сохранён, но магазины не сохранились'),
        findsWidgets);
    final field = tester.widget<TextField>(_passwordField());
    expect(field.controller!.text, isEmpty,
        reason: 'a retry must not look like a second password change');
  });

  testWidgets(
      'no answer from the server: does NOT claim the old password still works (critic M2)',
      (tester) async {
    final server = await _openEditor(tester);
    server.dropUserPut = true;
    await tester.enterText(_passwordField(), 'Shymkent2026x');
    await _save(tester);

    expect(find.textContaining('неизвестно, сохранился ли новый пароль'),
        findsWidgets);
    expect(find.textContaining('старый пароль действует'), findsNothing);
  });

  testWidgets(
      'leaving after «saved, shops failed» still tells the list to reload (critic L5)',
      (tester) async {
    final server = await _openEditor(tester);
    server.storesFail = true;
    await tester.enterText(_passwordField(), 'Shymkent2026x');
    await _save(tester);
    await tester.pumpAndSettle();

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(UserEditPage), findsNothing);
    expect(_popResult, isTrue);
  });

  testWidgets('an empty password field sends no `password` key',
      (tester) async {
    final server = await _openEditor(tester);
    await _save(tester);

    expect(server.userPuts, hasLength(1));
    expect((server.userPuts.single.data as Map).containsKey('password'), isFalse);
    expect(find.textContaining('Сохранено: Айгерим Менеджер'), findsOneWidget);
  });

  group('staffPasswordProblem mirrors auth-service', () {
    test('length: 11 refused, 12 accepted', () {
      expect(staffPasswordProblem('abcdefghij1'), contains('12'));
      expect(staffPasswordProblem('abcdefghijk1'), isNull);
    });
    test('needs a digit and a letter', () {
      expect(staffPasswordProblem('abcdefghijkl'), contains('цифру'));
      expect(staffPasswordProblem('123456789012'), contains('букву'));
    });
    test('Cyrillic letters count as letters, length counts characters', () {
      expect(staffPasswordProblem('пароль123456'), isNull);
    });
    test('the hint names the same minimum', () {
      expect(kStaffPasswordHint, contains('$kStaffPasswordMinLength'));
    });
  });
}
