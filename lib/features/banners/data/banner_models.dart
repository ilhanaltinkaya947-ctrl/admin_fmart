/// A home-page banner as returned by catalog-service.
///
/// `startsAt` / `endsAt` are the publish window. Both null means "live while
/// active" — the behaviour every banner had before scheduling existed, so the
/// older rows in the table deserialise to exactly the state they had.
class BannerItem {
  final int id;
  final String imageUrl;
  final String? linkUrl;
  final String? title;
  final int sortOrder;
  final bool active;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BannerItem({
    required this.id,
    required this.imageUrl,
    required this.sortOrder,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    this.linkUrl,
    this.title,
    this.startsAt,
    this.endsAt,
  });

  factory BannerItem.fromJson(Map<String, dynamic> json) {
    return BannerItem(
      // Guarded parse: one banner row with a null/missing id or timestamp
      // used to throw inside listAll().map() and break the entire banners
      // screen (same crash class as the customer-app OrderModel fix).
      id: (json['id'] as num?)?.toInt() ?? 0,
      imageUrl: (json['image_url'] as String?) ?? '',
      linkUrl: json['link_url'] as String?,
      title: json['title'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
      // Nullable on purpose: null is a meaningful state ("no window"), so a
      // parse failure must stay null rather than falling back to DateTime.now()
      // the way the non-nullable timestamps below do.
      startsAt: _tryParse(json['starts_at']),
      endsAt: _tryParse(json['ends_at']),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
              DateTime.now(),
    );
  }

  static DateTime? _tryParse(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  /// What the storefront is currently doing with this banner.
  BannerPublishState get publishState {
    if (!active) return BannerPublishState.disabled;
    final now = DateTime.now();
    final start = startsAt;
    if (start != null && start.isAfter(now)) {
      return BannerPublishState.scheduled;
    }
    final end = endsAt;
    if (end != null && !end.isAfter(now)) {
      return BannerPublishState.expired;
    }
    return BannerPublishState.live;
  }
}

enum BannerPublishState { live, scheduled, expired, disabled }

extension BannerPublishStateLabel on BannerPublishState {
  String get label => switch (this) {
        BannerPublishState.live => 'На главной',
        BannerPublishState.scheduled => 'Запланирован',
        BannerPublishState.expired => 'Истёк',
        BannerPublishState.disabled => 'Отключён',
      };
}
