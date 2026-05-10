class BannerItem {
  final int id;
  final String imageUrl;
  final String? linkUrl;
  final String? title;
  final int sortOrder;
  final bool active;
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
  });

  factory BannerItem.fromJson(Map<String, dynamic> json) {
    return BannerItem(
      id: (json['id'] as num).toInt(),
      imageUrl: (json['image_url'] as String?) ?? '',
      linkUrl: json['link_url'] as String?,
      title: json['title'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
