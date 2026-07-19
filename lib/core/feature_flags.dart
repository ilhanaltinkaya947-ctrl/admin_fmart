import 'package:flutter/foundation.dart';

/// Per-user feature toggles from the backend (`GET /gw/order/app/features`,
/// env-driven). Staged rollout: a feature is Kiril-only now and flips on for
/// every manager via a backend env change — no new admin build.
///
/// Defaults ALL-OFF so a gated feature stays hidden until the backend confirms
/// it for this staff member. Populated once on the home shell mount.
class AdminFeatureFlags {
  AdminFeatureFlags._();
  static final AdminFeatureFlags instance = AdminFeatureFlags._();

  final ValueNotifier<Map<String, bool>> flags =
      ValueNotifier<Map<String, bool>>(const {});

  bool isOn(String key) => flags.value[key] == true;
  bool get reviewReply => isOn('review_reply');
  bool get substitution => isOn('substitution');

  void set(Map<String, bool> value) => flags.value = value;
}
