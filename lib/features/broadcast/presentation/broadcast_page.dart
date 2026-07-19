import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/state/auth_cubit.dart';
import '../data/broadcast_repository.dart';

/// Admin Broadcast tab — send a single push to every subscribed customer.
/// High blast radius, so the page enforces:
///   * confirmation dialog explicitly states "all subscribed customers"
///   * Send button disabled while a request is in flight
///   * post-send success card shows the recipient estimate from OneSignal
class BroadcastPage extends StatefulWidget {
  const BroadcastPage({super.key});

  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final _formKey = GlobalKey<FormState>();
  final _headingCtl = TextEditingController();
  final _messageCtl = TextEditingController();
  BroadcastCategory _category = BroadcastCategory.news;
  bool _sending = false;
  BroadcastResult? _lastResult;
  String? _lastError;

  @override
  void dispose() {
    _headingCtl.dispose();
    _messageCtl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final heading = _headingCtl.text.trim();
    final message = _messageCtl.text.trim();

    final category = _category;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отправить всем?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Уведомление получат ВСЕ подписанные клиенты и попадёт '
              'в раздел «${category.label}». Это действие нельзя отменить.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(c).pop(true),
            icon: const Icon(Icons.send),
            label: const Text('Отправить всем'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _sending = true;
      _lastError = null;
      _lastResult = null;
    });
    try {
      final repo = context.read<BroadcastRepository>();
      final res = await repo.sendToAllCustomers(
        heading: heading,
        message: message,
        category: category,
      );
      if (!mounted) return;
      setState(() {
        _lastResult = res;
        _sending = false;
        _headingCtl.clear();
        _messageCtl.clear();
      });
      _formKey.currentState?.reset();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lastError = 'Не удалось отправить рассылку. Попробуйте ещё раз.';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Defense in depth: the nav rail already hides this tab from
    // managers, but a deep link / restored Navigator state could land
    // a non-admin here directly. The body MUST refuse — sending a push
    // to every customer is the highest blast-radius action in this app.
    final auth = context.watch<AuthCubit>().state;
    final isAdmin = auth is Authenticated && auth.user.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Рассылка')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Раздел доступен только администратору',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Рассылка')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Уведомление будет отправлено всем клиентам, '
                          'у которых разрешены push-уведомления.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 4),
                      child: Text(
                        'Раздел',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SegmentedButton<BroadcastCategory>(
                      segments: const [
                        ButtonSegment(
                          value: BroadcastCategory.news,
                          label: Text('Новости'),
                          icon: Icon(Icons.campaign_outlined),
                        ),
                        ButtonSegment(
                          value: BroadcastCategory.promo,
                          label: Text('Акция'),
                          icon: Icon(Icons.local_offer_outlined),
                        ),
                      ],
                      selected: {_category},
                      onSelectionChanged: _sending
                          ? null
                          : (s) => setState(() => _category = s.first),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 12),
                      child: Text(
                        'Определяет вкладку в приложении клиента, '
                        'куда придёт уведомление.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: _headingCtl,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Заголовок',
                        border: OutlineInputBorder(),
                        helperText: 'Короткий заголовок (до 120 символов)',
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Введите заголовок';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _messageCtl,
                      maxLength: 500,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Сообщение',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Введите текст сообщения';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _sending ? 'Отправка…' : 'Отправить всем клиентам',
                  ),
                ),
              ),
              if (_lastResult != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Рассылка отправлена',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (_lastResult!.recipients != null)
                                Text(
                                  'Получателей: ~${_lastResult!.recipients}',
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_lastError != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_lastError!)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
