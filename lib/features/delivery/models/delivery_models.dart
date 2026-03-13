class CargoItemDto {
  final int productId;
  final int qty;
  final double? weight;
  final double? length;
  final double? width;
  final double? height;

  CargoItemDto({
    required this.productId,
    required this.qty,
    this.weight,
    this.length,
    this.width,
    this.height,
  });

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'qty': qty,
    if (weight != null) 'weight': weight,
    if (length != null) 'length': length,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
  };
}

class RoutePointDto {
  final String type; // source|destination
  final List<double> coordinates; // [lon,lat]
  final String fullAddress;

  final int? floor;
  final String? porch;
  final String? apartment;
  final String? doorCode;

  RoutePointDto({
    required this.type,
    required this.coordinates,
    required this.fullAddress,
    this.floor,
    this.porch,
    this.apartment,
    this.doorCode,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'coordinates': coordinates,
    'full_address': fullAddress,
    if (floor != null) 'floor': floor,
    if (porch != null) 'porch': porch,
    if (apartment != null) 'apartment': apartment,
    if (doorCode != null) 'door_code': doorCode,
  };
}

class CalculateDeliveryRequestDto {
  final int? orderId;
  final int storeId;
  final double totalAmount;
  final List<CargoItemDto> items;
  final List<RoutePointDto> routePoints;

  CalculateDeliveryRequestDto({
    required this.orderId,
    required this.storeId,
    required this.totalAmount,
    required this.items,
    required this.routePoints,
  });

  Map<String, dynamic> toJson() => {
    'order_id': orderId,
    'store_id': storeId,
    'total_amount': totalAmount,
    'items': items.map((e) => e.toJson()).toList(),
    'route_points': routePoints.map((e) => e.toJson()).toList(),
  };
}

class TariffQuoteDto {
  final String tariffCode;
  final String title;
  final bool enabled;
  final String currency;
  final double price;

  TariffQuoteDto({
    required this.tariffCode,
    required this.title,
    required this.enabled,
    required this.currency,
    required this.price,
  });

  factory TariffQuoteDto.fromJson(Map<String, dynamic> j) => TariffQuoteDto(
    tariffCode: j['tariff_code'] as String,
    title: (j['title'] as String?) ?? '',
    enabled: (j['enabled'] as bool?) ?? false,
    currency: (j['currency'] as String?) ?? 'KZT',
    price: (j['price'] as num).toDouble(),
  );
}

class CalculateDeliveryResponseDto {
  final int? orderId;
  final int storeId;
  final double totalAmount;
  final List<TariffQuoteDto> quotes;

  CalculateDeliveryResponseDto({
    required this.orderId,
    required this.storeId,
    required this.totalAmount,
    required this.quotes,
  });

  factory CalculateDeliveryResponseDto.fromJson(Map<String, dynamic> j) => CalculateDeliveryResponseDto(
    orderId: j['order_id'] as int?,
    storeId: j['store_id'] as int,
    totalAmount: (j['total_amount'] as num).toDouble(),
    quotes: ((j['quotes'] as List?) ?? [])
        .map((e) => TariffQuoteDto.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

class CreateClaimRequestDto {
  final int orderId;
  final int storeId;
  final double totalAmount;

  final String requestId;
  final String tariffCode;

  final List<CargoItemDto> items;
  final List<RoutePointDto> routePoints;

  final String userPhone;
  final String? contactName;

  CreateClaimRequestDto({
    required this.orderId,
    required this.storeId,
    required this.totalAmount,
    required this.requestId,
    required this.tariffCode,
    required this.items,
    required this.routePoints,
    required this.userPhone,
    required this.contactName,
  });

  Map<String, dynamic> toJson() => {
    'order_id': orderId,
    'store_id': storeId,
    'total_amount': totalAmount,
    'request_id': requestId,
    'tariff_code': tariffCode,
    'items': items.map((e) => e.toJson()).toList(),
    'route_points': routePoints.map((e) => e.toJson()).toList(),
    'user_phone': userPhone,
    'contact_name': contactName,
  };
}

class CreateClaimResponseDto {
  final int orderId;
  final String claimId;
  final String status;
  final int version;
  final String provider;
  final String tariffCode;
  final double price;
  final String currency;

  CreateClaimResponseDto({
    required this.orderId,
    required this.claimId,
    required this.status,
    required this.version,
    required this.provider,
    required this.tariffCode,
    required this.price,
    required this.currency,
  });

  factory CreateClaimResponseDto.fromJson(Map<String, dynamic> j) => CreateClaimResponseDto(
    orderId: j['order_id'] as int,
    claimId: j['claim_id'] as String,
    status: (j['status'] as String?) ?? '',
    version: (j['version'] as int?) ?? 0,
    provider: (j['provider'] as String?) ?? 'yandex',
    tariffCode: (j['tariff_code'] as String?) ?? '',
    price: (j['price'] as num).toDouble(),
    currency: (j['currency'] as String?) ?? 'KZT',
  );
}

class GetClaimsResponseDto {
  final int orderId;
  final String claimId;

  GetClaimsResponseDto({required this.orderId, required this.claimId});

  factory GetClaimsResponseDto.fromJson(Map<String, dynamic> j) => GetClaimsResponseDto(
    orderId: j['order_id'] as int,
    claimId: j['claim_id'] as String,
  );
}

class ClaimInfoResponseDto {
  final String claimId;
  final int orderId;
  final String status;
  final int version;
  final double price;
  final String currency;

  ClaimInfoResponseDto({
    required this.claimId,
    required this.orderId,
    required this.status,
    required this.version,
    required this.price,
    required this.currency,
  });

  factory ClaimInfoResponseDto.fromJson(Map<String, dynamic> j) => ClaimInfoResponseDto(
    claimId: j['claim_id'] as String,
    orderId: j['order_id'] as int,
    status: (j['status'] as String?) ?? '',
    version: (j['version'] as int?) ?? 0,
    price: (j['price'] as num).toDouble(),
    currency: (j['currency'] as String?) ?? 'KZT',
  );
}

class CancelInfoResponseDto {
  final String claimId;
  final String cancelState; // free|paid

  CancelInfoResponseDto({required this.claimId, required this.cancelState});

  factory CancelInfoResponseDto.fromJson(Map<String, dynamic> j) => CancelInfoResponseDto(
    claimId: j['claim_id'] as String,
    cancelState: (j['cancel_state'] as String?) ?? 'free',
  );
}

class CourierUrlDto {
  final String claimId;
  final String? link;

  CourierUrlDto({required this.claimId, required this.link});

  factory CourierUrlDto.fromJson(Map<String, dynamic> j) => CourierUrlDto(
    claimId: j['claim_id'] as String,
    link: j['link'] as String?,
  );
}
