import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/feature_flags.dart';
import '../../../core/format/address.dart';
import '../../../core/format/money.dart';
import '../../delivery/models/delivery_models.dart';
import '../data/orders_repository.dart';
import '../models/refundable.dart';
import 'substitution_sheets.dart';
import '_sub_tokens.dart';
import '../models/order_models.dart';
import '../../stores/state/store_cubit.dart';
import '../../delivery/presentation/delivery_section.dart';
import 'widgets/order_item_card.dart';
import 'widgets/order_timeline_section.dart';

class OrderDetailsPage extends StatefulWidget {
  final Order order;
  const OrderDetailsPage({super.key, required this.order});

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage>
    with WidgetsBindingObserver {
  late Order _order;

  final _reasonCtrl = TextEditingController();

  bool _saving = false;
  bool _actionLoading = false;
  bool _refundSheetOpen = false;
  String? _error;

  List<OrderStatusDto> _statuses = [];
  bool _statusesLoading = false;
  String? _selectedStatus;

  CustomerInfo? _customer;
  bool _customerLoading = false;
  bool _customerLoadFailed = false;

  final Set<int> _itemBusy = <int>{};

  // Tracks which items have an in-flight mark-picked toggle so the
  // checkbox spins instead of double-firing on a second tap.
  final Set<int> _pickBusy = <int>{};

  final _timelineKey = GlobalKey<OrderTimelineSectionState>();

  // Refund history — populated only when the order has ever been refunded.
  // Refetched after every refund the admin applies via _openRefundSheet.
  List<RefundHistoryEntry> _refunds = const [];
  bool _refundsLoading = false;

  // Live polling of the order while the detail page is open. Picks up
  // server-side status changes (courier flips to "delivering", payment
  // webhook resolves, etc.) so the admin doesn't see stale state and
  // call support thinking the order is stuck. Cancelled in dispose().
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 8);

  bool get _orderEverRefunded {
    final s = _order.status.toLowerCase();
    return s == 'refunded' || s == 'partially-refunded';
  }

  // Cancel makes sense pre-fulfillment only. Hide on terminal states +
  // post-pickup states (delivering, completed, refunded, canceled,
  // payment-failed). 'pending-payment' allows cancel (admin cancels
  // unpaid hold); 'paid'/'processing'/'ready-for-delivery' allow cancel.
  bool get _canCancel {
    return const {'pending-payment', 'paid', 'processing', 'ready-for-delivery'}
        .contains(_order.status.toLowerCase());
  }

  // Refund needs money to refund: only after payment landed and before
  // fully refunded. partially-refunded still allows further refund up
  // to the remaining amount (backend will reject over-refund).
  bool get _canRefund {
    return const {
      'paid',
      'processing',
      'ready-for-delivery',
      'delivering',
      'completed',
      'partially-refunded',
    }.contains(_order.status.toLowerCase());
  }

  bool get _itemsEditable {
    final s = _order.status.toLowerCase();
    return s == 'paid' || s == 'processing';
  }

  // Dispatching / re-dispatching a Yandex courier makes no sense once the
  // order is money-dead — a canceled/refunded/payment-failed/timed-out order
  // has no delivery to make. Hide the create + "Заново вызвать курьера"
  // controls (a manager could otherwise pay for a courier to deliver a
  // canceled order). partially-refunded stays deliverable (remaining items).
  bool get _deliveryUnavailable {
    return const {'canceled', 'refunded', 'payment-failed', 'payment-timeout'}
        .contains(_order.status.toLowerCase());
  }

  // In-flight cancel-substitution toggles, keyed by order_item id.
  final Set<int> _subBusy = <int>{};

  // True while the substitute picker sheet is open — pauses the 8s poll so
  // _order (and the price the sheet shows a refund against) can't shift out
  // from under the manager mid-compose.
  bool _substituteSheetOpen = false;

  /// Force-refetch the order now (after a substitution propose/cancel) so the
  /// item chips reflect the new state without waiting for the 8s poll.
  Future<void> _refetchOrderNow() async {
    if (!mounted) return;
    try {
      final repo = context.read<OrdersRepository>();
      final fresh = await repo.getOrderById(
          storeId: _order.storeId, orderId: _order.id);
      if (fresh != null && mounted) setState(() => _order = fresh);
    } catch (_) {/* the 8s poll will catch up */}
  }

