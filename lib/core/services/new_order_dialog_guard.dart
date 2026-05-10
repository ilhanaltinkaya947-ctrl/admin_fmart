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
}

final newOrderDialogGuard = NewOrderDialogGuard();
