import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../orders/data/orders_repository.dart';
import '../../orders/models/order_models.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
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
              for (final r in _items) _ReviewCard(review: r),
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
    return Card(
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
                      color: const Color(0xFFFFB300),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                  '${stats.count} отзывов',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                          color: Color(0xFFFFB300),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 6,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: const AlwaysStoppedAnimation(
                                Color(0xFFFFB300),
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
                    color: Color(0xFFFFB300),
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

class _ReviewCard extends StatelessWidget {
  final ReviewItem review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('d MMM yyyy, HH:mm', 'ru');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                      color: const Color(0xFFFFB300),
                    );
                  }),
                ),
                const SizedBox(width: 8),
                Text(
                  '${review.rating}/5',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  'Заказ #${review.orderId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
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
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 12,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  'Клиент #${review.customerId}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.schedule,
                  size: 12,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  dateFmt.format(review.createdAt.toLocal()),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
