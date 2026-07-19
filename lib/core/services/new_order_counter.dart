import 'package:flutter/foundation.dart';

/// Tracks the number of new-order pushes that arrived since the operator
/// last visited the "Новые" tab.
///
/// app.dart increments it from the OneSignal foreground handler; the
/// home shell reads it via [ValueListenableBuilder] to paint a Badge on
/// the "Новые" nav entry, and calls [reset] when the operator opens
/// that tab so the badge clears.
///
/// Lives outside any cubit/repo because it's UI-presentation glue, not
/// domain state — and because we want the same instance shared between
/// app.dart (the writer) and home_shell.dart (the reader) without
/// threading a cubit through unrelated providers.
///
/// It *composes* a [ValueNotifier] rather than extending one so the
/// shared instance can be handed through a plain (repository) Provider
/// without tripping Provider's debug `debugCheckInvalidValueType`
/// assertion (which rejects any Listenable given to a non-listening
/// provider). Reactivity is still exposed via [listenable] for
/// [ValueListenableBuilder].
class NewOrderCounter {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  /// Listen to this for badge reactivity (used by the home shell).
  ValueListenable<int> get listenable => _notifier;

  int get value => _notifier.value;

  void bump() => _notifier.value = _notifier.value + 1;
  void reset() {
    if (_notifier.value != 0) _notifier.value = 0;
  }

  void dispose() => _notifier.dispose();
}
