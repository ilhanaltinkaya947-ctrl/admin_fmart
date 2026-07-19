import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/feature_flags.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/models/order_models.dart';
import '../../orders/presentation/_sub_tokens.dart';

/// Rating gold — the single source for the star colour used across the stats
/// card, distribution bars, filter chips and review cards. Was hardcoded as
/// `0xFFFFB300` in ~5 spots.
const Color _kRatingGold = Color(0xFFFFB300);

/// Admin Отзывы tab. Top: avg rating + count + 1-5 distribution bars.
/// Below: paginated list of reviews with stars, comment, date, order id.
/// Filters: rating chip set (1..5) + clear-filter button.
class ReviewsPage extends StatefulWidget {
  final int storeId;
  final String storeName;

  const ReviewsPage({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  static const _pageSize = 30;

  bool _loading = true;
  String? _error;
  ReviewStats? _stats;
  final List<ReviewItem> _items = [];
  bool _hasMore = false;
  int? _ratingFilter;
  final ScrollController _scroll = ScrollController();
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Rebuild when the feature flags land. getFeatures() is fired async on the
    // home shell; on a slow first fetch this page could mount before the reply
    // flag arrives and the reply UI would stay hidden until an unrelated
    // rebuild. Listening here (and setState) makes every flag-gated subtree on
    // this page appear as soon as the flags resolve — and, importantly, keeps
    // it reactive for the no-rebuild backend env flip to all managers.
    AdminFeatureFlags.instance.flags.addListener(_onFlagsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  void _onFlagsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AdminFeatureFlags.instance.flags.removeListener(_onFlagsChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _items.clear();
        _hasMore = false;
      });
    }
    try {
      final repo = context.read<OrdersRepository>();
      final results = await Future.wait([
        repo.getReviewStats(storeId: widget.storeId),
        repo.getReviews(
          storeId: widget.storeId,
          limit: _pageSize,
          offset: 0,
          minRating: _ratingFilter,
          maxRating: _ratingFilter,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as ReviewStats;
        final page = results[1] as ReviewsListResponse;
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить отзывы. Попробуйте обновить.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final repo = context.read<OrdersRepository>();
      final page = await repo.getReviews(
        storeId: widget.storeId,
        limit: _pageSize,
        offset: _items.length,
        minRating: _ratingFilter,
        maxRating: _ratingFilter,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _setFilter(int? rating) {
    if (_ratingFilter == rating) return;
    setState(() => _ratingFilter = rating);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отзывы'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            if (_stats != null) _StatsCard(stats: _stats!),
            const SizedBox(height: 12),
            _FilterRow(selected: _ratingFilter, onChange: _setFilter),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!)),
                      TextButton(
                        onPressed: () => _load(reset: true),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    _ratingFilter == null
                        ? 'Пока нет отзывов от клиентов'
                        : 'Нет отзывов с оценкой $_ratingFilter',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              )
            else ...[
              for (final r in _items)
                _ReviewCard(
                  review: r,
                  onReplied: (updated) {
                    final idx =
                        _items.indexWhere((x) => x.id == updated.id);
                    if (idx >= 0) setState(() => _items[idx] = updated);
                  },
                ),
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final ReviewStats stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final maxN = stats.distribution.values.fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      decoration: BoxDecoration(
        color: ST.card,
        borderRadius: BorderRadius.circular(ST.rCard),
        border: Border.all(color: ST.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              children: [
                Text(
                  stats.average.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final filled = i < stats.average.round();
                    return Icon(
                      filled
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: _kRatingGold,
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                  _reviewsPlural(stats.count),
                  style: ST.label(12, c: ST.ink2),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [5, 4, 3, 2, 1].map((star) {
                  final n = stats.distribution[star] ?? 0;
                  final ratio = maxN == 0 ? 0.0 : n / maxN;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          child: Text(
                            '$star',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: _kRatingGold,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 6,
                              backgroundColor: ST.well,
                              valueColor: const AlwaysStoppedAnimation(
                                _kRatingGold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 28,
                          child: Text(
                            '$n',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final int? selected;
  final ValueChanged<int?> onChange;
  const _FilterRow({required this.selected, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Все'),
            selected: selected == null,
            onSelected: (_) => onChange(null),
          ),
          for (final star in [5, 4, 3, 2, 1]) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$star'),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: _kRatingGold,
                  ),
                ],
              ),
              selected: selected == star,
              onSelected: (_) => onChange(star),
            ),
          ],
        ],
      ),
    );
  }
}

/// Russian plural for «отзыв» (1 отзыв / 2 отзыва / 5 отзывов).
String _reviewsPlural(int n) {
  return Intl.plural(
    n,
    one: '$n отзыв',
    few: '$n отзыва',
    many: '$n отзывов',
    other: '$n отзывов',
    locale: 'ru',
  );
}

String _replyTagLabel(String? tag) {
  switch (tag) {
    case 'in_progress':
      return 'Решаем';
    case 'refunded':
      return 'Вернули деньги';
    case 'resolved':
      return 'Решено';
    default:
      return '';
  }
}

class _ReviewCard extends StatelessWidget {
  final ReviewItem review;
  final void Function(ReviewItem updated) onReplied;
  const _ReviewCard({required this.review, required this.onReplied});

  Future<void> _openReply(BuildContext context) async {
    final updated = await showModalBottomSheet<ReviewItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReplyComposer(review: review),
    );
    if (updated != null) onReplied(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('d MMM yyyy, HH:mm', 'ru');
    final answered = review.isAnswered;
    // Unanswered reviews get a brand left-accent bar so a manager triaging 50
    // reviews can spot what still needs a reply at a glance.
    final replyEnabled = AdminFeatureFlags.instance.reviewReply;
    final showAccent = replyEnabled && !answered;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ST.card,
        borderRadius: BorderRadius.circular(ST.rCard),
        border: Border(
          left: BorderSide(
            color: showAccent ? ST.brand : ST.line,
            width: showAccent ? 3 : 1,
          ),
          top: const BorderSide(color: ST.line),
          right: const BorderSide(color: ST.line),
          bottom: const BorderSide(color: ST.line),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final filled = i < review.rating;
                    return Icon(
                      filled
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 18,
                      color: _kRatingGold,
                    );
                  }),
                ),
                const SizedBox(width: 8),
                Text(
                  '${review.rating}/5',
                  style: ST.label(13, c: ST.ink).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (showAccent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ST.milk,
                      borderRadius: BorderRadius.circular(ST.rChip),
                    ),
                    child: Text('Без ответа',
                        style: ST.label(11, c: ST.brand)),
                  ),
                ],
                const Spacer(),
                Text(
                  'Заказ #${review.orderId}',
                  style: ST.label(12, c: ST.brand),
                ),
              ],
            ),
            if ((review.comment ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                review.comment!,
                style: const TextStyle(fontSize: 14),
              ),
            ],
            if (review.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: review.photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _PhotoThumb(
                    urls: review.photoUrls,
                    index: i,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 13,
                  color: ST.ink3,
                ),
                const SizedBox(width: 5),
                Text(
                  'Клиент #${review.customerId}',
                  style: ST.label(11, c: ST.ink2),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.schedule,
                  size: 13,
                  color: ST.ink3,
                ),
                const SizedBox(width: 5),
                Text(
                  dateFmt.format(review.createdAt.toLocal()),
                  style: ST.label(11, c: ST.ink2),
                ),
              ],
            ),
            // Reply UI gated by the staged-rollout flag (Kiril-only for now;
            // a backend env flip opens replies to every manager, no rebuild).
            if (AdminFeatureFlags.instance.reviewReply) ...[
            const SizedBox(height: 10),
            if (answered) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storefront,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text('Ваш ответ',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary)),
                        const Spacer(),
                        if ((review.replyTag ?? '').isNotEmpty)
                          Chip(
                            label: Text(_replyTagLabel(review.replyTag),
                                style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(review.replyText!,
                        style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _openReply(context),
                  icon: const Icon(Icons.edit, size: 15),
                  label: const Text('Изменить ответ'),
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _openReply(context),
                  icon: const Icon(Icons.reply, size: 16),
                  label: const Text('Ответить клиенту'),
                ),
              ),
            ], // end feature-gated reply UI
          ],
        ),
      ),
    );
  }
}

