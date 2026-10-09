/// Single source of truth for "is the new-order dialog currently open".
///
/// Two independent paths can trigger the dialog:
///   1. OneSignal foreground push handler (lib/app.dart)
///   2. OrderWatcher polling (lib/core/services/order_watcher.dart)
///
/// Without coordination, a push and a poll can fire within milliseconds
/// of each other and stack two `barrierDismissible:false` AlertDialogs
/// on top of each other — manager has to dismiss them one by one and
/// the underlying refresh logic runs twice.
///
/// Anyone about to show the dialog should:
///   if (newOrderDialogGuard.isShowing) return;
///   newOrderDialogGuard.markShowing();
///   try { await showDialog(...); } finally { newOrderDialogGuard.markClosed(); }
class NewOrderDialogGuard {
  bool _showing = false;

  bool get isShowing => _showing;

  /// Returns true if the caller now owns the dialog slot. False means
  /// another path is already showing it — caller should bail.
  bool tryAcquire() {
    if (_showing) return false;
    _showing = true;
    return true;
  }

  void release() {
    _showing = false;
  }

  // Orders a dialog has already been shown for, by EITHER path. The push
  // arrives when the order is created (pending payment, a few seconds before
  // it is paid), so without a shared memory the poll would alarm a second
  // time for the same order once it turns paid. Bounded like the watcher's
  // own list so a long shift cannot grow it.
  static const int _shownCap = 200;
  final List<int> _shown = <int>[];

  void markShown(int orderId) {
    if (_shown.contains(orderId)) return;
    _shown.add(orderId);
    if (_shown.length > _shownCap) {
      _shown.removeRange(0, _shown.length - _shownCap);
    }
  }

  bool wasShown(int orderId) => _shown.contains(orderId);

  /// Tests only: forget everything, the instance is a process-wide singleton.
  void resetForTest() {
    _showing = false;
    _shown.clear();
  }
}

final newOrderDialogGuard = NewOrderDialogGuard();
