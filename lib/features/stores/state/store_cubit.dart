import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/cupertino.dart';

import '../../../core/services/onesignal_service.dart';
import '../../../core/storage/prefs_storage.dart';
import '../data/stores_repository.dart';
import '../models/store_models.dart';

part 'store_state.dart';

class StoreCubit extends Cubit<StoreState> {
  final StoresRepository storesRepository;
  final PrefsStorage prefsStorage;
  final OneSignalService oneSignalService;

  StoreCubit({
    required this.storesRepository,
    required this.prefsStorage,
    required this.oneSignalService,
  }) : super(StoreNotSelected());

  Future<void> bootstrap() async {
    emit(StoreLoading());

    final saved = await prefsStorage.getSelectedStoreDto();
    debugPrint('[STORE] bootstrap saved=$saved');

    if (saved != null && saved.storeId != 0 && saved.coordinates.length >= 2) {
      await oneSignalService.setStoreTag(saved.storeId);

      emit(StoreSelected(
        storeId: saved.storeId,
        storeName: saved.storeName,
        storeAddress: saved.storeAddress,
        coordinates: saved.coordinates,
      ));
      return;
    }

    emit(StoreNotSelected());
  }

  Future<void> loadStores() async {
    emit(StoreLoading());
    try {
      final stores = await storesRepository.getStores();
      emit(StoreListLoaded(stores: stores));
    } catch (e) {
      emit(const StoreFailure(message: 'Не удалось загрузить магазины'));
    }
  }

  Future<void> selectStore(StoreDto store) async {
    await prefsStorage.setSelectedStoreDto(store);
    await oneSignalService.setStoreTag(store.storeId);

    emit(StoreSelected(
      storeId: store.storeId,
      storeName: store.storeName,
      storeAddress: store.storeAddress,
      coordinates: store.coordinates,
    ));
  }

  Future<void> clearStore() async {
    await prefsStorage.clearStore();
    emit(StoreNotSelected());
  }
}