/// Soft, calm placeholder box used while a review photo loads and when it
/// fails — never the jagged broken-image glyph. [icon] distinguishes the two
/// states (loading = no icon, error = muted "no image" icon).
Widget _photoPlaceholder({double? size, IconData? icon}) {
  return Container(
    width: size,
    height: size,
    color: ST.well,
    alignment: Alignment.center,
    child: icon == null
        ? null
        : Icon(icon, size: (size != null && size < 100) ? 22 : 40, color: ST.ink3),
  );
}

/// Tappable review-photo thumbnail → fullscreen zoomable viewer (swipes across
/// all photos on the review). Loading + error states use a calm tonal box.
class _PhotoThumb extends StatelessWidget {
  final List<String> urls;
  final int index;
  const _PhotoThumb({required this.urls, required this.index});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _ReviewPhotoLightbox.open(context, urls, index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ST.rChip),
        child: Image.network(
          urls[index],
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _photoPlaceholder(size: 72),
          errorBuilder: (_, __, ___) => _photoPlaceholder(
              size: 72, icon: Icons.image_not_supported_outlined),
        ),
      ),
    );
  }
}

/// Rounded, scrimmed fullscreen photo viewer for review photos — pinch-to-zoom
/// with swipe between all photos on the review (PageView).
class _ReviewPhotoLightbox extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _ReviewPhotoLightbox({required this.urls, required this.initialIndex});

  static void open(BuildContext context, List<String> urls, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (_) =>
          _ReviewPhotoLightbox(urls: urls, initialIndex: initialIndex),
    );
  }

  @override
  State<_ReviewPhotoLightbox> createState() => _ReviewPhotoLightboxState();
}

