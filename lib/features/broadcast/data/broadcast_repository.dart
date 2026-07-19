import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';

/// Wraps the notification-service broadcast endpoint. Admin-only on
/// the backend; the admin app self-gates the nav entry too.
class BroadcastRepository {
  final ApiClient api;
  BroadcastRepository({required this.api});

  Future<BroadcastResult> sendToAllCustomers({
    required String heading,
    required String message,
    required BroadcastCategory category,
  }) async {
    final resp = await api.dio.post(
      '/gw/notification/admin/broadcast',
      data: {
        'heading': heading,
        'message': message,
        'type': category.wire,
      },
    );
    final j = asJsonMap(resp.data);
    return BroadcastResult(
      onesignalId: j['onesignal_id']?.toString(),
      recipients: j['recipients'] as int?,
    );
  }
}

/// Determines which inbox tab the push lands in on the customer device.
/// Wire values must match the backend Literal: `news` | `promo`.
enum BroadcastCategory {
  news('news', 'Новости'),
  promo('promo', 'Акция');

  final String wire;
  final String label;
  const BroadcastCategory(this.wire, this.label);
}

class BroadcastResult {
  final String? onesignalId;
  final int? recipients;

  BroadcastResult({this.onesignalId, this.recipients});
}
