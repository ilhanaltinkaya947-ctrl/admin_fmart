import 'package:onesignal_flutter/onesignal_flutter.dart';

class OneSignalService {
  Future<void> init() async {
    // слушаем уведомления в foreground
    OneSignal.Notifications.addForegroundWillDisplayListener((event) async {
      // не блокируем показ — пусть покажется системно, если хочешь
      event.preventDefault();
      event.notification.display();

      final data = event.notification.additionalData ?? <String, dynamic>{};
      await onForegroundNotification?.call(data);
    });
  }

  Future<String> getUserIdSafe() async {
    try {
      // В разных версиях SDK может быть по-разному.
      // Наша задача: безопасно получить строку или пустую.
      final id = OneSignal.User.pushSubscription.id;
      return id ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> setStoreTag(int storeId) async {
    try {
      OneSignal.User.addTags({"store": storeId.toString()});
    } catch (_) {}
  }

  int? tryExtractOrderId(Map<String, dynamic> data) {
    final raw = data['order_id'] ?? data['orderId'] ?? data['id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Future<void> Function(Map<String, dynamic> data)? onForegroundNotification;
}
