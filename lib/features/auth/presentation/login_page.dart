import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/services/onesignal_service.dart';
import '../data/auth_repository.dart';
import '../state/auth_cubit.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      debugPrint('[LOGIN] start');

      final repo = context.read<AuthRepository>();
      final oneSignal = context.read<OneSignalService>();

      debugPrint('[LOGIN] before osId');
      final osId = await oneSignal.getUserIdSafe();
      debugPrint('[LOGIN] osId=$osId');

      debugPrint('[LOGIN] before repo.login');
      await repo.login(
        phone: _phone.text.trim(),
        password: _pass.text,
        onesignalUserId: osId,
      );
      debugPrint('[LOGIN] repo.login done');

      if (!mounted) return;

      debugPrint('[LOGIN] before setAuthenticated');
      await context.read<AuthCubit>().setAuthenticated();
      debugPrint('[LOGIN] setAuthenticated done');
    } catch (e, st) {
      debugPrint('[LOGIN] error: $e\n$st');
      setState(() => _error = 'Не удалось войти. Проверь телефон/пароль.');
    } finally {
      debugPrint('[LOGIN] finally - mounted=$mounted');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Имя пользователя',
              hintText: 'Имя пользователя',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Пароль',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text('Войти'),
            ),
          ),
        ],
      ),
    );
  }
}
