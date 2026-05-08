import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../orders/models/order_models.dart' show Pagination;
import '../data/customers_repository.dart';
import '../models/customer_models.dart';

part 'customers_state.dart';

class CustomersCubit extends Cubit<CustomersState> {
  final CustomersRepository repository;

  CustomersCubit({required this.repository}) : super(CustomersInitial());

  String _query = '';
  final int _perPage = 20;
  bool _loading = false;
  Timer? _debounce;

  Future<void> ensureLoaded() async {
    if (state is CustomersLoaded) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    emit(CustomersLoading());
    try {
      final data = await repository.listCustomers(
        page: 1,
        perPage: _perPage,
        q: _query,
      );
      emit(CustomersLoaded(items: data.items, pagination: data.pagination));
    } catch (_) {
      emit(CustomersFailure(message: 'Не удалось загрузить клиентов'));
    } finally {
      _loading = false;
    }
  }

  void setQuery(String q) {
    _query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      refresh();
    });
  }

  Future<void> loadMore() async {
    final st = state;
    if (st is! CustomersLoaded) return;
    if (!st.pagination.hasNext) return;
    if (_loading) return;

    _loading = true;
    try {
      final nextPage = st.pagination.page + 1;
      final data = await repository.listCustomers(
        page: nextPage,
        perPage: _perPage,
        q: _query,
      );
      emit(CustomersLoaded(
        items: [...st.items, ...data.items],
        pagination: data.pagination,
      ));
    } catch (_) {
      // silent — keep current list
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
