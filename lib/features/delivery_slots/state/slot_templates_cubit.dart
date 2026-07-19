import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_errors.dart';
import '../data/delivery_slots_repository.dart';
import '../data/template_models.dart';

sealed class SlotTemplatesState {
  const SlotTemplatesState();
}

class SlotTemplatesInitial extends SlotTemplatesState {
  const SlotTemplatesInitial();
}

class SlotTemplatesLoading extends SlotTemplatesState {
  final int storeId;
  const SlotTemplatesLoading(this.storeId);
}

class SlotTemplatesLoaded extends SlotTemplatesState {
  final int storeId;
  final List<DeliverySlotTemplate> items;
  const SlotTemplatesLoaded(this.storeId, this.items);
}

class SlotTemplatesFailure extends SlotTemplatesState {
  final int storeId;
  final String message;
  const SlotTemplatesFailure(this.storeId, this.message);
}

class SlotTemplatesCubit extends Cubit<SlotTemplatesState> {
  final DeliverySlotsRepository repo;
  SlotTemplatesCubit({required this.repo}) : super(const SlotTemplatesInitial());

  void reset() => emit(const SlotTemplatesInitial());

  Future<void> load(int storeId) async {
    emit(SlotTemplatesLoading(storeId));
    try {
      final items = await repo.listTemplates(storeId: storeId);
      emit(SlotTemplatesLoaded(storeId, items));
    } catch (e) {
      emit(SlotTemplatesFailure(
        storeId,
        describeApiError(e, subject: 'слоты доставки'),
      ));
    }
  }

  Future<DeliverySlotTemplate?> create(TemplateDraft draft) async {
    final created = await repo.create(draft);
    await load(draft.storeId);
    return created;
  }

  Future<DeliverySlotTemplate?> update(int id, TemplatePatch patch, int storeId) async {
    final updated = await repo.update(id, patch);
    await load(storeId);
    return updated;
  }

  Future<void> remove(int id, int storeId) async {
    await repo.delete(id);
    await load(storeId);
  }
}
