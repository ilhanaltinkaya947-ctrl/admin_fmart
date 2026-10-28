/// A «Новости» post for the customer app's notification center (28.10).
///
/// Written here, shown to customers in Уведомления → Новости. [storeIds]
/// empty means every store. The publish window works like banners: null
/// start = as soon as it is active, null end = never expires.
class NewsPost {
  final int id;
  final String title;
  final String? body;
  final String? titleKk;
  final String? bodyKk;
  final String? imageUrl;
  final List<int> storeIds;
  final bool active;
  final bool pinned;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime publishedAt;
  final DateTime createdAt;

  const NewsPost({
    required this.id,
    required this.title,
    required this.storeIds,
    required this.active,
    required this.pinned,
    required this.publishedAt,
    required this.createdAt,
    this.body,
    this.titleKk,
    this.bodyKk,
    this.imageUrl,
    this.startsAt,
    this.endsAt,
  });

  factory NewsPost.fromJson(Map<String, dynamic> json) {
    final created = _tryParse(json['created_at']) ?? DateTime.now();
    return NewsPost(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      body: json['body'] as String?,
      titleKk: json['title_kk'] as String?,
      bodyKk: json['body_kk'] as String?,
      imageUrl: json['image_url'] as String?,
      storeIds: ((json['store_ids'] as List?) ?? const [])
          .whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      active: json['active'] as bool? ?? true,
      pinned: json['pinned'] as bool? ?? false,
      startsAt: _tryParse(json['starts_at']),
      endsAt: _tryParse(json['ends_at']),
      publishedAt: _tryParse(json['published_at']) ?? created,
      createdAt: created,
    );
  }

  static DateTime? _tryParse(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  NewsPublishState get publishState {
    if (!active) return NewsPublishState.disabled;
    final now = DateTime.now();
    final start = startsAt;
    if (start != null && start.isAfter(now)) return NewsPublishState.scheduled;
    final end = endsAt;
    if (end != null && !end.isAfter(now)) return NewsPublishState.expired;
    return NewsPublishState.live;
  }
}

enum NewsPublishState { live, scheduled, expired, disabled }

extension NewsPublishStateLabel on NewsPublishState {
  String get label => switch (this) {
        NewsPublishState.live => 'Опубликовано',
        NewsPublishState.scheduled => 'Запланировано',
        NewsPublishState.expired => 'Завершено',
        NewsPublishState.disabled => 'Скрыто',
      };
}

/// Limits enforced by catalog-service; mirrored here so the counters and
/// the preview match what the customer will get.
const int kNewsTitleMax = 70;
const int kNewsBodyMax = 300;
