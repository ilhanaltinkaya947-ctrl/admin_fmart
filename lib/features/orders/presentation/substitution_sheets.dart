import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/feature_flags.dart';
import '../data/orders_repository.dart';
import '../models/order_models.dart';
import '_sub_tokens.dart';

/// Result of the substitute picker sheet, handed back to the order page so it
/// can refetch / toast / route the empty-state remove through its own flow.
enum SubstituteSheetOutcome { proposed, removeItemRequested, dismissed }

String _money(num v) {
  final n = v.round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$buf ₸';
}

double _parse(String s) => double.tryParse(s) ?? 0.0;

/// Per-item substitution UI rendered UNDER each OrderItemCard on the admin
/// order detail. Shows one of: the «Нет в наличии → Заменить» action (when
/// editable + no open proposal), an amber "awaiting customer" chip with a
/// cancel affordance (open proposal), or a resolved outcome chip.
class SubstitutionItemRow extends StatelessWidget {
  final Order order;
  final OrderItem item;
  final bool editable;
  final bool busy;
  final VoidCallback onPropose;
  final void Function(int subId) onCancel;

  const SubstitutionItemRow({
    super.key,
    required this.order,
    required this.item,
    required this.editable,
    required this.busy,
    required this.onPropose,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final open = order.openSubstitutionForItem(item.id);

    if (open != null) {
      // Awaiting the customer.
      final mins = _minutesLeft(open.expiresAt);
      return Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.swap_horiz, size: 16, color: ST.brand),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                mins != null
                    ? 'Замена предложена · ждём ответ · ещё $mins мин'
                    : 'Замена предложена · ждём ответ покупателя',
                style: const TextStyle(
                    fontSize: 12.5,
                    color: ST.ink2,
                    fontWeight: FontWeight.w600),
              ),
            ),
            if (busy)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton(
                // The single confirm dialog lives in the parent's
                // _cancelSubstitution — fire straight through so we don't
                // stack two identical AlertDialogs.
                onPressed: () => onCancel(open.id),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 44)),
                child: const Text('Отменить', style: TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      );
    }

    // Most-recent resolved substitution for this item (if any).
    OrderSubstitution? resolved;
    for (final s in order.substitutions) {
      if (s.orderItemId == item.id && !s.isOpen) {
        resolved = s;
        break; // list is newest-first from the backend
      }
    }
    if (resolved != null) {
      final (label, color) = _resolvedLabel(resolved.status);
      return Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 15, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: color)),
            ),
          ],
        ),
      );
    }

    if (!editable) return const SizedBox.shrink();
    // Staged rollout: hide the «Заменить» action unless this manager is in the
    // backend allowlist. A backend env flip shows it to everyone, no rebuild.
    // (Open/resolved substitution rows above still render — they only exist for
    // allowlisted flows anyway, so nothing to hide there.)
    if (!AdminFeatureFlags.instance.substitution) return const SizedBox.shrink();

    // Offer the substitute action.
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: TextButton.icon(
          onPressed: busy ? null : onPropose,
          style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Нет в наличии — заменить',
              style: TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  static int? _minutesLeft(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final diff = expiresAt.difference(DateTime.now().toUtc());
    if (diff.isNegative) return 0;
    // Ceil to match the customer card exactly — both apps must show the same
    // minutes-left for the same TTL (customer uses (inSeconds/60).ceil()).
    return (diff.inSeconds / 60).ceil();
  }

  // Resolved-outcome chip color mirrors the customer rule: green = the
  // customer got a product (accepted); neutral ink = the item was removed
  // (declined / expired / canceled). Never grey-800 alarmism.
  static (String, Color) _resolvedLabel(String status) {
    switch (status) {
      case 'accepted':
        return ('Замена принята покупателем', ST.green);
      case 'declined':
        return ('Покупатель отказался — товар убран, деньги возвращены',
            ST.ink2);
      case 'expired':
        return ('Нет ответа — товар убран, деньги возвращены', ST.ink2);
      case 'canceled':
        return ('Замена отменена', ST.ink2);
      default:
        return (status, ST.ink2);
    }
  }
}

