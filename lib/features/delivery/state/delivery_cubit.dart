import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/cupertino.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_errors.dart';
import '../data/delivery_repository.dart';
import '../models/delivery_models.dart';

part 'delivery_state.dart';

class DeliveryCubit extends Cubit<DeliveryState> {
  final DeliveryRepository repo;
  final Uuid _uuid = const Uuid();

  DeliveryCubit({required this.repo}) : super(const DeliveryIdle());

  /// Wipe in-memory state on logout so the next admin doesn't see the
  /// previous user's pending delivery claim view.
  /// Every state change goes through here.
  ///
  /// This cubit used to be app-wide and immortal, so a bare `emit` was safe.
  /// `PickupStrayClaimPanel` now creates a ROUTE-SCOPED instance, which is
  /// closed the moment the manager taps back — while `initByOrder`'s two
  /// sequential GETs may still be in flight. The late `emit` then throws
  /// StateError out of an un-awaited Future: not a crash, but Sentry noise
  /// that looks like a real fault.
  ///
  /// A helper rather than 22 hand-written guards, because the one that gets
  /// forgotten is the one that fires.
  void _safeEmit(DeliveryState state) {
    if (isClosed) return;
    emit(state);
  }

  void reset() {
    _safeEmit(const DeliveryIdle());
  }

  // String newRequestId() => _uuid.v4();

  final _rng = Random.secure();

  int newRequestId() {
    final ms = DateTime.now().millisecondsSinceEpoch;

    final rand20 = _rng.nextInt(1 << 20);

    return (ms << 20) | rand20;
  }

  Future<void> initByOrder(int orderId) async {
    _safeEmit(const DeliveryLoading());
    try {
      final claim = await repo.getClaimByOrder(orderId);
      final info = await repo.claimInfo(claim.claimId);
      _safeEmit(DeliveryReady(
        orderId: orderId,
        claimId: claim.claimId,
        status: info.status,
        version: info.version,
        price: info.price,
        currency: info.currency,
        courierLink: null,
      ));
    } on DioException catch (e) {
      // ONLY a genuine 404 means "no claim exists yet" → show the create
      // form. A timeout / 5xx / connection error must NOT fall through
      // to DeliveryNoClaim — that showed the create-claim form for an
      // order that may ALREADY have a Yandex claim, inviting the admin
      // to create a duplicate.
      if (e.response?.statusCode == 404) {
        _safeEmit(DeliveryNoClaim(orderId: orderId));
      } else {
        _safeEmit(const DeliveryError(
            'Не удалось загрузить заявку на доставку. Проверьте соединение.'));
      }
    } catch (_) {
      _safeEmit(const DeliveryError(
          'Не удалось загрузить заявку на доставку. Проверьте соединение.'));
    }
  }

  Future<void> calculate(CalculateDeliveryRequestDto dto) async {
    _safeEmit(const DeliveryLoading());
    try {
      final calc = await repo.calculate(dto);
      _safeEmit(DeliveryTariffs(orderId: dto.orderId ?? 0, calc: calc));
    } catch (e) {
      _safeEmit(const DeliveryError('Не удалось рассчитать доставку'));
    }
  }

  Future<void> create(CreateClaimRequestDto dto) async {
    _safeEmit(const DeliveryLoading());
    try {
      final created = await repo.createClaim(dto);
      final info = await repo.claimInfo(created.claimId);
      _safeEmit(DeliveryReady(
        orderId: dto.orderId,
        claimId: created.claimId,
        status: info.status,
        version: info.version,
        price: info.price,
        currency: info.currency,
        courierLink: null,
      ));
    } catch (e) {
      // Show the backend's own reason when it sent one. delivery-service
      // refuses a dispatch for an order that isn't deliverable with a 409
      // «Нельзя вызвать курьера: заказ не готов к доставке» — the order was
      // never paid, or it's still parked off-hours waiting to be released.
      // Folding that into the flat message below told the manager only that
      // "something failed", so the natural response was to tap again, which
      // can never succeed. Falls back to the generic message for transport
      // failures and for internal English details.
      _safeEmit(DeliveryError(backendDetail(e) ?? 'Не удалось создать заявку'));
    }
  }

  Future<void> refresh(String claimId, int orderId) async {
    _safeEmit(const DeliveryLoading());
    try {
      final info = await repo.claimInfo(claimId);
      _safeEmit(DeliveryReady(
        orderId: orderId,
        claimId: claimId,
        status: info.status,
        version: info.version,
        price: info.price,
        currency: info.currency,
        courierLink: null,
      ));
    } catch (_) {
      _safeEmit(const DeliveryError('Не удалось обновить статус'));
    }
  }

  Future<void> accept(String claimId, int version, int orderId) async {
    _safeEmit(const DeliveryLoading());
    try {
      await repo.accept(claimId, version);
      await refresh(claimId, orderId);
    } catch (_) {
      _safeEmit(const DeliveryError('Не удалось принять заявку'));
    }
  }

  Future<void> cancelFlow(String claimId, int version, int orderId) async {
    _safeEmit(const DeliveryLoading());
    try {
      final ci = await repo.cancelInfo(claimId);
      await repo.cancel(claimId, version, ci.cancelState);
      await refresh(claimId, orderId);
    } catch (_) {
      _safeEmit(const DeliveryError('Не удалось отменить заявку'));
    }
  }

  Future<void> loadCourierLink(int orderId, String claimId) async {
    final st = state;
    if (st is! DeliveryReady) return;

    try {
      final url = await repo.courierUrl(orderId);
      _safeEmit(st.copyWith(courierLink: url.link));
    } catch (_) {
      // Surface as transient error then go back to the previous Ready state
      // so the operator sees feedback without losing the claim view.
      _safeEmit(const DeliveryError('Не удалось получить ссылку курьера'));
      _safeEmit(st);
    }
  }
}
