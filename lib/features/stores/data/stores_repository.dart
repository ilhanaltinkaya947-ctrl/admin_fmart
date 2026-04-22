import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import '../models/store_models.dart';

class StoresRepository {
  final ApiClient api;
  StoresRepository({required this.api});

  Future<List<StoreDto>> getStores() async {
    final resp = await api.dio.get('/gw/catalog/stores');
    return asJsonList(resp.data).map(StoreDto.fromJson).toList();
  }
}