/// Opens the substitute picker → compose → send-confirm flow. Returns the
/// outcome; the caller refetches the order on [proposed] and runs its own
/// remove flow on [removeItemRequested].
Future<SubstituteSheetOutcome> showSubstitutePickerSheet(
  BuildContext context, {
  required OrdersRepository repo,
  required Order order,
  required OrderItem item,
}) async {
  final size = MediaQuery.of(context).size;
  final wide = size.shortestSide >= 600; // iPad / large tablet
  SubstituteSheetOutcome? result;
  if (wide) {
    // iPad-first: a centered, comfortably-sized dialog instead of a
    // full-width bottom sheet that reads as a phone pattern on a tablet.
    result = await showDialog<SubstituteSheetOutcome>(
      context: context,
      builder: (ctx) {
        // Keyboard-aware: shrink the box AND lift it by the inset so the note
        // field doesn't push the header off-screen or overflow the fixed box.
        final mq = MediaQuery.of(ctx);
        final h =
            (mq.size.height * 0.88 - mq.viewInsets.bottom).clamp(420.0, 900.0);
        // Wide enough for the browse grid + detail pane side by side, but
        // capped so it stays a comfortable centered studio on a big iPad.
        final w = (mq.size.width - 80).clamp(360.0, 980.0);
        return Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding:
              EdgeInsets.fromLTRB(40, 32, 40, 32 + mq.viewInsets.bottom),
          child: SizedBox(
            width: w,
            height: h,
            child: _SubstitutePickerSheet(
                repo: repo, order: order, item: item, inDialog: true),
          ),
        );
      },
    );
  } else {
    result = await showModalBottomSheet<SubstituteSheetOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _SubstitutePickerSheet(repo: repo, order: order, item: item),
    );
  }
  return result ?? SubstituteSheetOutcome.dismissed;
}

class _SubstitutePickerSheet extends StatefulWidget {
  final OrdersRepository repo;
  final Order order;
  final OrderItem item;
  final bool inDialog; // true = iPad centered dialog, false = phone bottom sheet
  const _SubstitutePickerSheet(
      {required this.repo,
      required this.order,
      required this.item,
      this.inDialog = false});

  @override
  State<_SubstitutePickerSheet> createState() => _SubstitutePickerSheetState();
}

class _SubstitutePickerSheetState extends State<_SubstitutePickerSheet> {
  bool _loading = true;
  String? _error;
  List<SimilarProduct> _candidates = const [];

  SimilarProduct? _selected; // when set, we're on the compose step
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  bool _confirming = false; // second-tap send-confirm
  bool _closing = false; // latch so a fast double-tap on close can't double-pop
  Timer? _disarmTimer; // auto-disarms the confirm after 4s of no second tap
  final ScrollController _dialogScroll = ScrollController(); // browse grid
  final ScrollController _detailScroll = ScrollController(); // detail pane (iPad)
  final _searchCtrl = TextEditingController();
  String _query = ''; // live filter over the loaded candidates

  /// Candidates after the browse search box. Empty query = full list (already
  /// closest-price-first). Local filter only — no extra API round-trip.
  List<SimilarProduct> get _filtered {
    if (_query.isEmpty) return _candidates;
    return _candidates
        .where((p) => p.name.toLowerCase().contains(_query))
        .toList();
  }

