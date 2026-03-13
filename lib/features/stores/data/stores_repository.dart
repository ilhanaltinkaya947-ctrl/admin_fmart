import '../../../core/api/api_client.dart';
import '../models/store_models.dart';

class StoresRepository {
  final ApiClient api;
  StoresRepository({required this.api});

  Future<List<StoreDto>> getStores() async {
    final resp = await api.dio.get('/gw/catalog/stores');
    final list = (resp.data as List).cast<Map<String, dynamic>>();
    return list.map(StoreDto.fromJson).toList();
  }
}
