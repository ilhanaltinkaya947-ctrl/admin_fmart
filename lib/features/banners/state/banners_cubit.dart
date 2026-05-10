import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/banner_models.dart';
import '../data/banners_repository.dart';

sealed class BannersState {
  const BannersState();
}

class BannersInitial extends BannersState {
  const BannersInitial();
}

class BannersLoading extends BannersState {
  const BannersLoading();
}

class BannersLoaded extends BannersState {
  final List<BannerItem> items;
  const BannersLoaded(this.items);
}

class BannersFailure extends BannersState {
  final String message;
  const BannersFailure(this.message);
}

class BannersCubit extends Cubit<BannersState> {
  final BannersRepository repo;
  BannersCubit({required this.repo}) : super(const BannersInitial());

  Future<void> load() async {
    emit(const BannersLoading());
    try {
      final items = await repo.listAll();
      emit(BannersLoaded(items));
    } catch (e) {
      emit(BannersFailure('Не удалось загрузить баннеры'));
    }
  }

  Future<BannerItem?> create({
    required File imageFile,
    String? title,
    String? linkUrl,
    int sortOrder = 0,
    bool active = true,
  }) async {
    final created = await repo.create(
      imageFile: imageFile,
      title: title,
      linkUrl: linkUrl,
      sortOrder: sortOrder,
      active: active,
    );
    await load();
    return created;
  }

  Future<BannerItem?> update({
    required int id,
    File? imageFile,
    String? title,
    String? linkUrl,
    int? sortOrder,
    bool? active,
  }) async {
    final updated = await repo.update(
      id: id,
      imageFile: imageFile,
      title: title,
      linkUrl: linkUrl,
      sortOrder: sortOrder,
      active: active,
    );
    await load();
    return updated;
  }

  Future<void> remove(int id) async {
    await repo.delete(id);
    await load();
  }

  Future<void> reorder(List<int> orderedIds) async {
    final s = state;
    if (s is BannersLoaded) {
      final byId = {for (final b in s.items) b.id: b};
      final reordered = orderedIds.map((id) => byId[id]).whereType<BannerItem>().toList();
      emit(BannersLoaded(reordered));
    }
    try {
      await repo.reorder(orderedIds);
    } catch (_) {
      await load();
    }
  }
}
