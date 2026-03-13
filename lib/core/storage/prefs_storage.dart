import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/stores/models/store_models.dart';

class PrefsStorage {
  static const _kStoreId = 'selected_store_id';
  static const _kStoreName = 'selected_store_name';

  static const _kSelectedStore = 'selected_store_v2'; // json
  static const _kSelectedStoreId = 'selected_store_id'; // опционально, если где-то используется

  Future<void> setSelectedStoreDto(StoreDto store) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSelectedStore, jsonEncode(store.toJson()));
    await sp.setInt(_kSelectedStoreId, store.storeId);
  }

  Future<StoreDto?> getSelectedStoreDto() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kSelectedStore);
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return StoreDto.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<int?> getSelectedStoreId() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_kSelectedStoreId);
  }

  Future<void> clearStore() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kSelectedStore);
    await sp.remove(_kSelectedStoreId);
    await sp.remove(_kStoreName);
    await sp.remove(_kStoreId);

  }


  Future<String?> getSelectedStoreName() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kStoreName);
  }

  Future<void> setSelectedStore({required int storeId, required String storeName}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kStoreId, storeId);
    await sp.setString(_kStoreName, storeName);
  }

}
