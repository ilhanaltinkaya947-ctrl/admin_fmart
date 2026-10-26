import 'package:flutter/foundation.dart';

/// «Утренняя проверка» push (26.10): catalog sends
/// `{"type": "morning_check", "store_id": N, "count": M}` once a morning, only
/// to app versions that handle it (ops morning_push.py,
/// MORNING_CHECK_APP_VERSIONS). The `morning_check` tag is not the gate.
///
/// It is NOT a new order. The push handlers in app.dart treat every other push
/// as one (siren, counter, non-dismissable dialog), so they must branch on this
/// FIRST: a siren for a stock question at 08:00 teaches staff to mute the one
/// alarm they have to trust.
bool isMorningCheckPush(Map<String, dynamic> data) =>
    data['type'] == 'morning_check';

/// How many products wait for an answer, if the push says.
int? morningCheckCount(Map<String, dynamic> data) {
  final raw = data['count'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

/// The foreground banner text.
String morningCheckBannerText(int? count) {
  if (count == null || count <= 0) {
    return 'Утренняя проверка: есть товары, которые ждут ответа';
  }
  final m10 = count % 10, m100 = count % 100;
  final String noun;
  if (m10 == 1 && m100 != 11) {
    noun = 'товар ждёт';
  } else if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) {
    noun = 'товара ждут';
  } else {
    noun = 'товаров ждут';
  }
  return 'Утренняя проверка: $count $noun ответа';
}

/// A request to show the morning check section, from a push.
///
/// Sticky on purpose: a tap on a cold start arrives before there is a
/// HomeShell to switch (no auth, no store yet). The request waits here and the
/// shell takes it when it mounts, the same idea as `_pendingOpenOrderId`.
///
/// Not itself a Listenable: it is handed down with RepositoryProvider.value,
/// which asserts against Listenables (they belong in a ChangeNotifierProvider
/// that rebuilds on change, which nothing here needs). [requests] is the hook.
class MorningCheckLauncher {
  final ValueNotifier<int> _signal = ValueNotifier<int>(0);
  bool _pending = false;

  /// Fires on every [request].
  Listenable get requests => _signal;

  bool get pending => _pending;

  void request() {
    _pending = true;
    _signal.value++;
  }

  void dispose() => _signal.dispose();

  /// True once per request.
  bool consume() {
    final p = _pending;
    _pending = false;
    return p;
  }
}
