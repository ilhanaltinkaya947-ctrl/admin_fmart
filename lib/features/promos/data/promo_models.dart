/// A promo code as returned by promo-service `/admin/promos`.
///
/// The engine supports exactly two `promoType` values, both free-delivery, and
/// the app does NOT invent a richer campaign shape: exposing a discount percent
/// the engine cannot honour would put a control on screen that lies about what
/// it does. The type picker is built from the server's `/admin/promos/types`, so
/// a type added to the engine appears here with no app release.
class AdminPromo {
  final int id;
  final String code;
  final String promoType;
  final bool enabled;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Redemption ROWS. One customer can hold several (one per order, plus
  /// released attempts), so this is NOT a customer count.
  final int redemptions;
  final int committed;
  final int reserved;
  final int released;

  /// Distinct customers. Deliberately separate from [redemptions]: prod shows
  /// FREEORDER at 119 redemptions but 82 customers, and reading the first as
  /// reach would overstate a campaign by ~45%.
  final int customers;

  const AdminPromo({
    required this.id,
    required this.code,
    required this.promoType,
    required this.enabled,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
    this.redemptions = 0,
    this.committed = 0,
    this.reserved = 0,
    this.released = 0,
    this.customers = 0,
  });

  factory AdminPromo.fromJson(Map<String, dynamic> j) => AdminPromo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        code: (j['code'] as String?) ?? '',
        promoType: (j['promo_type'] as String?) ?? '',
        enabled: j['enabled'] as bool? ?? false,
        // Nullable on purpose: null is "no expiry", a meaningful state. A
        // fallback to now() here would make every code look expired.
        expiresAt: _tryParse(j['expires_at']),
        createdAt: _tryParse(j['created_at']),
        updatedAt: _tryParse(j['updated_at']),
        redemptions: (j['redemptions'] as num?)?.toInt() ?? 0,
        committed: (j['committed'] as num?)?.toInt() ?? 0,
        reserved: (j['reserved'] as num?)?.toInt() ?? 0,
        released: (j['released'] as num?)?.toInt() ?? 0,
        customers: (j['customers'] as num?)?.toInt() ?? 0,
      );

  static DateTime? _tryParse(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }

  bool get isExpired {
    final e = expiresAt;
    if (e == null) return false;
    return DateTime.now().isAfter(e);
  }

  /// What a manager needs to understand at a glance, in the same vocabulary the
  /// Баннеры screen already uses for its state chips.
  AdminPromoState get state {
    if (!enabled) return AdminPromoState.disabled;
    if (isExpired) return AdminPromoState.expired;
    return AdminPromoState.live;
  }

  /// Human wording for the type. The stored value is an engine constant, not
  /// something to show an operator.
  String get typeLabel => switch (promoType) {
        'FREE_DELIVERY_FIRST_ORDER' => 'Бесплатная доставка (первый заказ)',
        'FREE_DELIVERY_TEST_UNLIMITED' => 'Тестовый: доставка без ограничений',
        _ => promoType,
      };

  /// The TEST type is only usable by ids in the server's PROMO_TEST_USER_IDS
  /// allowlist. Today that list holds one id, so a code of this type is dead
  /// for every real customer — worth saying out loud rather than letting
  /// marketing ship it and wonder.
  bool get isTestOnly => promoType == 'FREE_DELIVERY_TEST_UNLIMITED';
}

enum AdminPromoState { live, expired, disabled }

extension AdminPromoStateLabel on AdminPromoState {
  String get label => switch (this) {
        AdminPromoState.live => 'Активен',
        AdminPromoState.expired => 'Истёк',
        AdminPromoState.disabled => 'Отключён',
      };
}

/// One row of a code's redemption history.
class PromoRedemption {
  final int id;
  final int userId;
  final int orderId;
  final String status;
  final double discountSum;
  final String currency;
  final DateTime? createdAt;

  const PromoRedemption({
    required this.id,
    required this.userId,
    required this.orderId,
    required this.status,
    required this.discountSum,
    required this.currency,
    this.createdAt,
  });

  factory PromoRedemption.fromJson(Map<String, dynamic> j) => PromoRedemption(
        id: (j['id'] as num?)?.toInt() ?? 0,
        userId: (j['user_id'] as num?)?.toInt() ?? 0,
        orderId: (j['order_id'] as num?)?.toInt() ?? 0,
        status: (j['status'] as String?) ?? '',
        discountSum: (j['discount_sum'] as num?)?.toDouble() ?? 0,
        currency: (j['currency'] as String?) ?? 'KZT',
        createdAt: AdminPromo._tryParse(j['created_at']),
      );

  String get statusLabel => switch (status) {
        'committed' => 'Применён',
        'reserved' => 'Зарезервирован',
        'released' => 'Освобождён',
        _ => status,
      };
}