  Future<void> _openSubstitutePicker(OrderItem it) async {
    final repo = context.read<OrdersRepository>();
    _substituteSheetOpen = true;
    final outcome = await showSubstitutePickerSheet(
        context, repo: repo, order: _order, item: it);
    _substituteSheetOpen = false;
    if (!mounted) return;
    if (outcome == SubstituteSheetOutcome.proposed) {
      await _refetchOrderNow();
      if (mounted) {
        // Branded confirmation — a green check-disc + white copy on ST.green,
        // consistent with the retoned studio (not the bare grey default).
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: ST.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ST.rMd)),
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Замена предложена — покупатель получит уведомление',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ));
      }
    } else if (outcome == SubstituteSheetOutcome.removeItemRequested) {
      await _removeItem(it);
    }
  }

  Future<void> _cancelSubstitution(int subId, int itemId) async {
    if (_subBusy.contains(itemId)) return;
    // Retracting a live customer-facing proposal is irreversible — confirm.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отменить замену?'),
        content: const Text(
            'Покупатель больше не увидит это предложение. Товар останется в заказе.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Назад')),
          TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Отменить замену')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _subBusy.add(itemId));
    try {
      final repo = context.read<OrdersRepository>();
      await repo.cancelSubstitution(orderId: _order.id, subId: subId);
      await _refetchOrderNow();
    } on OrdersApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось отменить замену')));
      }
    } finally {
      if (mounted) setState(() => _subBusy.remove(itemId));
    }
  }

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    // Start with nothing selected — the order's CURRENT status is never a
    // valid transition target (the backend rejects self-loops), so the
    // admin must explicitly pick a real next status.
    _selectedStatus = null;
    _loadStatuses();
    _loadCustomer();
    if (_orderEverRefunded) _loadRefunds();
    WidgetsBinding.instance.addObserver(this);
    // Rebuild when feature flags land so the gated «Заменить» (substitution)
    // action appears as soon as the async /features fetch resolves, even if
    // this page was opened before it returned. Also keeps the action reactive
    // for the no-rebuild backend env flip that opens substitution to all
    // managers. (The button itself is gated inside substitution_sheets.dart;
    // rebuilding this page re-evaluates that child.)
    AdminFeatureFlags.instance.flags.addListener(_onFlagsChanged);
    _startPolling();
  }

  void _onFlagsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background-firing every 8s while the iPad is locked drains
    // battery + cellular for no benefit (the operator can't see the
    // screen). Pause polling on background, resume + one-shot refresh
    // on foreground so the screen catches up instantly.
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_pollTimer == null && mounted) {
        _startPolling();
        // Immediate catch-up so the operator doesn't stare at stale
        // state for up to 8s after unlocking.
        _pollOrder();
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOrder());
  }

  /// Re-fetch the order from the server and merge any server-truth
  /// fields. Best-effort: any failure is swallowed so a flaky network
  /// never breaks the UI. Skipped while the operator is mid-mutation
  /// (status save, cancel, refund, item edit) so we don't fight their
  /// in-flight change.
  Future<void> _pollOrder() async {
    if (!mounted) return;
    if (_saving || _actionLoading || _itemBusy.isNotEmpty) return;
    if (_substituteSheetOpen) return; // don't shift _order under an open sheet

    final storeState = context.read<StoreCubit>().state;
    if (storeState is! StoreSelected) return;

    try {
      final repo = context.read<OrdersRepository>();
      final fresh = await repo.getOrderById(
        storeId: storeState.storeId,
        orderId: _order.id,
      );
      if (fresh == null || !mounted) return;

      final statusChanged = fresh.status != _order.status;
      setState(() {
        _order = fresh;
        if (statusChanged) {
          // The status changed under us (e.g. a consumer-driven transition
          // landed during a poll). If the operator's pending dropdown
          // selection is no longer a valid transition from the NEW status,
          // clear it — otherwise DropdownButtonFormField(value: …) holds a
          // value absent from its items and asserts/renders blank.
          final allowed =
              kAdminAllowedTransitions[fresh.status.toLowerCase().trim()] ??
                  const <String>{};
          if (_selectedStatus != null && !allowed.contains(_selectedStatus)) {
            _selectedStatus = null;
          }
        }
      });
      if (statusChanged) {
        // Refresh the timeline so the new transition appears below. The
        // status badge at the top already reflects server truth.
        _timelineKey.currentState?.refresh();
      }
    } catch (_) {
      // Polling is best-effort. Operator can still pull-to-refresh
      // (badge) or back-out / re-enter to force a reload.
    }
  }

  Future<void> _loadRefunds() async {
    if (_refundsLoading) return;
    setState(() => _refundsLoading = true);
    try {
      final repo = context.read<OrdersRepository>();
      final list = await repo.getRefundHistory(orderId: _order.id);
      if (!mounted) return;
      setState(() => _refunds = list);
    } catch (_) {
      // Non-blocking — admin can still issue another refund; we just
      // skip showing history if the GET fails.
    } finally {
      if (mounted) setState(() => _refundsLoading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AdminFeatureFlags.instance.flags.removeListener(_onFlagsChanged);
    _pollTimer?.cancel();
    _pollTimer = null;
    _reasonCtrl.dispose();
    super.dispose();
  }

  double _parseMoney(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0.0;

  /// Copy [value] to the clipboard and toast the operator. No-op + toast
  /// when the value is empty so a long-press on '—' doesn't silently
  /// "succeed" with empty clipboard contents.
  void _copyToClipboard(String value, {required String label}) {
    final v = value.trim();
    if (v.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label пуст — нечего копировать')),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: v));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label скопирован')),
    );
  }

  Future<void> _loadCustomer() async {
    final cid = _order.customerId;
    if (cid <= 0) return;

    setState(() {
      _customerLoading = true;
      _customerLoadFailed = false;
    });
    try {
      final repo = context.read<OrdersRepository>();
      final info = await repo.getCustomerInfo(customerId: cid);

      if (!mounted) return;
      setState(() => _customer = info);
    } catch (_) {
      if (mounted) setState(() => _customerLoadFailed = true);
    } finally {
      if (mounted) setState(() => _customerLoading = false);
    }
  }

  Future<void> _loadStatuses() async {
    setState(() {
      _statusesLoading = true;
      _error = null;
    });

    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.getOrderStatuses();
      // Slow-network back-nav: the manager can dispose this page during the
      // await (Shymkent 3G, 1-3s). Guard before setState — matches every other
      // post-await handler in this file; without it this throws
      // "setState after dispose" (Sentry noise). (audit 2026-07-27)
      if (!mounted) return;

      final items = [...res.items]..sort((a, b) => a.id.compareTo(b.id));

      setState(() {
        _statuses = items;
        // Don't force-select anything — the dropdown filters to valid
        // transitions from the current order status, and the admin
        // picks one explicitly. If the previously-picked target is no
        // longer valid (status changed under us), clear it.
        final allowed =
            kAdminAllowedTransitions[_order.status.toLowerCase().trim()] ?? const <String>{};
        if (_selectedStatus != null &&
            !allowed.contains(_selectedStatus)) {
          _selectedStatus = null;
        }
      });
    } catch (_) {
      // Same slow-network back-nav guard as the success branch above — the
      // catch fires on a timeout/lost-response after the page is disposed;
      // without this it throws "setState after dispose". (audit 2026-07-27)
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить список статусов');
    } finally {
      if (mounted) setState(() => _statusesLoading = false);
    }
  }


  Future<void> _changeStatus() async {
    final status = (_selectedStatus ?? '').trim();
    if (status.isEmpty) {
      setState(() => _error = 'Выбери статус');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = context.read<OrdersRepository>();
      await repo.changeStatus(
        orderId: _order.id,
        status: status, // отправляем код
        reason: _reasonCtrl.text.trim(),
      );

      if (!mounted) return;
      // API-first / pessimistic update: only mutate local state AFTER
      // the network call succeeded. If it failed we'd be in the catch
      // block below with the old _order.status still intact, so admin
      // sees the actual server state instead of a phantom new one.
      setState(() {
        _order = _order.copyWith(status: status);
        // The status we just applied is now the CURRENT status, so it's
        // no longer a valid transition target — clear the selection.
        _selectedStatus = null;
      });
      _timelineKey.currentState?.refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Статус обновлён')),
      );
    } on OrdersApiException catch (e) {
      // Server-side reason surfaced via the typed exception — e.g.
      // "Address outside delivery zone" from the Yandex delivery proxy.
      // Show the actual message instead of swallowing it.
      if (!mounted) return;
      _showErrorWithRetry(e.message, _changeStatus);
    } catch (_) {
      if (!mounted) return;
      _showErrorWithRetry('Не удалось обновить статус', _changeStatus);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showErrorWithRetry(String message, Future<void> Function() onRetry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Повторить',
          textColor: Colors.white,
          onPressed: onRetry,
        ),
      ),
    );
  }

  Future<void> _cancelOrder() async {
    final repo = context.read<OrdersRepository>();
    final storeState = context.read<StoreCubit>().state;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: Text('Заказ #${_order.id} будет отменён.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Нет')),
          ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Отменить')),
        ],
      ),
    );

    if (confirm != true) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      final res = await repo.cancelOrder(orderId: _order.id);

      if (!mounted) return;
      if (res.success) {
        // Cancelling a PAID order now issues a REFUND server-side, so the order
        // becomes 'refunded' (not 'canceled'). Re-fetch the true status instead
        // of optimistically forcing 'canceled'. (2026-07-04)
        Order? fresh;
        if (storeState is StoreSelected) {
          // Best-effort: a re-fetch blip must NOT turn a successful cancel into
          // a failure. Fall back to the optimistic 'canceled' below.
          try {
            fresh = await repo.getOrderById(
              storeId: storeState.storeId,
              orderId: _order.id,
            );
          } catch (_) {
            fresh = null;
          }
        }
        if (!mounted) return;
        setState(() => _order = fresh ?? _order.copyWith(status: 'canceled'));
        _timelineKey.currentState?.refresh();
      }
      final isRefund = _order.status == 'refunded' ||
          _order.status == 'partially-refunded';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message.isNotEmpty
            ? res.message
            : (res.success
                ? (isRefund ? 'Оформлен возврат' : 'Заказ отменён')
                : 'Не удалось отменить'))),
      );
    } on OrdersApiException catch (e) {
      if (!mounted) return;
      _showErrorWithRetry(e.message, _cancelOrder);
    } catch (_) {
      if (!mounted) return;
      _showErrorWithRetry('Не удалось отменить заказ', _cancelOrder);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // True while a scheduled-order «Выпустить заказ» call is in flight — the
  // button shows a spinner and disables so a laggy double-tap can't fire two
  // releases. Separate from _actionLoading so it doesn't spin the
  // cancel/refund buttons.
  bool _releasing = false;

  Future<void> _releaseOrder() async {
    if (_releasing) return;
    final repo = context.read<OrdersRepository>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Выпустить заказ?'),
        content: Text(
            'Заказ #${_order.id} выйдет из режима ожидания и попадёт в сборку сейчас, не дожидаясь 09:00.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Нет')),
          ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Выпустить')),
        ],
      ),
    );

    if (confirm != true) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _releasing = true;
      _error = null;
    });

    try {
      final res = await repo.releaseOrder(orderId: _order.id);
      if (!mounted) return;
      if (res.success) {
        // Re-fetch the true post-release status (backend flips scheduled →
        // paid/processing) instead of guessing, so the badge + status form
        // reflect server truth and the scheduled label disappears.
        Order? fresh;
        try {
          fresh = await repo.getOrderById(
            storeId: _order.storeId,
            orderId: _order.id,
          );
        } catch (_) {
          fresh = null;
        }
        if (!mounted) return;
        // Prefer the re-fetched order (clears scheduled_for_at + gives the
        // true new status). If the re-fetch blipped, fall back to an
        // optimistic 'paid' — copyWith keeps scheduledForAt as the info
        // label, but the badge/status form already reflect the release.
        setState(() {
          _order = fresh ?? _order.copyWith(status: 'paid');
        });
        _timelineKey.currentState?.refresh();
        // Branded confirmation — matches the substitution snackbar tone.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: ST.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ST.rMd)),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  res.message.isNotEmpty
                      ? res.message
                      : 'Заказ выпущен — передан в сборку',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message.isNotEmpty
              ? res.message
              : 'Не удалось выпустить заказ')),
        );
      }
    } on OrdersApiException catch (e) {
      if (!mounted) return;
      _showErrorWithRetry(e.message, _releaseOrder);
    } catch (_) {
      if (!mounted) return;
      _showErrorWithRetry('Не удалось выпустить заказ', _releaseOrder);
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  Future<void> _openRefundSheet() async {
    // Synchronous re-entrancy guard: a double-tap on «Возврат» (laggy shared
    // iPad) must not stack two refund sheets — each would mint its OWN
    // sessionIdempotencyKey, so confirming both would apply two DISTINCT
    // refunds. Reset once the sheet closes (below).
    if (_refundSheetOpen || _actionLoading) return;
    setState(() => _refundSheetOpen = true);

    // The ceiling is what we CHARGED, not what the order is worth now.
    //
    // totalAmount is mutable: a substitution or an item edit runs
    // recalculate_order_totals on the backend and rewrites it, so on a
    // partially-refunded order it is ALREADY net of that refund. Subtracting
    // the refund history from it removes the same money twice — and the figure
    // below is both shown to the manager AND prefilled into the amount field,
    // so the short refund gets confirmed with nothing on screen to reveal it.
    // Measured in production: orders 392 and 424 were hand-refunded from this
    // screen and landed 20 ₸ and 55 ₸ light, each time by exactly the size of
    // the earlier substitution refund.
    //
    // capturedAmount is frozen at capture and never moves. Fall back to
    // totalAmount when the backend did not send it (older backend, or an order
    // captured before the column existed): that reproduces the previous
    // behaviour instead of offering no refund at all.
    // _refunds is the client-side refund history (loaded whenever the order was
    // ever refunded); summing its amounts gives what has already been returned.
    // The backend still enforces the true ceiling server-side (the dedupe +
    // over-refund guard, now judged against this same captured figure), so this
    // stays a UX guard, not the source of truth.
    final alreadyRefunded = _refunds.fold<double>(0.0, (s, r) => s + r.amount);

    // The rule itself lives in refundable.dart, pure and unit-tested against
    // the five production orders it got wrong. Money arithmetic buried in a
    // widget cannot be tested, and this one was wrong for months.
    final ceiling = refundCeiling(
      capturedAmount: _order.capturedAmount,
      totalAmount: _order.totalAmount,
      alreadyRefunded: alreadyRefunded,
    );
    final remaining = ceiling.remaining;
    // The header sum must be the SAME basis the remaining figure is measured
    // against, or the three numbers on screen do not reconcile: order 396 would
    // read «Сумма заказа 2785» / «Возвращено 2785» / «Осталось вернуть 230»,
    // which adds up to nothing a manager can check. On the captured basis it
    // reads 3015 / 2785 / 230 and the arithmetic is visible.
    final total = ceiling.basis;

    final amountCtrl =
        TextEditingController(text: remaining.toStringAsFixed(2));
    final reasonCtrl = TextEditingController();

    // Structured refund-reason picker. Free-text alone produced un-analyzable
    // garbage ("я", "1", "тест", 5 spellings of "нет в наличии"), so we can't
    // measure the real out-of-stock rate. A canonical dropdown writes one of a
    // fixed set of Russian labels into the SAME `reason` string the backend
    // already stores — no schema/endpoint change, fully backward-compatible
    // (old builds just keep sending free text). The free-text field below
    // becomes an OPTIONAL note appended after the canonical label.
    const refundReasons = <String>[
      'Нет в наличии',
      'Разница по весу',
      'Брак / качество товара',
      'Замена товара',
      'Жалоба клиента',
      'Отмена заказа',
      'Другое',
    ];
    final reasonCode = ValueNotifier<String?>(null);

    // ONE idempotency key for the entire modal session. Used by every
    // submit attempt from this sheet — including any retries the
    // operator triggers if they re-tap "Оформить" before the spinner
    // shows. The backend dedupes refunds by (order_id, idempotency_key),
    // so the second tap returns the first refund's result instead of
    // applying a duplicate. Closing + re-opening the sheet generates a
    // new key (that's a deliberate second refund intent).
    final sessionIdempotencyKey = const Uuid().v4();

    final result = await showModalBottomSheet<_RefundPayload>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,  // operator must explicitly close or confirm
      builder: (c) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(c).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Inline header with a close button — the sheet is set to
              // isDismissible:false (to prevent accidental tap-to-close
              // mid-confirm), so without this X the only exit is the
              // "Закрыть" button at the bottom. On iPhone with the
              // keyboard up that button falls below the visible area
              // and the operator has nothing to tap.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Возврат по заказу #${_order.id}',
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(c).pop(null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Сумма заказа: ${total.toStringAsFixed(2)} ₸',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
              // Only surface the refund-so-far / remaining lines when
              // something has already been returned — a fresh full-refund
              // order doesn't need the extra rows.
              if (alreadyRefunded > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'Уже возвращено: ${alreadyRefunded.toStringAsFixed(2)} ₸',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Осталось вернуть: ${remaining.toStringAsFixed(2)} ₸',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEE6F00),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                // Only digits + one decimal separator. Without this an
                // operator could paste "12.5 ₸" or "$12.50" and the
                // parse would silently floor it to 0.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Сумма возврата',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String?>(
                valueListenable: reasonCode,
                builder: (_, code, __) => DropdownButtonFormField<String>(
                  value: code,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Причина возврата',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final r in refundReasons)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) => reasonCode.value = v,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (необязательно)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(c).pop(null),
                      child: const Text('Закрыть'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        // Round to 2 decimals before send so the backend
                        // doesn't receive a float like 100.12345600001
                        // from operator-pasted text.
                        final rawAmount = double.tryParse(
                                amountCtrl.text.trim().replaceAll(',', '.')) ??
                            0.0;
                        final amount =
                            double.parse(rawAmount.toStringAsFixed(2));
                        final code = reasonCode.value;
                        final note = reasonCtrl.text.trim();
                        // Canonical label is the structured reason; the free
                        // note is appended after " · " so the stored string
                        // stays analyzable by its canonical prefix while
                        // preserving any operator detail.
                        final reason = code == null
                            ? note
                            : (note.isEmpty ? code : '$code · $note');

                        // жёсткая валидация — иначе будет мусор в бэке
                        if (amount <= 0) {
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Сумма должна быть > 0')));
                          return;
                        }
                        // Cap at the REMAINING balance, not the full order
                        // total, so a second partial refund can't exceed
                        // what's left to return.
                        if (amount > remaining + 0.0001) {
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Сумма больше остатка к возврату')));
                          return;
                        }
                        if (code == null) {
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Выберите причину возврата')));
                          return;
                        }
                        // "Другое" is only meaningful with a note — otherwise
                        // it's just the old un-analyzable free-text problem.
                        if (code == 'Другое' && note.isEmpty) {
                          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Для «Другое» добавьте комментарий')));
                          return;
                        }

                        // Two-step confirm — refunds are irreversible
                        // money movement, no taking it back if the
                        // operator fat-fingered the amount. Without
                        // this any accidental tap of "Оформить" with
                        // pre-filled-to-full-amount sent a real refund.
                        // "Full" now means the whole REMAINING balance —
                        // i.e. this refund closes out the order.
                        final isFullRefund = (amount + 0.0001 >= remaining);
                        final confirmed = await showDialog<bool>(
                          context: c,
                          barrierDismissible: false,
                          builder: (dctx) => AlertDialog(
                            title: const Text('Подтвердите возврат'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Сумма: ${amount.toStringAsFixed(2)} ₸'
                                  '${isFullRefund ? " (полный возврат)" : ""}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Text('Причина: $reason'),
                                const SizedBox(height: 12),
                                const Text(
                                  'Это действие нельзя отменить.',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dctx).pop(false),
                                child: const Text('Назад'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(dctx).pop(true),
                                child: const Text('Подтвердить'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;

                        if (!c.mounted) return;
                        Navigator.of(c).pop(_RefundPayload(
                          amount: amount,
                          reason: reason,
                          idempotencyKey: sessionIdempotencyKey,
                        ));
                      },
                      child: const Text('Оформить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    // Sheet closed → allow reopening. (The top-of-method guard blocked a
    // double-tap from stacking a second sheet with its own idempotency key.)
    if (mounted) setState(() => _refundSheetOpen = false);

    amountCtrl.dispose();
    reasonCtrl.dispose();
    reasonCode.dispose();

    if (result == null) return;

    await _refundOrder(
      amount: result.amount,
      reason: result.reason,
      idempotencyKey: result.idempotencyKey,
    );
  }

  Future<void> _changeItemQty(OrderItem item, int newQty) async {
    if (newQty < 1) return;
    if (_itemBusy.contains(item.id)) return;
    // Don't race a packaging save — both recompute the order total server-side,
    // and interleaving them can leave a stale total on screen until the poll.
    if (_saving) return;
    setState(() => _itemBusy.add(item.id));
    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.updateItemQty(
        orderId: _order.id,
        itemId: item.id,
        qty: newQty,
      );
      if (!mounted) return;
      final updatedItems = _order.items
          .map((it) => it.id == item.id
              ? it.copyWith(
                  qty: res.newQty ?? newQty,
                  total: res.newTotal.toStringAsFixed(2),
                )
              : it)
          .toList();
      setState(() {
        _order = _order.copyWith(
          items: updatedItems,
          // Use the backend's authoritative discounted total — NOT
          // subtotal + delivery, which dropped any promo discount.
          totalAmount: res.totalAmount.toStringAsFixed(2),
        );
      });
      _timelineKey.currentState?.refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось изменить количество')),
      );
    } finally {
      if (mounted) setState(() => _itemBusy.remove(item.id));
    }
  }

  Widget _buildPackagingChip() {
    final big = _order.bigBagCount ?? 0;
    final med = _order.mediumBagCount ?? 0;
    final sum = _order.packagingSum ?? 0;
    final editable = _itemsEditable;

    String summary;
    if (big == 0 && med == 0) {
      summary = editable ? 'Не назначены — нажмите чтобы добавить' : '—';
    } else {
      summary = [
        if (big > 0) 'Большой × $big',
        if (med > 0) 'Средний × $med',
      ].join('  ·  ');
    }

    final content = Row(
      children: [
        const Icon(Icons.shopping_bag_outlined,
            color: Color(0xFFEE6F00), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Пакеты',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                summary,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: (big == 0 && med == 0)
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
        if (sum > 0)
          Text(
            formatTenge(sum),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEE6F00)),
          ),
        if (editable) ...[
          const SizedBox(width: 6),
          const Icon(Icons.edit_outlined,
              size: 18, color: Color(0xFFEE6F00)),
        ],
      ],
    );

    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD9B0)),
      ),
      child: content,
    );

    if (!editable) return box;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openPackagingSheet,
        child: box,
      ),
    );
  }

  Future<void> _openPackagingSheet() async {
    if (!_itemsEditable) return;
    final result = await showModalBottomSheet<_PackagingDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => _PackagingEditSheet(
        initialBig: _order.bigBagCount ?? 0,
        initialMedium: _order.mediumBagCount ?? 0,
      ),
    );
    if (result == null) return;
    await _savePackaging(big: result.big, medium: result.medium);
  }

  Future<void> _savePackaging({required int big, required int medium}) async {
    if (_saving) return;
    // Don't race an in-flight item-qty/remove edit (same total-recompute reason).
    if (_itemBusy.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.updatePackaging(
        orderId: _order.id,
        bigBagCount: big,
        mediumBagCount: medium,
      );
      if (!mounted) return;
      setState(() {
        _order = _order.copyWith(
          totalAmount: res.totalAmount.toStringAsFixed(2),
          bigBagCount: res.bigBagCount,
          mediumBagCount: res.mediumBagCount,
          packagingSum: res.packagingSum,
        );
      });
      _timelineKey.currentState?.refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пакеты обновлены')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить пакеты')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeItem(OrderItem item) async {
    if (_itemBusy.contains(item.id)) return;
    if (_saving) return;
    if (_order.items.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нельзя удалить последний товар. Отмените заказ.'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text(item.product.name ?? 'Товар ${item.productId}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _itemBusy.add(item.id));
    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.removeItem(
        orderId: _order.id,
        itemId: item.id,
      );
      if (!mounted) return;
      final updatedItems =
          _order.items.where((it) => it.id != item.id).toList();
      setState(() {
        _order = _order.copyWith(
          items: updatedItems,
          // Use the backend's authoritative discounted total — NOT
          // subtotal + delivery, which dropped any promo discount.
          totalAmount: res.totalAmount.toStringAsFixed(2),
        );
      });
      _timelineKey.currentState?.refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить товар')),
      );
    } finally {
      if (mounted) setState(() => _itemBusy.remove(item.id));
    }
  }

  Future<void> _setItemPicked(OrderItem item, bool picked) async {
    if (_pickBusy.contains(item.id)) return;
    setState(() => _pickBusy.add(item.id));
    try {
      final repo = context.read<OrdersRepository>();
      final res = await repo.setItemPicked(
        orderId: _order.id,
        itemId: item.id,
        picked: picked,
      );
      if (!mounted) return;
      final updatedItems = _order.items
          .map((it) => it.id == item.id
              ? it.copyWith(
                  pickedAt: res.pickedAt,
                  clearPickedAt: res.pickedAt == null,
                )
              : it)
          .toList();
      setState(() => _order = _order.copyWith(items: updatedItems));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отметить товар')),
      );
    } finally {
      if (mounted) setState(() => _pickBusy.remove(item.id));
    }
  }

  Future<void> _refundOrder({
    required double amount,
    required String reason,
    required String idempotencyKey,
  }) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      final repo = context.read<OrdersRepository>();
      // idempotencyKey is generated by the caller (the refund sheet) and
      // stays stable for the entire modal session — so any retry from
      // this _refundOrder (via _showErrorWithRetry below) reuses the
      // same key and the backend dedupes. Generating fresh here was
      // the bug that let triple-taps through as multiple refunds.
      final res = await repo.refundOrder(
        orderId: _order.id,
        amount: amount,
        reason: reason,
        idempotencyKey: idempotencyKey,
      );

      if (!mounted) return;
      if (res.success) {
        // Against the CAPTURED amount, for the same reason the sheet sizes the
        // refund against it: totalAmount has already been shrunk by any earlier
        // substitution refund, so a close-out compared against it looks like it
        // overshot and the order was labelled 'partially-refunded' when it was
        // fully refunded. Matches what the backend now writes.
        final orderTotal = refundCeiling(
          capturedAmount: _order.capturedAmount,
          totalAmount: _order.totalAmount,
          alreadyRefunded: 0.0,
        ).basis;
        // Compare the CUMULATIVE refunded amount (prior history + this one)
        // against it — a second partial refund that closes out the order must
        // flip it to 'refunded', not leave it stuck in 'partially-refunded'.
        // (Optimistic; the 8s poll reconciles anyway.)
        final priorRefunded =
            _refunds.fold<double>(0.0, (s, r) => s + r.amount);
        final newStatus = (priorRefunded + amount + 0.0001 >= orderTotal)
            ? 'refunded'
            : 'partially-refunded';
        setState(() => _order = _order.copyWith(status: newStatus));
        _timelineKey.currentState?.refresh();
        // Refetch the history so the just-applied refund row appears
        // in the RefundHistorySection.
        _loadRefunds();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message.isNotEmpty ? res.message : (res.success ? 'Возврат оформлен' : 'Не удалось оформить возврат'))),
      );
    } on OrdersApiException catch (e) {
      if (!mounted) return;
      _showErrorWithRetry(
        e.message,
        () => _refundOrder(
          amount: amount,
          reason: reason,
          idempotencyKey: idempotencyKey,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showErrorWithRetry(
        'Не удалось оформить возврат',
        () => _refundOrder(
          amount: amount,
          reason: reason,
          idempotencyKey: idempotencyKey,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _order.items;

    final storeState = context.watch<StoreCubit>().state;
    final StoreSelected? selectedStore = storeState is StoreSelected ? storeState : null;

    final cargoItems = items
        .map((it) => CargoItemDto(productId: it.productId, qty: it.qty))
        .toList();

    final totalAmount = _parseMoney(_order.totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: Text('Заказ #${_order.id}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_order),
        ),
      ),
      body: RefreshIndicator(
        // Pull-to-refresh re-pulls order, customer, and refund history
        // in one go. Awaits all three so the spinner sticks until every
        // panel has fresh data — no half-loaded states.
        onRefresh: _onPullToRefresh,
        child: ListView(
          // Forces RefreshIndicator to engage even on short orders that
          // wouldn't otherwise overflow the viewport.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
          _StatusBadge(status: _order.status),
          const SizedBox(height: 16),
          Text('Покупатель', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),

          if (_customerLoading) ...[
            const LinearProgressIndicator(minHeight: 2),
          ] else if (_customerLoadFailed) ...[
            Row(
              children: [
                const Icon(Icons.error_outline, size: 16, color: Colors.orange),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Не удалось загрузить данные покупателя',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Повторить',
                  onPressed: _loadCustomer,
                ),
              ],
            ),
          ] else ...[
            Text('Имя: ${_customer?.fullName ?? '—'}'),
            // Long-press to copy: managers without a paired iPhone can't
            // call directly, but they can paste into a separate device
            // or share via chat. Tap-to-copy is the lowest-friction
            // affordance and needs no extra dependency.
            GestureDetector(
              onLongPress: () => _copyToClipboard(
                _customer?.phone ?? '',
                label: 'Телефон',
              ),
              child: Text(
                'Телефон: ${(_customer?.phone.isNotEmpty == true) ? _customer!.phone : '—'}',
              ),
            ),
            if ((_customer?.email ?? '').trim().isNotEmpty)
              GestureDetector(
                onLongPress: () => _copyToClipboard(
                  _customer!.email!,
                  label: 'Email',
                ),
                child: Text('Email: ${_customer!.email}'),
              ),
          ],

          const SizedBox(height: 8),
          Builder(builder: (_) {
            // Strip empty / "None" / trailing-comma noise that older
            // customer addresses leave in the delivery_address field.
            // E.g. "Адырбекова 114, , , ," → "Адырбекова 114".
            final cleanedAddr = cleanDeliveryAddress(_order.deliveryAddress);
            return GestureDetector(
              onLongPress: () =>
                  _copyToClipboard(cleanedAddr, label: 'Адрес'),
              child: Text('Адрес: $cleanedAddr'),
            );
          }),
          if (_order.customerComment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Комментарий: ${_order.customerComment}'),
          ],
          const SizedBox(height: 12),
          Text('Сумма: ${formatTenge(totalAmount)}',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          Text('Доставка: ${formatTenge(_parseMoney(_order.deliverySum))}'),
          // Customer-picked delivery slot or off-hours scheduled time.
          // Picker needs this to plan their day — when a customer chose
          // «к 17:00» from the in-app slot picker, the assembler must
          // see that target time prominently, not just on the orders
          // list. Format: "К доставке: 17:00 (Сегодня)".
          if (_order.scheduledForAt != null) ...[
            const SizedBox(height: 4),
            _ScheduledDeliveryRow(scheduledForAt: _order.scheduledForAt!),
          ],
          // Off-hours SCHEDULED order: the row above only LABELS the
          // release time — this is the actual action that moves the order
          // into fulfillment now, instead of forcing the manager to open
          // the status dropdown and hand-pick «Оплачен». Only shown while
          // the order is still parked in `scheduled`.
          if (_order.status.toLowerCase() == 'scheduled') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _releasing ? null : _releaseOrder,
                icon: _releasing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Выпустить заказ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEE6F00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          // Packaging — picker needs to know exact bag count before they
          // start assembling the order. Big bag 30₸ (7+ items), medium
          // 15₸ (up to 6). Fields are nullable for orders created before
          // 2026-05-28 (no auto-packaging line back then). When the order
          // is still editable (paid/processing) we render the chip even
          // at 0/0 so the manager can override the heuristic (e.g. 7L of
          // glass juice doesn't fit a Medium and needs to be bumped).
          if ((_order.bigBagCount ?? 0) > 0 ||
              (_order.mediumBagCount ?? 0) > 0 ||
              _itemsEditable) ...[
            const SizedBox(height: 8),
            _buildPackagingChip(),
          ],
          const SizedBox(height: 16),

          if (selectedStore == null) ...[
            const Text('Магазин не выбран (или не загружены данные магазина).'),
          ] else if (_deliveryUnavailable) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Заказ завершён — доставка недоступна.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ] else ...[
            YandexDeliverySection(
              orderId: _order.id,
              storeId: _order.storeId,
              totalAmount: totalAmount,
              shippingLat: _order.shippingLat,
              shippingLng: _order.shippingLng,
              shippingAddress: cleanDeliveryAddress(_order.deliveryAddress),
              storeCoordinates: selectedStore.coordinates,
              storeAddress: selectedStore.storeAddress,
              items: cargoItems,
              customerPhone: _customer?.phone,
              customerName: (_customer == null) ? null : _customer!.fullName == '—' ? null : _customer!.fullName,
            ),
          ],

          // Hide the whole Действия block when neither action makes sense
          // for the current status (e.g. canceled / refunded / payment-failed).
          // Previously the buttons showed on every order — tapping Отменить
          // on a refunded order returned a backend error.
          if (_canCancel || _canRefund) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text('Действия', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_canCancel) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _actionLoading ? null : _cancelOrder,
                      icon: const Icon(Icons.close, size: 18),
                      label: _actionLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Отменить'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_canRefund) const SizedBox(width: 12),
                ],
                if (_canRefund)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_actionLoading || _refundSheetOpen)
                          ? null
                          : _openRefundSheet,
                      icon: const Icon(Icons.replay, size: 18),
                      label: _actionLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Возврат'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ],

          // Append-only refund history — only shows up when the order has
          // been refunded at least once. Each row shows the amount,
          // reason, who did it, and when. Useful for audit when multiple
          // partial refunds happen.
          if (_orderEverRefunded) ...[
            const SizedBox(height: 16),
            _RefundHistorySection(
              items: _refunds,
              loading: _refundsLoading,
            ),
          ],

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Товары',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${items.length} ${_pluralItems(items.length)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (!_itemsEditable) ...[
            const SizedBox(height: 4),
            Text(
              'Редактирование доступно только в статусах "Оплачен" и "В обработке"',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_itemsEditable) ...[
            const SizedBox(height: 8),
            _PickProgressBar(
              picked: items.where((it) => it.isPicked).length,
              total: items.length,
            ),
          ],
          const SizedBox(height: 8),
          ...items.map((it) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OrderItemCard(
                    item: it,
                    editable: _itemsEditable,
                    busy: _itemBusy.contains(it.id),
                    onQtyChange: (newQty) => _changeItemQty(it, newQty),
                    onRemove: () => _removeItem(it),
                    onPickedToggle: _itemsEditable
                        ? (v) => _setItemPicked(it, v)
                        : null,
                    pickedBusy: _pickBusy.contains(it.id),
                  ),
                  SubstitutionItemRow(
                    order: _order,
                    item: it,
                    editable: _itemsEditable,
                    busy: _subBusy.contains(it.id),
                    onPropose: () => _openSubstitutePicker(it),
                    onCancel: (subId) => _cancelSubstitution(subId, it.id),
                  ),
                ],
              )),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          OrderTimelineSection(key: _timelineKey, orderId: _order.id),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Status-change form. When the order is in a terminal state
          // (canceled / refunded / partially-refunded) the heading,
          // reason field, error display, and Save button are ALL hidden
          // — only a friendly "this order is done" message is shown.
          // Before: heading + dropdown hid, but reason field + Save
          // button sat orphaned looking like they could do something.
          Builder(builder: (context) {
            // Only offer transitions the backend will actually accept
            // from the current status. Previously the dropdown listed
            // EVERY status, so an admin could pick completed ->
            // pending-payment and get a silent rejection.
            final allowed =
                kAdminAllowedTransitions[_order.status.toLowerCase().trim()] ?? const <String>{};
            final validStatuses = _statuses
                .where((s) => allowed.contains(s.statusName))
                .toList();

            if (allowed.isEmpty) {
              return Text(
                'Этот заказ завершён — изменение статуса недоступно.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Изменить статус', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Новый статус',
                      border: OutlineInputBorder(),
                    ),
                    items: validStatuses
                        .map((s) => DropdownMenuItem<String>(
                              value: s.statusName,
                              child: Text(orderStatusRu(s.statusName)),
                            ))
                        .toList(),
                    onChanged: (_saving || _statusesLoading)
                        ? null
                        : (v) => setState(() => _selectedStatus = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Обновить список статусов',
                  onPressed: _statusesLoading ? null : _loadStatuses,
                  icon: _statusesLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Причина (необязательно)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                ],
                // A3: while any substitution is still awaiting the customer, the
                // order can't advance (backend blocks ready-for-delivery/
                // delivering + the last-line decline can auto-cancel). Show WHY
                // the control is disabled instead of letting the manager hit a
                // raw rejection.
                if (_order.hasOpenSubstitution) ...[
                  Row(
                    children: [
                      Icon(Icons.hourglass_top,
                          size: 16, color: Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Дождитесь ответа покупателя по замене — заказ нельзя двигать дальше',
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (_saving || _order.hasOpenSubstitution)
                        ? null
                        : _changeStatus,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Сохранить'),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
      ),
    );
  }

  /// Pull-to-refresh handler. Re-loads order + customer + refund history
  /// in parallel and waits for all to finish so the RefreshIndicator
  /// spinner reflects actual data freshness, not just the order call.
  Future<void> _onPullToRefresh() async {
    await Future.wait([
      _pollOrder(),
      _loadCustomer(),
      if (_orderEverRefunded) _loadRefunds(),
    ]);
  }
}

class _RefundPayload {
  final double amount;
  final String reason;
  /// Idempotency key generated once when the refund sheet opens, used
  /// for the entire modal session. If the operator triple-taps "Оформить"
  /// (or re-opens the sheet by accident), the backend dedupes on this
  /// key and only the first POST applies. Without this we generated a
  /// fresh UUID per call and got duplicate refunds.
  final String idempotencyKey;
  _RefundPayload({
    required this.amount,
    required this.reason,
    required this.idempotencyKey,
  });
}

String _pluralItems(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'товар';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'товара';
  return 'товаров';
}

/// Append-only refund history. Reads /admin/orders/{id}/refunds and
/// renders newest-first. Loading state is a thin progress strip — the
/// section is non-critical so we never block the page on it.
class _RefundHistorySection extends StatelessWidget {
  final List<RefundHistoryEntry> items;
  final bool loading;
  const _RefundHistorySection({required this.items, required this.loading});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'История возвратов',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (!loading && items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Возвраты пока не зафиксированы.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        for (final r in items)
          Card(
            margin: const EdgeInsets.only(top: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatTenge(r.amount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                      Text(
                        df.format(r.createdAt.toLocal()),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(r.reason),
                  if (r.createdBy != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Оформил: #${r.createdBy}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Prominent colored status badge at the top of order detail — replaces
/// the old "Статус: X" plain text so admin can read order state from
/// across the room (iPad in the warehouse).
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  // Maps the backend status code to a (background, foreground, icon) tuple.
  static const _colors = <String, ({Color bg, Color fg, IconData icon})>{
    'pending-payment': (bg: Color(0xFFFFF4E5), fg: Color(0xFFAD6800), icon: Icons.hourglass_empty),
    'paid':            (bg: Color(0xFFE3F2FD), fg: Color(0xFF1565C0), icon: Icons.payments_outlined),
    'processing':      (bg: Color(0xFFE8EAF6), fg: Color(0xFF283593), icon: Icons.inventory_2_outlined),
    'ready-for-delivery': (bg: Color(0xFFE0F7FA), fg: Color(0xFF006064), icon: Icons.local_shipping_outlined),
    'delivering':      (bg: Color(0xFFFFF8E1), fg: Color(0xFFE65100), icon: Icons.directions_bike),
    'delivered':       (bg: Color(0xFFE8F5E9), fg: Color(0xFF2E7D32), icon: Icons.check_circle_outline),
    'completed':       (bg: Color(0xFFE8F5E9), fg: Color(0xFF2E7D32), icon: Icons.check_circle),
    'canceled':        (bg: Color(0xFFFFEBEE), fg: Color(0xFFC62828), icon: Icons.cancel_outlined),
    'refunded':        (bg: Color(0xFFFCE4EC), fg: Color(0xFFAD1457), icon: Icons.replay),
    'partially-refunded': (bg: Color(0xFFFCE4EC), fg: Color(0xFFAD1457), icon: Icons.replay_circle_filled_outlined),
    'payment-failed':  (bg: Color(0xFFFFEBEE), fg: Color(0xFFC62828), icon: Icons.error_outline),
    'payment-timeout': (bg: Color(0xFFFFF4E5), fg: Color(0xFFAD6800), icon: Icons.timer_off_outlined),
    'scheduled':       (bg: Color(0xFFEDE7F6), fg: Color(0xFF4527A0), icon: Icons.schedule),
  };

  @override
  Widget build(BuildContext context) {
    final c = _colors[status.toLowerCase().trim()] ??
        (bg: Colors.grey.shade200, fg: Colors.grey.shade700, icon: Icons.help_outline);
    final theme = Theme.of(context);
    // Render as a row "Статус заказа: <chip>" instead of a full-width
    // rounded pill. The old design looked like a button — managers kept
    // tapping the pink "Полный возврат" expecting it to issue a refund.
    return Row(
      children: [
        Text(
          'Статус заказа: ',
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.fg.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(c.icon, color: c.fg, size: 14),
              const SizedBox(width: 6),
              Text(
                orderStatusRu(status),
                style: TextStyle(
                  color: c.fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickProgressBar extends StatelessWidget {
  final int picked;
  final int total;

  const _PickProgressBar({required this.picked, required this.total});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = total == 0 ? 0.0 : picked / total;
    final allDone = total > 0 && picked == total;
    final color = allDone ? Colors.green.shade600 : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allDone ? Icons.check_circle : Icons.inventory_2_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                allDone ? 'Все товары собраны' : '$picked из $total собрано',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: scheme.surface,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackagingDraft {
  final int big;
  final int medium;
  const _PackagingDraft({required this.big, required this.medium});
}

class _PackagingEditSheet extends StatefulWidget {
  final int initialBig;
  final int initialMedium;
  const _PackagingEditSheet({
    required this.initialBig,
    required this.initialMedium,
  });

  @override
  State<_PackagingEditSheet> createState() => _PackagingEditSheetState();
}

class _PackagingEditSheetState extends State<_PackagingEditSheet> {
  static const _bigPrice = 30;
  static const _mediumPrice = 15;

  late int _big = widget.initialBig;
  late int _medium = widget.initialMedium;

  void _bump(bool isBig, int delta) {
    setState(() {
      if (isBig) {
        _big = (_big + delta).clamp(0, 99);
      } else {
        _medium = (_medium + delta).clamp(0, 99);
      }
    });
  }

  bool get _changed =>
      _big != widget.initialBig || _medium != widget.initialMedium;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    final total = _big * _bigPrice + _medium * _mediumPrice;
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Изменить пакеты',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Большой 30 ₸ · Средний 15 ₸',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 18),
              _PackagingRow(
                label: 'Большой пакет',
                priceLabel: '30 ₸',
                count: _big,
                onMinus: () => _bump(true, -1),
                onPlus: () => _bump(true, 1),
              ),
              const SizedBox(height: 10),
              _PackagingRow(
                label: 'Средний пакет',
                priceLabel: '15 ₸',
                count: _medium,
                onMinus: () => _bump(false, -1),
                onPlus: () => _bump(false, 1),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Сумма за пакеты',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      '$total ₸',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEE6F00)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _changed
                          ? () => Navigator.of(context).pop(
                                _PackagingDraft(big: _big, medium: _medium),
                              )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEE6F00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Сохранить',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackagingRow extends StatelessWidget {
  final String label;
  final String priceLabel;
  final int count;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _PackagingRow({
    required this.label,
    required this.priceLabel,
    required this.count,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(priceLabel,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280))),
            ],
          ),
        ),
        _StepperBtn(icon: Icons.remove, onTap: count > 0 ? onMinus : null),
        SizedBox(
          width: 44,
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        _StepperBtn(icon: Icons.add, onTap: count < 99 ? onPlus : null),
      ],
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? const Color(0xFFFFF3E6) : const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? const Color(0xFFEE6F00) : const Color(0xFFB7BBC2),
          ),
        ),
      ),
    );
  }
}

/// «К доставке: 17:00 (Сегодня)» row. Shown on order details whenever
/// the customer picked a specific delivery slot OR the order was
/// auto-scheduled for off-hours. Picker needs this front-and-center to
/// plan their batch order — the orders list shows it conditionally,
/// but most pickers spend time inside an individual order, so the
/// detail page needs it too.
class _ScheduledDeliveryRow extends StatelessWidget {
  final DateTime scheduledForAt;
  const _ScheduledDeliveryRow({required this.scheduledForAt});

  String _dayLabel(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final slotDay = DateTime(when.year, when.month, when.day);
    final diff = slotDay.difference(today).inDays;
    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Завтра';
    return DateFormat('d MMM', 'ru').format(when);
  }

  @override
  Widget build(BuildContext context) {
    final local = scheduledForAt.toLocal();
    final hhmm = DateFormat('HH:mm').format(local);
    final day = _dayLabel(local);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD9B0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 18, color: Color(0xFFEE6F00)),
          const SizedBox(width: 8),
          const Text(
            'К доставке:',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$hhmm · $day',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}
