import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_errors.dart';
import '../data/promo_models.dart';
import '../data/promo_repository.dart';

sealed class PromosState {
  const PromosState();
}

class PromosInitial extends PromosState {
  const PromosInitial();
}

class PromosLoading extends PromosState {
  const PromosLoading();
}

class PromosLoaded extends PromosState {
  final List<AdminPromo> items;
  final List<String> types;

  /// Set when a WRITE failed but the list itself is fine.
  ///
  /// A rejected toggle must not replace the screen with an error page — the
  /// manager's codes are still right there and still actionable. So the error
  /// rides along with the loaded list and the PAGE shows it as a snackbar.
  /// Emitting [PromosFailure] here would swap the whole list for an error box,
  /// which over-reacts to one refused request.
  final String? writeError;

  const PromosLoaded(this.items, this.types, {this.writeError});

  PromosLoaded copyWith({List<AdminPromo>? items, List<String>? types, String? writeError}) =>
      PromosLoaded(items ?? this.items, types ?? this.types, writeError: writeError);
}

class PromosFailure extends PromosState {
  final String message;
  const PromosFailure(this.message);
}

class PromosCubit extends Cubit<PromosState> {
  final PromoRepository repo;
  PromosCubit({required this.repo}) : super(const PromosInitial());

  /// Wipe on logout — promo codes are admin-only, so the next manager signing
  /// in must not briefly see the previous admin's list.
  void reset() => emit(const PromosInitial());

  /// Total order: live first, then by code. The endpoint returns newest-first
  /// by id, which buries an active campaign under a freshly created test code.
  static int compare(AdminPromo a, AdminPromo b) {
    final byState = a.state.index.compareTo(b.state.index);
    return byState != 0 ? byState : a.code.compareTo(b.code);
  }

  Future<void> load() async {
    emit(const PromosLoading());
    try {
      // Both reads are independent; a types failure must not blank the list,
      // and a list failure must not hide the picker. Fetch the list first
      // because it is what the screen is for.
      final items = await repo.list();
      List<String> types;
      try {
        types = await repo.types();
      } catch (_) {
        types = const [];
      }
      final ordered = [...items]..sort(compare);
      emit(PromosLoaded(ordered, types));
    } catch (e) {
      emit(PromosFailure(describeApiError(e, subject: 'промокоды')));
    }
  }

  Future<AdminPromo?> create({
    required String code,
    required String promoType,
    bool enabled = true,
    DateTime? expiresAt,
  }) async {
    final created = await repo.create(
      code: code,
      promoType: promoType,
      enabled: enabled,
      expiresAt: expiresAt,
    );
    await load();
    return created;
  }

  /// Toggle / re-schedule a code.
  ///
  /// Errors are SURFACED, not swallowed: a toggle that silently fails leaves
  /// the switch in the new position and the manager believing a code is off
  /// while customers can still redeem it. This is the same defect that made
  /// `reorder()` on the Баннеры screen lie about saving.
  Future<void> update(
    String code, {
    bool? enabled,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) async {
    final s = state;
    if (s is PromosLoaded) {
      // Optimistic flip so the switch responds immediately to the tap.
      final optimistic = s.items
          .map((p) => p.code == code
              ? AdminPromo(
                  id: p.id,
                  code: p.code,
                  promoType: p.promoType,
                  enabled: enabled ?? p.enabled,
                  expiresAt: clearExpiry ? null : (expiresAt ?? p.expiresAt),
                  createdAt: p.createdAt,
                  updatedAt: p.updatedAt,
                  redemptions: p.redemptions,
                  committed: p.committed,
                  reserved: p.reserved,
                  released: p.released,
                  customers: p.customers,
                )
              : p)
          .toList()
        ..sort(compare);
      emit(PromosLoaded(optimistic, s.types));
    }

    try {
      await repo.update(
        code,
        enabled: enabled,
        expiresAt: expiresAt,
        clearExpiry: clearExpiry,
      );
      await load();
    } on Exception catch (e) {
      if (isClosed) return;
      // Reload FIRST so the list shows what the server actually holds (the
      // optimistic flip above is a guess), THEN attach the error to the
      // loaded state. Emitting the error first was the original bug: `load()`
      // emits Loading then Loaded, so the error was overwritten within the
      // same call and the switch reverted with no explanation.
      //
      // And the error rides on PromosLoaded rather than replacing it, because
      // one refused request must not swap the manager's whole list for an
      // error box. The page renders writeError as a snackbar.
      await load();
      if (isClosed) return;
      final after = state;
      if (after is PromosLoaded) {
        emit(after.copyWith(writeError: describeApiError(e, subject: 'промокод')));
      } else {
        emit(PromosFailure(describeApiError(e, subject: 'промокод')));
      }
    }
  }
}
