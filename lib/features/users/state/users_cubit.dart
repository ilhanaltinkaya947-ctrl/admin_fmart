import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../orders/models/order_models.dart' show Pagination;
import '../data/users_repository.dart';
import '../models/user_models.dart';

part 'users_state.dart';

class UsersCubit extends Cubit<UsersState> {
  final UsersRepository repository;
  UsersCubit({required this.repository}) : super(UsersInitial());

  String _query = '';
  final int _perPage = 20;
  bool _loading = false;
  Timer? _debounce;

  Future<void> ensureLoaded() async {
    if (state is UsersLoaded) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    emit(UsersLoading());
    try {
      final data = await repository.list(
        page: 1,
        perPage: _perPage,
        q: _query,
      );
      emit(UsersLoaded(items: data.items, pagination: data.pagination));
    } catch (_) {
      emit(UsersFailure(message: 'Не удалось загрузить пользователей'));
    } finally {
      _loading = false;
    }
  }

  void setQuery(String q) {
    _query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), refresh);
  }

  Future<void> loadMore() async {
    final st = state;
    if (st is! UsersLoaded) return;
    if (!st.pagination.hasNext) return;
    if (_loading) return;
    _loading = true;
    try {
      final next = st.pagination.page + 1;
      final data = await repository.list(
        page: next,
        perPage: _perPage,
        q: _query,
      );
      emit(UsersLoaded(
        items: [...st.items, ...data.items],
        pagination: data.pagination,
      ));
    } catch (_) {
      // silent
    } finally {
      _loading = false;
    }
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
