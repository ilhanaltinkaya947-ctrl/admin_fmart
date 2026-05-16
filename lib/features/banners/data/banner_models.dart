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
      // Guarded parse: one banner row with a null/missing id or timestamp
      // used to throw inside listAll().map() and break the entire banners
      // screen (same crash class as the customer-app OrderModel fix).
      id: (json['id'] as num?)?.toInt() ?? 0,
      imageUrl: (json['image_url'] as String?) ?? '',
      linkUrl: json['link_url'] as String?,
      title: json['title'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}
