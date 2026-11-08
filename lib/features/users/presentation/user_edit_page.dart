import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/format/phone.dart';
import '../../auth/state/auth_cubit.dart';
import '../../stores/data/stores_repository.dart';
import '../../stores/models/store_models.dart';
import '../data/users_repository.dart';
import '../models/staff_password.dart';
import '../models/user_models.dart';

/// Sentinel used by _save to bubble validation messages through the
/// existing try/catch so they appear in the error banner the same way a
/// backend error would, without prefixing "Не удалось сохранить".
class _ValidationFailure implements Exception {
  final String message;
  _ValidationFailure(this.message);
}

class UserEditPage extends StatefulWidget {
  final AdminUser? existing;
  const UserEditPage({super.key, this.existing});

  @override
  State<UserEditPage> createState() => _UserEditPageState();
}

class _UserEditPageState extends State<UserEditPage> {
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _role = 'manager';
  late Set<int> _assignedStoreIds;

  Future<List<StoreDto>>? _storesFuture;

  bool _saving = false;
  bool _deleting = false;
  // The user row was saved but a later step failed and the page stayed open:
  // leaving must still tell the list to reload (critic 1.2.9 L5).
  bool _rowSaved = false;
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _phoneCtrl.text = ex.phone;
      _emailCtrl.text = ex.email ?? '';
      _firstNameCtrl.text = ex.firstName ?? '';
      _lastNameCtrl.text = ex.lastName ?? '';
      // Preserve the user's ACTUAL role — don't collapse it to
      // 'manager'. The old code did `ex.isAdmin ? 'admin' : 'manager'`,
      // so opening any user whose role wasn't 'admin' and saving
      // silently rewrote them to 'manager'.
      _role = ex.role.toLowerCase().trim();
      _assignedStoreIds = ex.assignedStoreIds.toSet();
    } else {
      _assignedStoreIds = <int>{};
    }
    _storesFuture = context.read<StoresRepository>().getStores();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    // Edit path only: whether PUT /admin/users/{id} already went through, so a
    // later failure (the stores call) never reads as «nothing was saved»
    // when the new password is in fact already live.
    var userSaved = false;
    var passwordSent = false;

    try {
      final repo = context.read<UsersRepository>();
      final phoneRaw = _phoneCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final firstName = _firstNameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();
      final password = _passwordCtrl.text;
      final stores = _role == 'admin' ? <int>[] : _assignedStoreIds.toList();

      // Reject garbage email early — backend accepts the row but the user
      // can never recover their password without a real address.
      if (email.isNotEmpty && !isPlausibleEmail(email)) {
        throw _ValidationFailure('Email указан некорректно');
      }

      AdminUser saved;
      if (_isCreate) {
        if (phoneRaw.isEmpty) {
          throw _ValidationFailure('Укажите телефон');
        }
        // Normalise to +7XXXXXXXXXX so login matches. Rejecting up-front
        // prevents the "user created but cannot log in" footgun where
        // the admin types something like "test" and the backend stores
        // it verbatim.
        final phone = normaliseKzPhone(phoneRaw);
        if (phone == null) {
          throw _ValidationFailure('Введите корректный номер телефона (+7…)');
        }
        if (password.isEmpty) {
          throw _ValidationFailure('Укажите пароль');
        }
        final problem = staffPasswordProblem(password);
        if (problem != null) throw _ValidationFailure(problem);
        saved = await repo.create(
          phone: phone,
          email: email.isEmpty ? null : email,
          firstName: firstName.isEmpty ? null : firstName,
          lastName: lastName.isEmpty ? null : lastName,
          password: password,
          role: _role,
          assignedStoreIds: stores,
        );
      } else {
        final id = widget.existing!.id;
        // 08.11: a new password the server refuses (under 12 characters, no
        // digit or no letter) used to come back as a bare 400 and read as
        // «такой пользователь уже есть», so the old password silently stayed.
        if (password.isNotEmpty) {
          final problem = staffPasswordProblem(password);
          if (problem != null) throw _ValidationFailure(problem);
        }
        passwordSent = password.isNotEmpty;
        await repo.update(
          id,
          email: email.isEmpty ? null : email,
          firstName: firstName.isEmpty ? null : firstName,
          lastName: lastName.isEmpty ? null : lastName,
          role: _role,
          password: password.isEmpty ? null : password,
        );
        userSaved = true;
        _rowSaved = true;
        saved = await repo.assignStores(id, stores);
      }

      if (!mounted) return;
      final who = saved.fullName == '—' ? saved.phone : saved.fullName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isCreate
                ? 'Пользователь создан'
                : passwordSent
                    ? 'Сохранено. Новый пароль для $who действует'
                    : 'Сохранено: $who',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final reason = _humanError(e);
      final String message;
      if (e is _ValidationFailure) {
        message = reason;
      } else if (userSaved) {
        // The user row (and the password, when one was typed) IS saved; only
        // the shop list failed. Clear the field so a retry does not look like
        // a second password change.
        _passwordCtrl.clear();
        message = passwordSent
            ? 'Новый пароль сохранён, но магазины не сохранились. $reason'
            : 'Данные сохранены, но магазины не сохранились. $reason';
      } else if (e is DioException && backendStatus(e) == null) {
        // No answer at all: the server may have saved it (critic 1.2.9 M2).
        // Resending the same request is safe.
        message = passwordSent
            ? 'Нет связи: неизвестно, сохранился ли новый пароль. Повторите сохранение.'
            : 'Нет связи: неизвестно, сохранилось ли. Повторите сохранение.';
      } else {
        message = passwordSent
            ? 'Не сохранено, старый пароль действует. $reason'
            : 'Не сохранено. $reason';
      }
      setState(() => _error = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ex = widget.existing;
    if (ex == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить пользователя?'),
        content: Text(ex.fullName == '—' ? ex.phone : ex.fullName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _deleting = true);
    try {
      await context.read<UsersRepository>().delete(ex.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пользователь удалён')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить. ${_humanError(e)}');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _humanError(Object e) {
    // Surface validation messages verbatim — they're already user-facing.
    if (e is _ValidationFailure) return e.message;
    // The server's own Russian reason (password rule, duplicate phone, role)
    // is the only thing that tells the admin what to change; show it as is.
    final detail = backendDetail(e);
    if (detail != null) return detail;
    final status = backendStatus(e);
    if (status == 400) return 'Проверьте данные. Возможно, такой пользователь уже есть.';
    if (status == 422) return 'Проверьте данные: email или пароль в неверном формате.';
    if (e is DioException || status != null) {
      return describeApiError(e, subject: 'данные');
    }
    final s = e.toString();
    return s.characters.length > 120 ? s.characters.take(120).toString() : s;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_rowSaved,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop(true);
        },
        child: _page(context),
      );

  Widget _page(BuildContext context) {
    final title = _isCreate ? 'Новый пользователь' : 'Редактировать пользователя';

    // Self-delete guard: an admin opening their own profile must not
    // see the trash button. Backend may permit it, after which the app
    // 401-loops on every subsequent request. Hide the icon entirely
    // for the current user.
    final auth = context.watch<AuthCubit>().state;
    final currentUserId =
        auth is Authenticated ? auth.user.id : null;
    final isSelf = !_isCreate &&
        widget.existing != null &&
        currentUserId != null &&
        widget.existing!.id == currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!_isCreate && !isSelf)
            IconButton(
              tooltip: 'Удалить',
              onPressed: (_saving || _deleting) ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              color: Colors.red.shade600,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _phoneCtrl,
            enabled: _isCreate,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Телефон',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email (опционально)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _firstNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lastNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Фамилия',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _isCreate
                  ? 'Пароль'
                  : 'Новый пароль (оставьте пустым, чтобы не менять)',
              helperText: kStaffPasswordHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Роль',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          // The SegmentedButton only knows manager/admin. If the user
          // has any other role, show it read-only instead of forcing a
          // segment selection (which would both throw an assertion and
          // silently rewrite the role on save).
          if (_role == 'manager' || _role == 'admin')
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'manager',
                  label: Text('Менеджер'),
                  icon: Icon(Icons.support_agent),
                ),
                ButtonSegment(
                  value: 'admin',
                  label: Text('Админ'),
                  icon: Icon(Icons.admin_panel_settings),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Роль «$_role» не редактируется в этом приложении и '
                'будет сохранена без изменений.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (_role == 'manager') ...[
            Text(
              'Магазины',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Менеджер видит только заказы из выбранных магазинов',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<StoreDto>>(
              future: _storesFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                if (snap.hasError || snap.data == null) {
                  return const Text(
                    'Не удалось загрузить магазины',
                    style: TextStyle(color: Colors.red),
                  );
                }
                final stores = snap.data!;
                if (stores.isEmpty) {
                  return const Text('Магазины не найдены');
                }
                return Column(
                  children: stores
                      .map(
                        (s) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _assignedStoreIds.contains(s.storeId),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _assignedStoreIds.add(s.storeId);
                              } else {
                                _assignedStoreIds.remove(s.storeId);
                              }
                            });
                          },
                          title: Text(s.storeName),
                          subtitle: s.storeAddress.isEmpty
                              ? null
                              : Text(s.storeAddress),
                          dense: true,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.purple.shade700),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Администратор имеет доступ ко всем магазинам',
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: (_saving || _deleting) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isCreate ? 'Создать' : 'Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}
