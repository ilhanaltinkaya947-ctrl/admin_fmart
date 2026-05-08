import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../orders/models/order_models.dart' show CustomerInfo, OrdersPage;
import '../data/customers_repository.dart';

part 'customer_detail_state.dart';

class CustomerDetailCubit extends Cubit<CustomerDetailState> {
  final CustomersRepository repository;

  CustomerDetailCubit({required this.repository}) : super(CustomerDetailInitial());

  Future<void> load({required int customerId, required int storeId}) async {
    emit(CustomerDetailLoading());
    try {
      final results = await Future.wait([
        repository.getCustomerById(customerId),
        repository.getOrdersForCustomer(
          customerId: customerId,
          storeId: storeId,
          page: 1,
          perPage: 50,
        ),
      ]);

      emit(CustomerDetailLoaded(
        customer: results[0] as CustomerInfo,
        orders: results[1] as OrdersPage,
      ));
    } catch (_) {
      emit(CustomerDetailFailure(message: 'Не удалось загрузить клиента'));
    }
  }
}
