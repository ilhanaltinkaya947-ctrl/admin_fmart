import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_errors.dart';
import '../data/news_models.dart';
import '../data/news_repository.dart';

sealed class NewsState {
  const NewsState();
}

class NewsInitial extends NewsState {
  const NewsInitial();
}

class NewsLoading extends NewsState {
  const NewsLoading();
}

class NewsLoaded extends NewsState {
  final List<NewsPost> items;
  const NewsLoaded(this.items);
}

class NewsFailure extends NewsState {
  final String message;
  const NewsFailure(this.message);
}

class NewsCubit extends Cubit<NewsState> {
  final NewsRepository repo;
  NewsCubit({required this.repo}) : super(const NewsInitial());

  /// Admin-only data: cleared on logout like banners.
  void reset() => emit(const NewsInitial());

  Future<void> load() async {
    emit(const NewsLoading());
    try {
      final items = await repo.listAll();
      // Pinned first, then the date customers see, newest first.
      items.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        final byDate = b.publishedAt.compareTo(a.publishedAt);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
      emit(NewsLoaded(items));
    } catch (e) {
      emit(NewsFailure(describeApiError(e, subject: 'новости')));
    }
  }

  Future<void> remove(int id) async {
    await repo.delete(id);
    await load();
  }

  Future<void> setActive(NewsPost p, bool active) async {
    await repo.update(
      id: p.id,
      title: p.title,
      body: p.body ?? '',
      titleKk: p.titleKk ?? '',
      bodyKk: p.bodyKk ?? '',
      storeIds: p.storeIds,
      active: active,
      pinned: p.pinned,
    );
    await load();
  }
}
