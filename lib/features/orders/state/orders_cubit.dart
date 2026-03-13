import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../data/orders_repository.dart';
import '../models/order_models.dart';

part 'orders_state.dart';

class OrdersCubit extends Cubit<OrdersState> {
  final OrdersRepository ordersRepository;

  OrdersCubit({required this.ordersRepository}) : super(OrdersInitial());

  int? _storeId;
  int _page = 1;
  final int _perPage = 20;
  bool _loading = false;

  Future<void> ensureLoaded({required int storeId}) async {
    if (_storeId == storeId && state is OrdersLoaded) return;
    await refresh(storeId: storeId);
  }

  Future<void> refresh({required int storeId}) async {
    if (_loading) return;
    _loading = true;

    emit(OrdersLoading());
    try {
      _storeId = storeId;
      _page = 1;
      final data = await ordersRepository.getOrders(storeId: storeId, page: _page, perPage: _perPage);
      emit(OrdersLoaded(items: data.items, pagination: data.pagination));
    } catch (e) {
      emit(OrdersFailure(message: 'Не удалось загрузить заказы'));
    } finally {
      _loading = false;
    }
  }

  Future<void> loadMore() async {
    final st = state;
    if (st is! OrdersLoaded) return;
    if (!st.pagination.hasNext) return;
    if (_storeId == null) return;
    if (_loading) return;

    _loading = true;
    try {
      final nextPage = st.pagination.page + 1;
      final data = await ordersRepository.getOrders(storeId: _storeId!, page: nextPage, perPage: _perPage);

      emit(OrdersLoaded(
        items: [...st.items, ...data.items],
        pagination: data.pagination,
      ));
    } catch (_) {
      // молча, чтобы не ломать UX
    } finally {
      _loading = false;
    }
  }

  void updateOrderInList(Order updated) {
    final st = state;
    if (st is! OrdersLoaded) return;

    final idx = st.items.indexWhere((o) => o.id == updated.id);
    if (idx == -1) return;

    final newList = [...st.items];
    newList[idx] = updated;
    emit(OrdersLoaded(items: newList, pagination: st.pagination));
  }
}