class _ReviewPhotoLightboxState extends State<_ReviewPhotoLightbox> {
  late final PageController _pager =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.urls.length > 1;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ST.rCard),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ST.rCard),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pager,
                  itemCount: widget.urls.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Center(
                      child: Image.network(
                        widget.urls[i],
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const Padding(
                                padding: EdgeInsets.all(40),
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.4, color: Colors.white54),
                                ),
                              ),
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_not_supported_outlined,
                                  size: 44, color: Colors.white54),
                              SizedBox(height: 8),
                              Text('Не удалось загрузить фото',
                                  style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
              if (multi)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_index + 1} / ${widget.urls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reply composer sheet — a text field + optional resolution tag. Returns the
/// updated [ReviewItem] on success (so the card refreshes in place).
class _ReplyComposer extends StatefulWidget {
  final ReviewItem review;
  const _ReplyComposer({required this.review});

  @override
  State<_ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<_ReplyComposer> {
  late final TextEditingController _text =
      TextEditingController(text: widget.review.replyText ?? '');
  String? _tag;
  bool _sending = false;
  String? _error;

  // Quick-reply templates. RU only: the admin app has NO l10n system (RU-only
  // by design per admin scope), so these are not localized. These strings ship
  // verbatim into a CUSTOMER-facing reply — if KK-speaking customers become a
  // priority, add KK variants here (a picker) once the admin app gains l10n.
  static const _quick = [
    'Спасибо за отзыв! Рады, что вам понравилось.',
    'Извините за неудобства. Разбираемся и всё исправим.',
    'Спасибо, что сообщили. Оформили возврат за товар.',
  ];

  @override
  void initState() {
    super.initState();
    _tag = widget.review.replyTag;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Введите текст ответа');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repo = context.read<OrdersRepository>();
      final updated = await repo.replyToReview(
        orderId: widget.review.orderId,
        replyText: body,
        replyTag: _tag,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось отправить ответ. Попробуйте ещё раз.';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Ответ на отзыв — заказ #${widget.review.orderId}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text(
                      q,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    tooltip: q,
                    onPressed: _sending
                        ? null
                        : () => setState(() {
                              // Set text AND park the caret at the end so a
                              // manager can keep typing after picking a template.
                              _text.value = TextEditingValue(
                                text: q,
                                selection: TextSelection.collapsed(
                                    offset: q.length),
                              );
                            }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              maxLines: 4,
              maxLength: 2000,
              enabled: !_sending,
              decoration: InputDecoration(
                hintText: 'Ваш ответ клиенту…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: ST.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: ST.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: ST.brand, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('Статус (необязательно)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final t in const ['in_progress', 'refunded', 'resolved'])
                  ChoiceChip(
                    label: Text(_replyTagLabel(t)),
                    selected: _tag == t,
                    onSelected: _sending
                        ? null
                        : (sel) => setState(() => _tag = sel ? t : null),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 18),
                label: Text(widget.review.isAnswered
                    ? 'Обновить ответ'
                    : 'Отправить клиенту'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
