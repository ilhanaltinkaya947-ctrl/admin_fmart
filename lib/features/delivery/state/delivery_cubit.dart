import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/cupertino.dart';
import 'package:uuid/uuid.dart';

import '../data/delivery_repository.dart';
import '../models/delivery_models.dart';

part 'delivery_state.dart';

class DeliveryCubit extends Cubit<DeliveryState> {
  final DeliveryRepository repo;
  final Uuid _uuid = const Uuid();

  DeliveryCubit({required this.repo}) : super(const DeliveryIdle());

  /// Wipe in-memory state on logout so the next admin doesn't see the
  /// previous user's pending delivery claim view.
  void reset() {
    emit(const DeliveryIdle());
  }

  // String newRequestId() => _uuid.v4();

  final _rng = Random.secure();

  int newRequestId() {
    final ms = DateTime.now().millisecondsSinceEpoch;

    final rand20 = _rng.nextInt(1 << 20);

    return (ms << 20) | rand20;
  }

  Future<void> initByOrder(int orderId) async {
    emit(const DeliveryLoading());
    try {
      final claim = await repo.getClaimByOrder(orderId);
      final info = await repo.claimInfo(claim.claimId);
      emit(DeliveryReady(
        orderId: orderId,
        claimId: claim.claimId,
        status: info.status,
        version: info.version,
        price: info.price,
        currency: info.currency,
        courierLink: null,
      ));
    } catch (_) {
      emit(DeliveryNoClaim(orderId: orderId));
    }
  }

  Future<void> calculate(CalculateDeliveryRequestDto dto) async {
    emit(const DeliveryLoading());
    try {
      final calc = await repo.calculate(dto);
      emit(DeliveryTariffs(orderId: dto.orderId ?? 0, calc: calc));
    } catch (e) {
      emit(const DeliveryError('Не удалось рассчитать доставку'));
    }
  }

  Future<void> create(CreateClaimRequestDto dto) async {
    emit(const DeliveryLoading());
    try {
      final created = await repo.createClaim(dto);
      final info = await repo.claimInfo(created.claimId);
      emit(DeliveryReady(
        orderId: dto.orderId,
        claimId: created.claimId,
        status: info.status,
        version: info.version,
        price: info.price,
        currency: info.currency,
        courierLink: null,
      ));
    } catch (e) {
      emit(const DeliveryError('Не удалось создать заявку'));
    }
  }

  Future<void> refresh(String claimId, int orderId) async {
    emit(const DeliveryLoading());
    try {
      final info = await repo.claimInfo(claimId);
      emit(DeliveryReady(
        orderId: orderId,
        claimId: claimId,
        status: info.status,
        version: info.version,
        price: info.price,
        currency: info.currency,
        courierLink: null,
      ));
    } catch (_) {
      emit(const DeliveryError('Не удалось обновить статус'));
    }
  }

  Future<void> accept(String claimId, int version, int orderId) async {
    emit(const DeliveryLoading());
    try {
      await repo.accept(claimId, version);
      await refresh(claimId, orderId);
    } catch (_) {
      emit(const DeliveryError('Не удалось принять заявку'));
    }
  }

  Future<void> cancelFlow(String claimId, int version, int orderId) async {
    emit(const DeliveryLoading());
    try {
      final ci = await repo.cancelInfo(claimId);
      await repo.cancel(claimId, version, ci.cancelState);
      await refresh(claimId, orderId);
    } catch (_) {
      emit(const DeliveryError('Не удалось отменить заявку'));
    }
  }

  Future<void> loadCourierLink(int orderId, String claimId) async {
    final st = state;
    if (st is! DeliveryReady) return;

    try {
      final url = await repo.courierUrl(orderId);
      emit(st.copyWith(courierLink: url.link));
    } catch (_) {
      // Surface as transient error then go back to the previous Ready state
      // so the operator sees feedback without losing the claim view.
      emit(const DeliveryError('Не удалось получить ссылку курьера'));
      emit(st);
    }
  }
}
