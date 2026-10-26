import '../../../core/api/api_client.dart';

/// «Утренняя проверка» (26.10): every morning the store manager is asked, per
/// product a picker reported missing, whether it is on the shelf now.
///
/// «Да, есть» lifts the hold (the product shows again, unless 1C itself says
/// 0); «Нет, ещё нет» keeps it hidden one more day and asks again tomorrow.
/// Unanswered holds lapse back to 1C on their own (`lapses_at`).
class MorningCheckItem {
  final int productId;
  final String name;
  final String? imageUrl;

  /// When it was hidden. Null when the server has no stamp (the row still
  /// needs an answer, so it is kept).
  final DateTime? heldAt;

  /// What 1C has for it now. 0 means a «Да, есть» cannot show it yet: the
  /// app would still read 0 until 1C is corrected.
  final int? stock1c;
  final DateTime? lapsesAt;

  /// true «Да, есть», false «Нет, ещё нет», null not answered today.
  final bool? answer;
  final DateTime? answeredAt;

  const MorningCheckItem({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.heldAt,
    required this.stock1c,
    required this.lapsesAt,
    required this.answer,
    required this.answeredAt,
  });

  /// Tolerant, like [HeldProduct.tryFromJson]: one bad row must not blank the
  /// list the manager is working through.
  static MorningCheckItem? tryFromJson(Map<String, dynamic> j) {
    final pid = j['product_id'];
    final id = pid is int ? pid : int.tryParse(pid?.toString() ?? '');
    if (id == null) return null;
    final q = j['stock_1c'];
    final a = j['answer'];
    final img = j['image_url']?.toString();
    return MorningCheckItem(
      productId: id,
      name: (j['name'] ?? '').toString(),
      imageUrl: (img == null || img.isEmpty) ? null : img,
      heldAt: _date(j['held_at']),
      stock1c: q is int ? q : (q is num ? q.toInt() : int.tryParse(q?.toString() ?? '')),
      lapsesAt: _date(j['lapses_at']),
      answer: a is bool ? a : null,
      answeredAt: _date(j['answered_at']),
    );
  }

  /// A stamp without an offset is the server's UTC, not the iPad's clock.
  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    final t = DateTime.tryParse(s);
    if (t == null || t.isUtc) return t;
    final hasOffset = RegExp(r'([+-]\d{2}:?\d{2}|Z)$').hasMatch(s);
    return hasOffset ? t : DateTime.tryParse('${s}Z');
  }
}

class MorningCheckList {
  final int storeId;
  final String? day;
  final bool enabled;
  final List<MorningCheckItem> items;

  const MorningCheckList({
    required this.storeId,
    required this.day,
    required this.enabled,
    required this.items,
  });

  /// Rows nobody has answered today.
  int get remaining => items.where((i) => i.answer == null).length;

  static MorningCheckList fromJson(dynamic data, {required int storeId}) {
    final map = (data as Map?)?.cast<String, dynamic>() ?? const {};
    final raw = (map['items'] as List?) ?? const [];
    final sid = map['store_id'];
    return MorningCheckList(
      storeId: sid is int ? sid : storeId,
      day: map['day']?.toString(),
      // Missing = on: an older catalog that serves the list has the feature.
      enabled: map['enabled'] != false,
      items: raw
          .whereType<Map>()
          .map((e) => MorningCheckItem.tryFromJson(e.cast<String, dynamic>()))
          .whereType<MorningCheckItem>()
          .toList(),
    );
  }
}

class MorningCheckRepository {
  final ApiClient api;
  MorningCheckRepository({required this.api});

  // A normal admin path with catalog's own staff check, like /admin/oos-holds.
  static const _path = '/gw/catalog/admin/morning-check';

  Future<MorningCheckList> list({required int storeId}) async {
    final resp = await api.dio.get(_path, queryParameters: {'store_id': storeId});
    return MorningCheckList.fromJson(resp.data, storeId: storeId);
  }

  /// Answer for one product. The server returns the whole list, so the screen
  /// refreshes from it without a second round-trip.
  Future<MorningCheckList> answer({
    required int storeId,
    required int productId,
    required bool present,
  }) async {
    final resp = await api.dio.post(
      '$_path/answer',
      data: {'store_id': storeId, 'product_id': productId, 'present': present},
    );
    return MorningCheckList.fromJson(resp.data, storeId: storeId);
  }
}

/// «DD.MM HH:MM» on the store's clock. Asia/Almaty is UTC+5 all year (no
/// DST), so a fixed offset is exact and does not depend on the iPad's zone.
String formatAlmaty(DateTime t) {
  final a = t.toUtc().add(const Duration(hours: 5));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(a.day)}.${two(a.month)} ${two(a.hour)}:${two(a.minute)}';
}

/// The line under a row once it has an answer; null while unanswered.
String? morningCheckOutcome(MorningCheckItem i) {
  if (i.answer == true) {
    return i.stock1c == 0
        ? 'в 1С 0: появится после исправления остатка в 1С'
        : 'снова виден в приложении';
  }
  if (i.answer == false) return 'скрыт ещё на день, спросим завтра';
  return null;
}
