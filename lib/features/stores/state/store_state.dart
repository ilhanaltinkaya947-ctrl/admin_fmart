part of 'store_cubit.dart';

sealed class StoreState extends Equatable {
  const StoreState();
  @override
  List<Object?> get props => [];
}

final class StoreLoading extends StoreState {}

final class StoreNotSelected extends StoreState {}

class StoreSelected extends StoreState {
  final int storeId;
  final String storeName;
  final String storeAddress;
  final List<double> coordinates; // [lon,lat]

  const StoreSelected({
    required this.storeId,
    required this.storeName,
    required this.storeAddress,
    required this.coordinates,
  });

  @override
  List<Object?> get props => [storeId, storeName, storeAddress, coordinates];
}

final class StoreListLoaded extends StoreState {
  final List<StoreDto> stores;
  const StoreListLoaded({required this.stores});

  @override
  List<Object?> get props => [stores];
}

final class StoreFailure extends StoreState {
  final String message;
  const StoreFailure({required this.message});

  @override
  List<Object?> get props => [message];
}