  double get _origUnitPrice => _parse(widget.item.price);
  int get _qty => widget.item.qty;
  String get _origName => widget.item.product.name ?? 'Товар';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disarmTimer?.cancel();
    _dialogScroll.dispose();
    _detailScroll.dispose();
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repo.getSimilarProducts(
        storeId: widget.order.storeId,
        productId: widget.item.productId,
        maxPrice: _origUnitPrice,
      );
      if (!mounted) return;
      // Closest price first (smallest refund = most equivalent product), so the
      // best swap for the customer is the picker's top tap.
      final inStock = list.where((p) => p.inStock).toList()
        ..sort((a, b) => b.effectivePrice.compareTo(a.effectivePrice));
      setState(() {
        _candidates = inStock;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить';
        _loading = false;
      });
    }
  }

  double _refundFor(SimilarProduct p) =>
      ((_origUnitPrice - p.effectivePrice) * _qty).clamp(0, double.infinity);

  Future<void> _submit() async {
    if (_submitting) return; // single-flight — a fast double-tap can't fire two POSTs
    final sub = _selected;
    if (sub == null) return;
    // First tap arms the confirm; second tap sends. Auto-disarm after 4s so a
    // stale armed state can't fire on an accidental later tap.
    if (!_confirming) {
      setState(() => _confirming = true);
      _disarmTimer?.cancel();
      _disarmTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _confirming = false);
      });
      return;
    }
    _disarmTimer?.cancel();
    setState(() => _submitting = true);
    try {
      await widget.repo.proposeSubstitution(
        orderId: widget.order.id,
        itemId: widget.item.id,
        substituteProductId: sub.id,
        managerNote: _noteCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(SubstituteSheetOutcome.proposed);
    } on OrdersApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _confirming = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _confirming = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось предложить замену')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.inDialog) return _studio(cs); // iPad master–detail
    // Phone: draggable bottom sheet, single column (browse → detail).
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scroll) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _phoneBody(scroll, cs),
      ),
    );
  }

  /// iPad: a shop-for-the-swap studio — browse similar products on the left
  /// (just like the customer browses the catalog), live preview + send on the
  /// right. One screen, no step-by-step back-and-forth.
  Widget _studio(ColorScheme cs) {
    return Container(
      color: ST.bg,
      child: Column(
        children: [
          _header(cs, showClose: true),
          const Divider(height: 1, color: ST.line),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: _browsePane(cs, _dialogScroll)),
                const VerticalDivider(width: 1, color: ST.line),
                SizedBox(
                  width: 340,
                  child: Container(
                    color: ST.card,
                    child: _detailPane(cs, _detailScroll),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Phone: only one pane is visible at a time, so the single sheet controller
  /// is shared. Browse until a product is tapped, then the detail replaces it.
  Widget _phoneBody(ScrollController scroll, ColorScheme cs) {
    return Container(
      color: ST.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: ST.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          _header(cs, showClose: false),
          const Divider(height: 1, color: ST.line),
          Expanded(
            child: _selected == null
                ? _browsePane(cs, scroll)
                : _detailPane(cs, scroll),
          ),
        ],
      ),
    );
  }

  /// The out-of-stock item we're replacing — the anchor for the whole flow.
  Widget _header(ColorScheme cs, {required bool showClose}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, showClose ? 8 : 16, 12),
      child: Row(
        children: [
          _thumb(widget.item.product.imageUrl, 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Заменить: $_origName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                    '$_qty шт · ${_money(_origUnitPrice)} · подберём равную или дешевле',
                    style: const TextStyle(fontSize: 12, color: ST.ink2)),
              ],
            ),
          ),
          if (showClose)
            IconButton(
              tooltip: 'Закрыть',
              icon: const Icon(Icons.close),
              onPressed: (_submitting || _closing)
                  ? null
                  : () {
                      _closing = true;
                      Navigator.of(context).pop();
                    },
            ),
        ],
      ),
    );
  }

  /// The browsable catalog of similar in-stock products — a photo grid the
  /// manager scans like a shopper, with a search box to jump to a brand.
  Widget _browsePane(ColorScheme cs, ScrollController scroll) {
    if (_loading) return _gridSkeleton(cs, scroll);
    if (_error != null) {
      return _centered(
        icon: Icons.wifi_off,
        title: _error!,
        action: TextButton(onPressed: _load, child: const Text('Повторить')),
      );
    }
    if (_candidates.isEmpty) {
      return _centered(
        icon: Icons.search_off,
        title: 'Нет подходящей замены в наличии',
        subtitle: 'Можно убрать товар и вернуть деньги покупателю',
        action: FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(SubstituteSheetOutcome.removeItemRequested),
          child: Text('Убрать и вернуть ${_money(_origUnitPrice * _qty)}'),
        ),
      );
    }
    final items = _filtered;
    final closestId = _candidates.first.id; // globally closest (list is sorted)
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: ST.well,
              prefixIcon: const Icon(Icons.search, size: 20, color: ST.ink3),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              hintText: 'Поиск среди похожих товаров…',
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _centered(
                  icon: Icons.search_off,
                  title: 'Ничего не найдено',
                  subtitle: 'Попробуйте другое название')
              : GridView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisExtent: 232,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) =>
                      _pickCard(items[i], cs, isClosest: items[i].id == closestId),
                ),
        ),
      ],
    );
  }

  /// One product in the browse grid: photo-forward, tappable, with the refund
  /// it yields and a «ближайшая замена» tag on the closest match. Selected =
  /// brand ring + tint, so the current choice reads at a glance.
  Widget _pickCard(SimilarProduct p, ColorScheme cs, {required bool isClosest}) {
    final selected = _selected?.id == p.id;
    final delta = _origUnitPrice - p.effectivePrice;
    return GestureDetector(
      // Changing the selection resets the arm-then-confirm — otherwise an
      // armed send from a previous card would let the next card fire on a
      // single tap. Mirrors what «Назад» does.
      onTap: () => setState(() {
        _selected = p;
        _confirming = false;
        _disarmTimer?.cancel();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? ST.milk : ST.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? ST.brand : ST.line,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: _photo(p.imageUrl, cs),
                    ),
                  ),
                  if (isClosest)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                            color: ST.brand,
                            borderRadius: BorderRadius.circular(7)),
                        child: const Text('ближайшая замена',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  if (selected)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: ST.brand,
                        child: Icon(Icons.check,
                            size: 15, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(_money(p.effectivePrice),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (delta > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: ST.greenMilk,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('−${_money(delta)}',
                        style: const TextStyle(
                            color: ST.green,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Photo filling a box (grid cell / preview), cover-cropped, graceful glyph
  /// fallback when the SKU has no image.
  Widget _photo(String? url, ColorScheme cs) {
    final ph = Container(
      color: ST.well,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: ST.ink3),
    );
    if (url == null || url.isEmpty) return ph;
    return Image.network(url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => ph);
  }

  Widget _gridSkeleton(ColorScheme cs, ScrollController scroll) {
    return GridView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 232,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: ST.well,
        highlightColor: ST.card,
        child: Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  /// The right-hand pane (iPad) / second screen (phone): a live preview of the
  /// exact card the customer will receive, the refund it triggers, an optional
  /// note, and the send button. Empty until a product is chosen.
  Widget _detailPane(ColorScheme cs, ScrollController scroll) {
    final sub = _selected;
    if (sub == null) {
      return _centered(
        icon: Icons.swap_horiz,
        title: 'Выберите замену',
        subtitle: 'Нажмите на товар слева — покупатель увидит его карточку',
        action: TextButton.icon(
          onPressed: () => Navigator.of(context)
              .pop(SubstituteSheetOutcome.removeItemRequested),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text('Убрать и вернуть ${_money(_origUnitPrice * _qty)}'),
        ),
      );
    }
    final refund = _refundFor(sub);
    final note = _noteCtrl.text.trim();
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Text('Покупатель увидит:',
                  style: const TextStyle(fontSize: 12, color: ST.ink2)),
              const SizedBox(height: 8),
              // A real preview of the customer's swap card, so the manager
              // sends knowing exactly what lands on the customer's screen.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ST.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ST.brand.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _previewTile(
                            img: widget.item.product.imageUrl,
                            name: _origName,
                            price: _origUnitPrice,
                            cs: cs,
                            dim: true,
                            struck: true,
                            badge: 'Нет в наличии',
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 23, left: 6, right: 6),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                                color: ST.brand, shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_forward,
                                size: 15, color: Colors.white),
                          ),
                        ),
                        Expanded(
                          child: _previewTile(
                            img: sub.imageUrl,
                            name: sub.name,
                            price: sub.effectivePrice,
                            cs: cs,
                            refund: refund,
                          ),
                        ),
                      ],
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: ST.well,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('«$note»',
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: ST.ink2,
                                fontStyle: FontStyle.italic)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: ST.greenMilk,
                    borderRadius: BorderRadius.circular(12)),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: ST.ink),
                    children: refund > 0
                        ? [
                            const TextSpan(text: 'Покупателю вернём '),
                            TextSpan(
                                text: _money(refund),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: ST.green)),
                          ]
                        : const [
                            TextSpan(text: 'Цена та же — возврата не будет')
                          ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteCtrl,
                maxLength: 200,
                maxLines: 2,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Сообщение покупателю (необязательно)',
                  hintText:
                      'Напр.: Взяли такой же, но другого бренда — качество то же',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        // Sticky action bar — always reachable above the keyboard, so a
        // cold-aisle picker never scrolls to find "send".
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: const BoxDecoration(
            color: ST.card,
            border: Border(top: BorderSide(color: ST.line)),
          ),
          child: Row(
            children: [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () {
                        _disarmTimer?.cancel();
                        setState(() {
                          _selected = null;
                          _confirming = false;
                        });
                      },
                child: const Text('Назад'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _confirming && !_submitting
                    ? FilledButton.icon(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 50)),
                        icon: const Icon(Icons.send, size: 18),
                        label: Text(refund > 0
                            ? 'Отправить · вернём ${_money(refund)}'
                            : 'Отправить покупателю'),
                      )
                    : FilledButton.tonal(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 50)),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Предложить замену'),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Mini replica of the customer's product tile (photo + name + price), used
  /// in the compose preview so the manager sees the actual swap the customer
  /// will get.
  Widget _previewTile({
    required String? img,
    required String name,
    required double price,
    required ColorScheme cs,
    bool dim = false,
    bool struck = false,
    String? badge,
    double? refund,
  }) {
    final ph = Container(
      color: ST.well,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: ST.ink3),
    );
    final image = (img == null || img.isEmpty)
        ? ph
        : Image.network(img,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 66,
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: dim ? 0.55 : 1,
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(10), child: image),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(7)),
                    child: Text(badge,
                        style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: ST.ink2)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                color: dim ? ST.ink2 : ST.ink)),
        const SizedBox(height: 2),
        Text(_money(price),
            style: struck
                ? const TextStyle(
                    fontSize: 12,
                    color: ST.ink2,
                    decoration: TextDecoration.lineThrough)
                : const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        if (refund != null && refund > 0) ...[
          const SizedBox(height: 2),
          Text('вернём ${_money(refund)}',
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: ST.green)),
        ],
      ],
    );
  }

  Widget _thumb(String? url, double size) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: ST.well, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_outlined, size: size * 0.5, color: ST.ink3),
    );
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder),
    );
  }

  Widget _centered({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: ST.ink3),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: ST.ink)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ST.ink2, fontSize: 13)),
              ],
              if (action != null) ...[
                const SizedBox(height: 16),
                action,
              ],
            ],
          ),
        ),
      );
}
