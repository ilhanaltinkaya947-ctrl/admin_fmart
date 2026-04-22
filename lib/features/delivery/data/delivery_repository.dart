import '../../../core/api/api_client.dart';
import '../../../core/api/safe_response.dart';
import '../models/delivery_models.dart';

class DeliveryRepository {
  final ApiClient api;
  final String prefix;

  DeliveryRepository({required this.api, this.prefix = '/gw/delivery'});

  Future<CalculateDeliveryResponseDto> calculate(CalculateDeliveryRequestDto dto) async {
    final r = await api.dio.post('$prefix/calculate', data: dto.toJson());
    return CalculateDeliveryResponseDto.fromJson(asJsonMap(r.data));
  }

  Future<GetClaimsResponseDto> getClaimByOrder(int orderId) async {
    final r = await api.dio.get('$prefix/$orderId/claim');
    return GetClaimsResponseDto.fromJson(asJsonMap(r.data));
  }

  Future<CreateClaimResponseDto> createClaim(CreateClaimRequestDto dto) async {
    final r = await api.dio.post('$prefix/claims/create', data: dto.toJson());
    // print(dto);
    return CreateClaimResponseDto.fromJson(asJsonMap(r.data));
  }

  Future<ClaimInfoResponseDto> claimInfo(String claimId) async {
    final r = await api.dio.get('$prefix/claims/$claimId/info');
    return ClaimInfoResponseDto.fromJson(asJsonMap(r.data));
  }

  Future<void> accept(String claimId, int version) async {
    await api.dio.post('$prefix/claims/$claimId/accept', data: {'version': version});
  }

  Future<CancelInfoResponseDto> cancelInfo(String claimId) async {
    final r = await api.dio.post('$prefix/claims/$claimId/cancel-info');
    return CancelInfoResponseDto.fromJson(asJsonMap(r.data));
  }

  Future<void> cancel(String claimId, int version, String cancelState) async {
    await api.dio.post('$prefix/claims/$claimId/cancel', data: {
      'version': version,
      'cancel_state': cancelState,
    });
  }

  Future<CourierUrlDto> courierUrl(int orderId) async {
    final r = await api.dio.get('$prefix/$orderId/courier/url');
    return CourierUrlDto.fromJson(asJsonMap(r.data));
  }
}
