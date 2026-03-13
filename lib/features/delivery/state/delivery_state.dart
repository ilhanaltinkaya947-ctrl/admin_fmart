part of 'delivery_cubit.dart';

sealed class DeliveryState extends Equatable {
  const DeliveryState();
  @override
  List<Object?> get props => [];
}

class DeliveryIdle extends DeliveryState {
  const DeliveryIdle();
}

class DeliveryLoading extends DeliveryState {
  const DeliveryLoading();
}

class DeliveryNoClaim extends DeliveryState {
  final int orderId;
  const DeliveryNoClaim({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class DeliveryTariffs extends DeliveryState {
  final int orderId;
  final CalculateDeliveryResponseDto calc;
  const DeliveryTariffs({required this.orderId, required this.calc});
  @override
  List<Object?> get props => [orderId, calc];
}

class DeliveryReady extends DeliveryState {
  final int orderId;
  final String claimId;
  final String status;
  final int version;
  final double price;
  final String currency;
  final String? courierLink;

  const DeliveryReady({
    required this.orderId,
    required this.claimId,
    required this.status,
    required this.version,
    required this.price,
    required this.currency,
    required this.courierLink,
  });

  DeliveryReady copyWith({String? courierLink}) => DeliveryReady(
    orderId: orderId,
    claimId: claimId,
    status: status,
    version: version,
    price: price,
    currency: currency,
    courierLink: courierLink ?? this.courierLink,
  );

  @override
  List<Object?> get props => [orderId, claimId, status, version, price, currency, courierLink];
}

class DeliveryError extends DeliveryState {
  final String message;
  const DeliveryError(this.message);
  @override
  List<Object?> get props => [message];
}
