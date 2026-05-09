class OrdersPage {
  final Pagination pagination;
  final List<Order> items;

  OrdersPage({required this.pagination, required this.items});

  factory OrdersPage.fromJson(Map<String, dynamic> j) {
    return OrdersPage(
      pagination: Pagination.fromJson((j['pagination'] as Map).cast<String, dynamic>()),
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
  final String customerComment;
  final String paymentMethod;
  final bool isPromo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<OrderItem> items;

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
    required this.customerComment,
    required this.paymentMethod,
    required this.isPromo,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

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
    customerComment: j['customer_comment'] as String? ?? '',
    paymentMethod: j['payment_method'] as String? ?? '',
    isPromo: j['is_promo'] as bool? ?? false,
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? '') ?? DateTime.now(),
    items: ((j['items'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map(OrderItem.fromJson)
        .toList(),
  );

  Order copyWith({String? status}) => Order(
    id: id,
    customerId: customerId,
    status: status ?? this.status,
    totalAmount: totalAmount,
    deliverySum: deliverySum,
    shippingLat: shippingLat,
    shippingLng: shippingLng,
    storeId: storeId,
    storeName: storeName,
    deliveryAddress: deliveryAddress,
    customerComment: customerComment,
    paymentMethod: paymentMethod,
    isPromo: isPromo,
    createdAt: createdAt,
    updatedAt: updatedAt,
    items: items,
  );
}



class OrderItem {
  final int productId;
  final int qty;
  final String price;
  final String total;
  final ProductInfo product;

  OrderItem({
    required this.productId,
    required this.qty,
    required this.price,
    required this.total,
    required this.product,
  });

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    productId: (j['product_id'] is int)
        ? (j['product_id'] as int)
        : int.tryParse(j['product_id']?.toString() ?? '0') ?? 0,
    qty: j['qty'] as int? ?? 0,
    price: j['price']?.toString() ?? '0',
    total: j['total']?.toString() ?? '0',
    product: ProductInfo.fromJson((j['product'] as Map?)?.cast<String, dynamic>() ?? {}),
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
  'delivered': 'Доставлен',
  'completed': 'Завершён',
  'canceled': 'Отменён',
  'refunded': 'Полный возврат',
  'partially-refunded': 'Частичный возврат',
  'payment-failed': 'Ошибка',
};

String orderStatusRu(String code) => kOrderStatusRu[code] ?? code;


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

