import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class OneSignalService {
  Future<void> init() async {
    // слушаем уведомления в foreground
    OneSignal.Notifications.addForegroundWillDisplayListener((event) async {
      // Telemetry — when staff report "no sound on foreground push", this
      // breadcrumb (visible in Sentry on the next captured event) tells us
      // whether the listener actually fired at all. If it never appears,
      // the push isn't reaching the SDK (likely a binding/subscription
      // issue on OneSignal's side); if it appears but staff still hear
      // nothing, the gap is between this callback and the sound path.
      debugPrint('[OneSignal] foreground push received — id=${event.notification.notificationId}');
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'onesignal',
        level: SentryLevel.info,
        message: 'foreground push received',
        data: {
          'notification_id': event.notification.notificationId,
          'title': event.notification.title ?? '',
          'has_additional_data': event.notification.additionalData != null,
        },
      ));

      // не блокируем показ — пусть покажется системно, если хочешь
      event.preventDefault();
      event.notification.display();

      final data = event.notification.additionalData ?? <String, dynamic>{};
      await onForegroundNotification?.call(data);
    });

    // Notification TAP (open) handler. Fires when staff tap a push while the
    // app is backgrounded OR killed — the normal case on a store iPad that's
    // rarely in the foreground at the exact moment a push lands. Without this,
    // tapping a new-order push only opened the app to the last screen and
    // never routed to the order, defeating push-driven fulfilment.
    OneSignal.Notifications.addClickListener((event) async {
      final data = event.notification.additionalData ?? <String, dynamic>{};
      debugPrint('[OneSignal] push tapped — id=${event.notification.notificationId}');
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'onesignal',
        level: SentryLevel.info,
        message: 'push tapped',
        data: {
          'notification_id': event.notification.notificationId,
          'has_additional_data': event.notification.additionalData != null,
        },
      ));
      await onNotificationClick?.call(data);
    });
  }

  Future<String> getUserIdSafe() async {
    try {
      // В разных версиях SDK может быть по-разному.
      // Наша задача: безопасно получить строку или пустую.
      final id = OneSignal.User.pushSubscription.id;
      return id ?? '';
    } catch (e, st) {
      // Prior debug session burned hours chasing silent push failures —
      // root cause was this catch swallowing an SDK exception. Report
      // so the next regression shows up in Sentry instead of as
      // "managers say push doesn't work."
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'onesignal',
        level: SentryLevel.warning,
        message: 'getUserIdSafe failed: $e',
      ));
      Sentry.captureException(e, stackTrace: st);
      return '';
    }
  }

  Future<void> setStoreTag(int storeId) async {
    try {
      OneSignal.User.addTags({"store": storeId.toString()});
    } catch (e, st) {
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'onesignal',
        level: SentryLevel.warning,
        message: 'setStoreTag($storeId) failed: $e',
      ));
      Sentry.captureException(e, stackTrace: st);
    }
  }

  int? tryExtractOrderId(Map<String, dynamic> data) {
    final raw = data['order_id'] ?? data['orderId'] ?? data['id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Future<void> Function(Map<String, dynamic> data)? onForegroundNotification;
  Future<void> Function(Map<String, dynamic> data)? onNotificationClick;
}
