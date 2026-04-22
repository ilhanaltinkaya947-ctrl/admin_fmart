Map<String, dynamic> asJsonMap(dynamic data) {
  if (data is Map) return data.cast<String, dynamic>();
  throw FormatException('Expected JSON object, got ${data.runtimeType}: ${data.toString().substring(0, 200.clamp(0, data.toString().length))}');
}

List<Map<String, dynamic>> asJsonList(dynamic data) {
  if (data is List) return data.cast<Map<String, dynamic>>();
  throw FormatException('Expected JSON array, got ${data.runtimeType}');
}
