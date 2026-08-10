class OrdersPage {
  final Pagination pagination;
  final List<Order> items;

  OrdersPage({required this.pagination, required this.items});

  factory OrdersPage.fromJson(Map<String, dynamic> j) {
    return OrdersPage(
      // Guarded: a 200 response missing/odd `pagination` (error envelope,
      // partial body) used to throw `null as Map` and crash the orders
      // list. Pagination.fromJson null-defaults every field.
      pagination: Pagination.fromJson(
          (j['pagination'] as Map?)?.cast<String, dynamic>() ?? const {}),
      items: ((j['items'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(Order.fromJson)
          .toList(),
    );
  }
}

class Pagination {
  final int page;
  final int pageSize;
  final int total;
  final int pages;
  final bool hasNext;
  final bool hasPrev;

  Pagination({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.pages,
    required this.hasNext,
    required this.hasPrev,
  });

  factory Pagination.fromJson(Map<String, dynamic> j) => Pagination(
    page: j['page'] as int? ?? 1,
    pageSize: j['page_size'] as int? ?? 10,
    total: j['total'] as int? ?? 0,
    pages: j['pages'] as int? ?? 1,
    hasNext: j['has_next'] as bool? ?? false,
    hasPrev: j['has_prev'] as bool? ?? false,
  );
}

class Order {
  final int id;
  final int customerId;
  final String status;
  final String totalAmount;
  final String deliverySum;

  final double shippingLat;
  final double shippingLng;

  final int storeId;
  final String storeName;
  final String deliveryAddress;

  /// 'delivery' (courier) or 'pickup' (самовывоз).
  ///
  /// Defaults to delivery, so an order-service that predates this field — and
  /// every historical order — reads exactly as it does today.
  ///
  /// For a PICKUP order [deliveryAddress] holds the STORE's address, i.e. where
  /// the customer collects. Without this flag a manager reading that field
  /// would think the customer lives at the shop.
  final String fulfillmentType;
  final String customerComment;
  final String paymentMethod;
  final bool isPromo;
  final DateTime createdAt;
  final DateTime updatedAt;
  // Set only when status == 'scheduled'. ISO UTC string of the next
  // 09:00 Almaty boundary — surfaced on the Запланированные tab so a
  // manager can sort by urgency / see when each order would naturally
  // release. Parsed leniently; null on rows from before the feature.
  final DateTime? scheduledForAt;
  // Packaging — surfaced to the picker so they pack the right
  // bag count without guessing. Big bag = 30₸ (handles 7+ items),
  // medium bag = 15₸ (handles up to 6 items). Backend computes
  // counts in cart-service.checkout and stores them on the order;
  // admin just displays. null on legacy orders (before 2026-05-28).
  final int? bigBagCount;
  final int? mediumBagCount;
  final double? packagingSum;
  final List<OrderItem> items;

  // Item substitution ("Замена товара"). `substitutions` = full array on the
  // order-detail response; the two flags are the lightweight signals (also
  // present on list rows).
  final List<OrderSubstitution> substitutions;
  final bool hasPendingSubstitution;
  final DateTime? pendingSubstitutionExpiresAt;

  Order({
    required this.id,
    required this.customerId,
    required this.status,
    required this.totalAmount,
    required this.deliverySum,
    required this.shippingLat,
    required this.shippingLng,
    required this.storeId,
    required this.storeName,
    required this.deliveryAddress,
    this.fulfillmentType = 'delivery',
    required this.customerComment,
    required this.paymentMethod,
    required this.isPromo,
    required this.createdAt,
    required this.updatedAt,
    this.scheduledForAt,
    this.bigBagCount,
    this.mediumBagCount,
    this.packagingSum,
    required this.items,
    this.substitutions = const [],
    this.hasPendingSubstitution = false,
    this.pendingSubstitutionExpiresAt,
  });

  /// The open (still-awaiting-customer) proposal for [itemId], if any.
  OrderSubstitution? openSubstitutionForItem(int itemId) {
    for (final s in substitutions) {
      if (s.orderItemId == itemId && s.isOpen) return s;
    }
    return null;
  }

  /// True while ANY substitution is still awaiting the customer. Advancing the
  /// order to ready-for-delivery/delivering is blocked (backend + UI) until
  /// every proposal resolves.
  bool get hasOpenSubstitution => substitutions.any((s) => s.isOpen);

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory Order.fromJson(Map<String, dynamic> j) => Order(
    id: j['id'] as int? ?? 0,
    customerId: j['customer_id'] as int? ?? 0,
    status: j['status'] as String? ?? '',
    totalAmount: j['total_amount']?.toString() ?? '0',
    deliverySum: j['delivery_sum']?.toString() ?? '0',
    shippingLat: _toDouble(j['shipping_lat']),
    shippingLng: _toDouble(j['shipping_lng']),
    storeId: j['store_id'] as int? ?? 0,
    storeName: j['store_name'] as String? ?? '',
    deliveryAddress: j['delivery_address'] as String? ?? '',
    // `is String` rather than `as String?`: a cast throws on any non-string,
    // and this is the field that decides whether courier controls appear. It
    // must never be the reason an order screen fails to open.
    fulfillmentType: (j['fulfillment_type'] is String) &&
            (j['fulfillment_type'] as String).trim().toLowerCase() == 'pickup'
        ? 'pickup'
        // Anything else — absent, null, unrecognised, or from an older
        // order-service — is a courier delivery. Never guess pickup: a wrongly
        // "pickup" order would have its courier controls hidden and would
        // simply never be delivered.
        : 'delivery',
    customerComment: j['customer_comment'] as String? ?? '',
    paymentMethod: j['payment_method'] as String? ?? '',
    isPromo: j['is_promo'] as bool? ?? false,
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? '') ?? DateTime.now(),
    scheduledForAt: j['scheduled_for_at'] != null
        ? DateTime.tryParse(j['scheduled_for_at'].toString())
        : null,
    bigBagCount: j['big_bag_count'] as int?,
    mediumBagCount: j['medium_bag_count'] as int?,
    packagingSum: j['packaging_sum'] != null
        ? _toDouble(j['packaging_sum'])
        : null,
    items: ((j['items'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map(OrderItem.fromJson)
        .toList(),
    substitutions: ((j['substitutions'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => OrderSubstitution.fromJson(m.cast<String, dynamic>()))
        .toList(),
    hasPendingSubstitution: j['has_pending_substitution'] as bool? ?? false,
    pendingSubstitutionExpiresAt: j['pending_substitution_expires_at'] == null
        ? null
        : DateTime.tryParse(j['pending_substitution_expires_at'].toString()),
  );

  Order copyWith({
    String? status,
    String? totalAmount,
    List<OrderItem>? items,
    int? bigBagCount,
    int? mediumBagCount,
    double? packagingSum,
    List<OrderSubstitution>? substitutions,
    bool? hasPendingSubstitution,
  }) =>
      Order(
        id: id,
        customerId: customerId,
        status: status ?? this.status,
        totalAmount: totalAmount ?? this.totalAmount,
        deliverySum: deliverySum,
        shippingLat: shippingLat,
        shippingLng: shippingLng,
        storeId: storeId,
        storeName: storeName,
        deliveryAddress: deliveryAddress,
        // MUST be carried. The constructor DEFAULTS this to 'delivery', so
        // omitting it here does not fail loudly — it silently converts a
        // самовывоз order into a courier one. `_order = _order.copyWith(status: …)`
        // runs immediately after a manager saves a status change
        // (order_details_page.dart:457), so the bug would fire on the single
        // most common action in the flow: courier controls reappear, the badge
        // reverts to «Готов к доставке», and «В пути» becomes selectable again
        // on an order the customer is walking to collect.
        //
        // Deliberately NOT exposed as a copyWith parameter. How an order is
        // fulfilled is decided at checkout and is never a local edit.
        fulfillmentType: fulfillmentType,
        customerComment: customerComment,
        paymentMethod: paymentMethod,
        isPromo: isPromo,
        createdAt: createdAt,
        updatedAt: updatedAt,
        scheduledForAt: scheduledForAt,
        bigBagCount: bigBagCount ?? this.bigBagCount,
        mediumBagCount: mediumBagCount ?? this.mediumBagCount,
        packagingSum: packagingSum ?? this.packagingSum,
        items: items ?? this.items,
        substitutions: substitutions ?? this.substitutions,
        hasPendingSubstitution:
            hasPendingSubstitution ?? this.hasPendingSubstitution,
        pendingSubstitutionExpiresAt: pendingSubstitutionExpiresAt,
      );
}

/// A manager's proposed replacement for an out-of-stock order item, awaiting
/// the customer's accept/decline. Mirrors the order-service
/// order_item_substitutions row surfaced on the order-detail response.
class OrderSubstitution {
  final int id;
  final int orderItemId;
  final String status; // proposed | accepted | declined | expired | canceled
  final int originalProductId;
  final String originalPrice;
  final int originalQty;
  final int substituteProductId;
  final String substituteName;
  final String substitutePrice;
  final int substituteQty;
  final String? managerNote;
  final String? refundAmount;
  final DateTime? expiresAt;
  final DateTime? respondedAt;

  OrderSubstitution({
    required this.id,
    required this.orderItemId,
    required this.status,
    required this.originalProductId,
    required this.originalPrice,
    required this.originalQty,
    required this.substituteProductId,
    required this.substituteName,
    required this.substitutePrice,
    required this.substituteQty,
    this.managerNote,
    this.refundAmount,
    this.expiresAt,
    this.respondedAt,
  });

  bool get isOpen => status == 'proposed';

  static int _i(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  factory OrderSubstitution.fromJson(Map<String, dynamic> j) =>
      OrderSubstitution(
        id: _i(j['id']),
        orderItemId: _i(j['order_item_id']),
        status: j['status'] as String? ?? '',
        originalProductId: _i(j['original_product_id']),
        originalPrice: j['original_price']?.toString() ?? '0',
        originalQty: _i(j['original_qty']),
        substituteProductId: _i(j['substitute_product_id']),
        substituteName: j['substitute_name'] as String? ?? '',
        substitutePrice: j['substitute_price']?.toString() ?? '0',
        substituteQty: _i(j['substitute_qty']),
        managerNote: j['manager_note'] as String?,
        refundAmount: j['refund_amount']?.toString(),
        expiresAt: j['expires_at'] == null
            ? null
            : DateTime.tryParse(j['expires_at'].toString()),
        respondedAt: j['responded_at'] == null
            ? null
            : DateTime.tryParse(j['responded_at'].toString()),
      );
}

/// A candidate substitute from catalog `/products/similar-products`
/// (ProductResponse), filtered ≤ the OOS item's price. Shown in the
/// admin picker sheet.
class SimilarProduct {
  final int id; // product_id
  final String name;
  final double price;
  final double? salePrice;
  final bool onSale;
  final bool inStock;
  final String? imageUrl;

  SimilarProduct({
    required this.id,
    required this.name,
    required this.price,
    this.salePrice,
    required this.onSale,
    required this.inStock,
    this.imageUrl,
  });

  /// Effective sell price = sale price when on sale, else base price. This is
  /// the number the backend refunds against, so it's what the manager sees.
  double get effectivePrice =>
      (onSale && salePrice != null && salePrice! > 0) ? salePrice! : price;

  static double _d(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
  static int _i(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  factory SimilarProduct.fromJson(Map<String, dynamic> j) => SimilarProduct(
        id: _i(j['id'] ?? j['product_id']),
        name: j['name'] as String? ?? '',
        price: _d(j['price']),
        salePrice: j['sale_price'] == null ? null : _d(j['sale_price']),
        onSale: j['on_sale'] as bool? ?? false,
        inStock: j['in_stock'] as bool? ?? false,
        imageUrl: j['image_url'] as String?,
      );
}



class OrderItem {
  final int id;
  final int productId;
  final int qty;
  final String price;
  final String total;
  final ProductInfo product;
  final DateTime? pickedAt;

  OrderItem({
    required this.id,
    required this.productId,
    required this.qty,
    required this.price,
    required this.total,
    required this.product,
    this.pickedAt,
  });

  bool get isPicked => pickedAt != null;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    id: j['id'] as int? ?? 0,
    productId: (j['product_id'] is int)
        ? (j['product_id'] as int)
        : int.tryParse(j['product_id']?.toString() ?? '0') ?? 0,
    qty: j['qty'] as int? ?? 0,
    price: j['price']?.toString() ?? '0',
    total: j['total']?.toString() ?? '0',
    product: ProductInfo.fromJson((j['product'] as Map?)?.cast<String, dynamic>() ?? {}),
    pickedAt: j['picked_at'] == null
        ? null
        : DateTime.tryParse(j['picked_at'].toString()),
  );

  OrderItem copyWith({
    int? qty,
    String? total,
    DateTime? pickedAt,
    bool clearPickedAt = false,
  }) =>
      OrderItem(
        id: id,
        productId: productId,
        qty: qty ?? this.qty,
        price: price,
        total: total ?? this.total,
        product: product,
        pickedAt: clearPickedAt ? null : (pickedAt ?? this.pickedAt),
      );
}

class ProductInfo {
  final String? name;
  final String? sku;
  final String? imageUrl;
  final bool inStock;
  final bool onSale;

  ProductInfo({
    required this.name,
    required this.sku,
    required this.imageUrl,
    required this.inStock,
    required this.onSale,
  });

  factory ProductInfo.fromJson(Map<String, dynamic> j) => ProductInfo(
    name: j['name'] as String?,
    sku: j['sku'] as String?,
    imageUrl: j['image_url'] as String?,
    inStock: j['in_stock'] as bool? ?? false,
    onSale: j['on_sale'] as bool? ?? false,
  );
}

class NewOrderItem {
  final int id;
  final String status;
  final String? createdGmt;
  final String? createdLocal;
  final int storeId;
  final String? storeName;

  NewOrderItem({
    required this.id,
    required this.status,
    this.createdGmt,
    this.createdLocal,
    required this.storeId,
    this.storeName,
  });

  factory NewOrderItem.fromJson(Map<String, dynamic> j) => NewOrderItem(
    id: j['id'] as int? ?? 0,
    status: j['status'] as String? ?? '',
    createdGmt: j['created_gmt'] as String?,
    createdLocal: j['created_local'] as String?,
    storeId: j['store_id'] as int? ?? 0,
    storeName: j['store_name'] as String?,
  );
}

class NewOrdersResponse {
  final bool hasNew;
  final int storeId;
  final String sinceUsed; // ISO8601 UTC (Z)
  final int count;
  final List<NewOrderItem> orders;

  NewOrdersResponse({
    required this.hasNew,
    required this.storeId,
    required this.sinceUsed,
    required this.count,
    required this.orders,
  });

  factory NewOrdersResponse.fromJson(Map<String, dynamic> j) => NewOrdersResponse(
    hasNew: j['has_new'] as bool? ?? false,
    storeId: j['store_id'] as int? ?? 0,
    sinceUsed: j['since_used'] as String? ?? '',
    count: j['count'] as int? ?? 0,
    orders: ((j['orders'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map(NewOrderItem.fromJson)
        .toList(),
  );
}

class SimpleActionResponse {
  final bool success;
  final String message;

  SimpleActionResponse({required this.success, required this.message});

  factory SimpleActionResponse.fromJson(Map<String, dynamic> j) => SimpleActionResponse(
    success: j['success'] as bool? ?? false,
    message: j['message'] as String? ?? '',
  );
}


class OrderStatusDto {
  final int id;
  final String statusName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  OrderStatusDto({
    required this.id,
    required this.statusName,
    required this.createdAt,
    this.updatedAt,
  });

  factory OrderStatusDto.fromJson(Map<String, dynamic> j) => OrderStatusDto(
    id: j['id'] as int? ?? 0,
    statusName: j['status_name'] as String? ?? '',
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? ''),
  );
}

class OrderStatusesResponse {
  final List<OrderStatusDto> items;

  OrderStatusesResponse({required this.items});

  factory OrderStatusesResponse.fromJson(Map<String, dynamic> j) => OrderStatusesResponse(
    items: ((j['items'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map(OrderStatusDto.fromJson)
        .toList(),
  );
}

const Map<String, String> kOrderStatusRu = {
  'pending-payment': 'Ожидает оплату',
  'paid': 'Оплачен',
  'processing': 'В обработке',
  'ready-for-delivery': 'Готов к доставке',
  'delivering': 'В пути',
  // NOTE: no 'delivered' — the backend OrderStatus enum has no such
  // status (the flow goes delivering -> completed). It was a phantom
  // key the two apps disagreed on.
  'completed': 'Завершён',
  'canceled': 'Отменён',
  'refunded': 'Полный возврат',
  'partially-refunded': 'Частичный возврат',
  'payment-failed': 'Карта отклонена',
  // Customer opened the bank 3DS page but never finished — the bank
  // never confirmed and never declined. No money captured. Distinct
  // from 'Карта отклонена' (active decline) and 'Отменён' (deliberate
  // cancellation) so managers know "customer wandered off mid-payment".
  'payment-timeout': 'Оплата не завершена',
  // Off-hours parked order. Customer already paid; awaits manager
  // Release in the Запланированные tab to enter the picking flow.
  'scheduled': 'Запланирован на утро',
};

/// Status labels that read WRONG on a самовывоз order.
///
/// Mirrors `PICKUP_STATUS_RU_MAP` in order-service
/// `app/domain/fulfillment_presentation.py`. Keep the two in step: the customer
/// is told «Готов к выдаче» by the push, so a manager reading «Готов к доставке»
/// on the same order is reading a different sentence about the same thing.
///
/// `delivering` is unreachable for pickup under the backend transition policy.
/// It is listed anyway so that if some other door ever parks a pickup order
/// there, the manager sees that it is WRONG rather than «В пути», which reads
/// as a courier calmly doing their job.
const Map<String, String> kPickupStatusRu = {
  'ready-for-delivery': 'Готов к выдаче',
  'completed': 'Выдан',
  'delivering': 'Ошибка: курьер на самовывозе',
};

/// RU label for a status.
///
/// The default argument keeps every existing call site byte-identical. The
/// dashboard aggregate and the status-filter sheet talk about statuses in the
/// abstract, with no order in hand, and must keep saying «Готов к доставке».
String orderStatusRu(String code, {String fulfillmentType = 'delivery'}) {
  if (fulfillmentType == 'pickup') {
    final override = kPickupStatusRu[code];
    if (override != null) return override;
  }
  return kOrderStatusRu[code] ?? code;
}

/// Valid admin status transitions, mirrored from the backend
/// `StatusMachine.ADMIN_ALLOWED` (order-service status_machine.py).
/// The status dropdown filters to these so an admin can't pick an
/// invalid transition (e.g. completed -> pending-payment) and get a
/// silent backend rejection.
///
/// Refund targets ('refunded', 'partially-refunded') are intentionally
/// NOT listed here. Refunds can ONLY be applied through the refund
/// modal (_openRefundSheet → writes order_refunds row + moves money via
/// payment-service). Letting the admin pick "Частичный возврат" from
/// this dropdown changed only the status — no money moved, no refund
/// row recorded — and trapped the order in a terminal-looking state.
/// Caught 2026-05-20 during Kiril's live order test.
///
/// 'partially-refunded' allows forward progress so the admin can still
/// fulfill the remaining (non-refunded) items of the order.
const Map<String, Set<String>> kAdminAllowedTransitions = {
  'pending-payment': {'paid', 'payment-failed', 'canceled'},
  'paid': {'processing', 'canceled'},
  'processing': {'ready-for-delivery', 'canceled'},
  'ready-for-delivery': {'delivering'},
  'delivering': {'completed'},
  'completed': {},
  'payment-failed': {'canceled'},
  'payment-timeout': {'canceled'},
  'canceled': {},
  'partially-refunded': {'processing', 'ready-for-delivery', 'delivering', 'completed'},
  'refunded': {},
  // Release a scheduled order: manager picks "Оплачен" → backend fires
  // the normal PAID push to customer + picking flow starts. Cancel is
  // also allowed in case customer rings to back out overnight.
  'scheduled': {'paid', 'canceled'},
};

/// Transitions REMOVED for a given fulfillment type.
///
/// Mirrors `FULFILLMENT_TRANSITION_DENY` in order-service
/// `app/domain/fulfillment_policy.py`. If these two ever disagree, the manager
/// gets a dropdown option the backend answers with a 409, which reads to them
/// as "the app is broken".
const Map<String, Map<String, Set<String>>> kFulfillmentTransitionDeny = {
  'delivery': {},
  'pickup': {
    'ready-for-delivery': {'delivering'},
    'partially-refunded': {'delivering'},
  },
};

/// Transitions ADDED for a given fulfillment type.
///
/// Mirrors `FULFILLMENT_TRANSITION_ALLOW`. Pickup collapses
/// `ready-for-delivery -> delivering -> completed` into
/// `ready-for-delivery -> completed`, because for самовывоз the handover IS the
/// completion. There is no courier leg to represent.
const Map<String, Map<String, Set<String>>> kFulfillmentTransitionAllow = {
  'delivery': {},
  'pickup': {
    'ready-for-delivery': {'completed'},
  },
};

/// The transitions this order may actually take, `(base - deny) | allow`.
///
/// WHY THIS EXISTS AT ALL, AND WHY IT IS URGENT
/// Before this, the map above was fulfillment-blind and offered exactly one
/// forward move at `ready-for-delivery`: «В пути». On a самовывоз order the
/// backend now refuses that transition, and `completed` was never offered — so
/// a manager holding a bag the customer had already collected had NO legal
/// button. The only thing that still worked was «Отменить», which refunds the
/// full remaining amount and releases the stock: a full refund handed to
/// someone who already walked out with the goods.
///
/// For 'delivery' both masks are empty, so this reduces to
/// `kAdminAllowedTransitions[status]` by set algebra. That is the safety
/// argument, and a test pins it across the whole status cross-product.
Set<String> adminAllowedTransitions(
  String status, {
  String fulfillmentType = 'delivery',
}) {
  final key = status.toLowerCase().trim();
  final base = kAdminAllowedTransitions[key];
  // Unknown status denies everything, including the ALLOW half. Otherwise a
  // typo'd status would come back with `{'completed'}` for pickup and offer a
  // manager a transition the backend has never heard of.
  if (base == null) return const <String>{};

  // Anything that is not exactly 'pickup' is a courier delivery. Never guess
  // pickup: a wrongly-pickup order loses its courier controls and is simply
  // never delivered, which is silent. A wrongly-delivery order books a courier,
  // which is visible and refundable.
  final fulfillment = fulfillmentType.toLowerCase().trim() == 'pickup'
      ? 'pickup'
      : 'delivery';

  final deny = kFulfillmentTransitionDeny[fulfillment]?[key] ?? const <String>{};
  final allow = kFulfillmentTransitionAllow[fulfillment]?[key] ?? const <String>{};
  return {...base.where((t) => !deny.contains(t)), ...allow};
}


class OrderEvent {
  final int id;
  final String? fromStatus;
  final String toStatus;
  final String? fromStatusDisplay;
  final String toStatusDisplay;
  final int changedBy;
  final String? comment;
  final DateTime createdAt;

  OrderEvent({
    required this.id,
    required this.fromStatus,
    required this.toStatus,
    required this.fromStatusDisplay,
    required this.toStatusDisplay,
    required this.changedBy,
    required this.comment,
    required this.createdAt,
  });

  factory OrderEvent.fromJson(Map<String, dynamic> j) => OrderEvent(
        id: j['id'] as int? ?? 0,
        fromStatus: (j['from_status'] as String?)?.trim(),
        toStatus: (j['to_status'] as String? ?? '').trim(),
        fromStatusDisplay: (j['from_status_display'] as String?)?.trim(),
        toStatusDisplay: (j['to_status_display'] as String? ?? '').trim(),
        changedBy: j['changed_by'] as int? ?? 0,
        comment: (j['comment'] as String?)?.trim(),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class OrderItemEditResult {
  final bool ok;
  final int orderId;
  final int itemId;
  final int? newQty;
  final double newTotal;
  final double subtotal;
  final double deliverySum;
  // Authoritative discounted order total from the backend. Use this, not
  // subtotal + deliverySum — that re-derivation dropped the promo
  // discount and inflated the displayed order total after an edit.
  final double totalAmount;
  final bool removed;

  OrderItemEditResult({
    required this.ok,
    required this.orderId,
    required this.itemId,
    required this.newQty,
    required this.newTotal,
    required this.subtotal,
    required this.deliverySum,
    required this.totalAmount,
    required this.removed,
  });

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory OrderItemEditResult.fromJson(Map<String, dynamic> j) =>
      OrderItemEditResult(
        ok: j['ok'] as bool? ?? false,
        orderId: j['order_id'] as int? ?? 0,
        itemId: j['item_id'] as int? ?? 0,
        newQty: j['new_qty'] as int?,
        newTotal: _toDouble(j['new_total']),
        subtotal: _toDouble(j['subtotal']),
        deliverySum: _toDouble(j['delivery_sum']),
        totalAmount: _toDouble(j['total_amount']),
        removed: j['removed'] as bool? ?? false,
      );
}

class PackagingEditResult {
  final bool ok;
  final int orderId;
  final int bigBagCount;
  final int mediumBagCount;
  final double packagingSum;
  final double totalAmount;

  PackagingEditResult({
    required this.ok,
    required this.orderId,
    required this.bigBagCount,
    required this.mediumBagCount,
    required this.packagingSum,
    required this.totalAmount,
  });

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory PackagingEditResult.fromJson(Map<String, dynamic> j) =>
      PackagingEditResult(
        ok: j['ok'] as bool? ?? false,
        orderId: j['order_id'] as int? ?? 0,
        bigBagCount: j['big_bag_count'] as int? ?? 0,
        mediumBagCount: j['medium_bag_count'] as int? ?? 0,
        packagingSum: _toDouble(j['packaging_sum']),
        totalAmount: _toDouble(j['total_amount']),
      );
}

class SalesByDayRow {
  final DateTime date;
  final int orderCount;
  final double revenue;

  SalesByDayRow({
    required this.date,
    required this.orderCount,
    required this.revenue,
  });

  factory SalesByDayRow.fromJson(Map<String, dynamic> j) {
    final raw = j['date']?.toString() ?? '';
    return SalesByDayRow(
      date: DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0),
      orderCount: j['order_count'] as int? ?? 0,
      revenue: (j['revenue'] is num)
          ? (j['revenue'] as num).toDouble()
          : double.tryParse(j['revenue']?.toString() ?? '') ?? 0.0,
    );
  }
}

class SalesByDayResponse {
  final int storeId;
  final List<SalesByDayRow> rows;

  SalesByDayResponse({required this.storeId, required this.rows});

  factory SalesByDayResponse.fromJson(Map<String, dynamic> j) =>
      SalesByDayResponse(
        storeId: j['store_id'] as int? ?? 0,
        rows: ((j['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => SalesByDayRow.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}

class TopProductRow {
  final int productId;
  final int qty;
  final double revenue;
  final String name;
  final String? sku;
  final String? imageUrl;

  TopProductRow({
    required this.productId,
    required this.qty,
    required this.revenue,
    required this.name,
    this.sku,
    this.imageUrl,
  });

  factory TopProductRow.fromJson(Map<String, dynamic> j) => TopProductRow(
        productId: j['product_id'] as int? ?? 0,
        qty: j['qty'] as int? ?? 0,
        revenue: (j['revenue'] is num)
            ? (j['revenue'] as num).toDouble()
            : double.tryParse(j['revenue']?.toString() ?? '') ?? 0.0,
        name: (j['name'] as String?)?.trim().isNotEmpty == true
            ? j['name'] as String
            : 'Товар #${j['product_id']}',
        sku: j['sku'] as String?,
        imageUrl: j['image_url'] as String?,
      );
}

class TopProductsResponse {
  final int storeId;
  final List<TopProductRow> rows;

  TopProductsResponse({required this.storeId, required this.rows});

  factory TopProductsResponse.fromJson(Map<String, dynamic> j) =>
      TopProductsResponse(
        storeId: j['store_id'] as int? ?? 0,
        rows: ((j['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => TopProductRow.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}

class ReviewItem {
  final int id;
  final int orderId;
  final int customerId;
  final int storeId;
  final int rating;
  final String? comment;
  final List<String> photoUrls;
  final String? replyText;
  final String? replyTag;
  final DateTime? repliedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  ReviewItem({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.storeId,
    required this.rating,
    this.comment,
    this.photoUrls = const [],
    this.replyText,
    this.replyTag,
    this.repliedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAnswered => (replyText ?? '').trim().isNotEmpty;

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        id: j['id'] as int? ?? 0,
        orderId: j['order_id'] as int? ?? 0,
        customerId: j['customer_id'] as int? ?? 0,
        storeId: j['store_id'] as int? ?? 0,
        rating: j['rating'] as int? ?? 0,
        comment: j['comment'] as String?,
        photoUrls: ((j['photo_urls'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList(),
        replyText: j['reply_text'] as String?,
        replyTag: j['reply_tag'] as String?,
        repliedAt: DateTime.tryParse(j['replied_at']?.toString() ?? ''),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class ReviewsListResponse {
  final List<ReviewItem> items;
  final bool hasMore;

  ReviewsListResponse({required this.items, required this.hasMore});

  factory ReviewsListResponse.fromJson(Map<String, dynamic> j) =>
      ReviewsListResponse(
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => ReviewItem.fromJson(m.cast<String, dynamic>()))
            .toList(),
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ReviewStats {
  final int storeId;
  final int count;
  final double average;
  // {1: n, 2: n, ...5: n}
  final Map<int, int> distribution;

  ReviewStats({
    required this.storeId,
    required this.count,
    required this.average,
    required this.distribution,
  });

  factory ReviewStats.fromJson(Map<String, dynamic> j) {
    final raw = (j['distribution'] as Map?) ?? const {};
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    raw.forEach((k, v) {
      final star = int.tryParse(k.toString());
      if (star != null && star >= 1 && star <= 5) {
        dist[star] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
      }
    });
    return ReviewStats(
      storeId: j['store_id'] as int? ?? 0,
      count: j['count'] as int? ?? 0,
      average: (j['average'] is num)
          ? (j['average'] as num).toDouble()
          : double.tryParse(j['average']?.toString() ?? '') ?? 0.0,
      distribution: dist,
    );
  }
}

class OrderItemPickedResult {
  final int orderId;
  final int itemId;
  final DateTime? pickedAt;
  final int pickedCount;
  final int totalCount;

  OrderItemPickedResult({
    required this.orderId,
    required this.itemId,
    required this.pickedAt,
    required this.pickedCount,
    required this.totalCount,
  });

  factory OrderItemPickedResult.fromJson(Map<String, dynamic> j) =>
      OrderItemPickedResult(
        orderId: j['order_id'] as int? ?? 0,
        itemId: j['item_id'] as int? ?? 0,
        pickedAt: j['picked_at'] == null
            ? null
            : DateTime.tryParse(j['picked_at'].toString()),
        pickedCount: j['picked_count'] as int? ?? 0,
        totalCount: j['total_count'] as int? ?? 0,
      );
}

class OrderEventsResponse {
  final int orderId;
  final List<OrderEvent> events;

  OrderEventsResponse({required this.orderId, required this.events});

  factory OrderEventsResponse.fromJson(Map<String, dynamic> j) =>
      OrderEventsResponse(
        orderId: j['order_id'] as int? ?? 0,
        events: ((j['events'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(OrderEvent.fromJson)
            .toList(),
      );
}

class CustomerInfo {
  final int id;
  final String phone;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String role;
  final String onesignalUserId;

  CustomerInfo({
    required this.id,
    required this.phone,
    this.email,
    this.firstName,
    this.lastName,
    required this.role,
    required this.onesignalUserId,
  });

  String get fullName {
    final fn = (firstName ?? '').trim();
    final ln = (lastName ?? '').trim();
    final combined = ('$fn $ln').trim();
    return combined.isNotEmpty ? combined : '—';
  }

  factory CustomerInfo.fromJson(Map<String, dynamic> j) => CustomerInfo(
    id: j['id'] as int? ?? 0,
    phone: (j['phone'] as String? ?? '').trim(),
    email: (j['email'] as String?)?.trim(),
    firstName: (j['first_name'] as String?)?.trim(),
    lastName: (j['last_name'] as String?)?.trim(),
    role: (j['role'] as String? ?? '').trim(),
    onesignalUserId: (j['onesignal_user_id'] as String? ?? '').trim(),
  );
}

/// One refund row from /admin/orders/{id}/refunds — append-only history
/// of every refund applied to an order.
class RefundHistoryEntry {
  final int id;
  final double amount;
  final String reason;
  final int? createdBy; // admin/manager user id, nullable for legacy rows
  final DateTime createdAt;

  const RefundHistoryEntry({
    required this.id,
    required this.amount,
    required this.reason,
    required this.createdBy,
    required this.createdAt,
  });

  factory RefundHistoryEntry.fromJson(Map<String, dynamic> j) =>
      RefundHistoryEntry(
        // Guarded parse — every other model in this file defends these;
        // this one didn't. A legacy refund row with a null amount or odd
        // created_at threw inside getRefundHistory(), and because the
        // throw was swallowed the refund history silently never appeared
        // even when refunds existed (a money-audit surface).
        id: (j['id'] as num?)?.toInt() ?? 0,
        amount: (j['amount'] as num?)?.toDouble() ?? 0.0,
        reason: (j['reason'] as String? ?? '').trim(),
        createdBy: (j['created_by'] as num?)?.toInt(),
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '') ??
                DateTime.now(),
      );
}

