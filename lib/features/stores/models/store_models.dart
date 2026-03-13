class StoreDto {
  final int storeId;
  final String storeName;
  final String storeAddress;
  final List<double> coordinates; // [lon,lat]

  StoreDto({
    required this.storeId,
    required this.storeName,
    required this.storeAddress,
    required this.coordinates,
  });

  static List<double> _toDoubleList(dynamic v) {
    if (v is List) {
      return v.map((e) {
        if (e is num) return e.toDouble();
        return double.tryParse(e.toString()) ?? 0.0;
      }).toList();
    }
    return <double>[];
  }

  factory StoreDto.fromJson(Map<String, dynamic> j) => StoreDto(
    storeId: (j['store_id'] as num?)?.toInt() ?? 0,
    storeName: j['store_name'] as String? ?? '',
    storeAddress: j['store_address'] as String? ?? '',
    coordinates: _toDoubleList(j['coordinates']),
  );

  Map<String, dynamic> toJson() => {
    'store_id': storeId,
    'store_name': storeName,
    'store_address': storeAddress,
    'coordinates': coordinates,
  };
}
