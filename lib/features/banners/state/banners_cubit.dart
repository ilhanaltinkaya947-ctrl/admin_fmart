import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_errors.dart';
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

  /// Wipe in-memory state on logout — banners are admin-only, so the
  /// next manager (or anyone signing in non-admin) shouldn't briefly
  /// see the previous admin's loaded list.
  void reset() {
    emit(const BannersInitial());
  }

  Future<void> load() async {
    emit(const BannersLoading());
    try {
      final items = await repo.listAll();
      // Sort defensively. The admin endpoint has no ORDER BY of its own for
      // this set, and prod holds duplicated sort_order values, so the raw
      // order can vary between loads — tiles would shuffle, and a drag would
      // be computed against an order the server does not use. Mirrors the
      // server's own `sort_order ASC, id ASC`.
      final ordered = [...items]..sort(BannersRepository.compare);
      emit(BannersLoaded(ordered));
    } catch (e) {
      emit(BannersFailure(describeApiError(e, subject: 'баннеры')));
    }
  }

  Future<BannerItem?> create({
    required File imageFile,
    String? title,
    String? linkUrl,
    int? sortOrder,
    bool active = true,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final created = await repo.create(
      imageFile: imageFile,
      title: title,
      linkUrl: linkUrl,
      sortOrder: sortOrder,
      active: active,
      startsAt: startsAt,
      endsAt: endsAt,
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
    DateTime? startsAt,
    bool? clearStartsAt,
    DateTime? endsAt,
    bool? clearEndsAt,
  }) async {
    final updated = await repo.update(
      id: id,
      imageFile: imageFile,
      title: title,
      linkUrl: linkUrl,
      sortOrder: sortOrder,
      active: active,
      startsAt: startsAt,
      clearStartsAt: clearStartsAt,
      endsAt: endsAt,
      clearEndsAt: clearEndsAt,
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
    } on Exception catch (e) {
      // Every other method in the repository maps validation failures to
      // BannerValidationException, but reorder() was the one call with no
      // catch here — so a rejection escaped as an unhandled async error and
      // the optimistic emit above stayed on screen as if it had saved. The
      // failure was invisible; the list just lied. Surface it and reload so
      // the tiles snap back to what the server actually holds.
      if (isClosed) return;
      emit(BannersFailure(describeApiError(e, subject: 'порядок баннеров')));
      await load();
    }
  }
}
