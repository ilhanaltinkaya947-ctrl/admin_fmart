import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/banner_action_draft.dart';
import '../../data/banners_repository.dart';

/// Find products by name, barcode or id and pick one ([multi] false) or
/// several. Each row says at which shops it can be ordered right now.
/// Returns the picked products in tap order, or null when closed.
class BannerProductPickerPage extends StatefulWidget {
  const BannerProductPickerPage({
    super.key,
    required this.repo,
    this.multi = false,
    this.already = const [],
    this.storeNames = const {},
  });

  final BannersRepository repo;
  final bool multi;
  final List<PickedProduct> already;
  final Map<int, String> storeNames;

  @override
  State<BannerProductPickerPage> createState() => _BannerProductPickerPageState();
}

class _BannerProductPickerPageState extends State<BannerProductPickerPage> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<BannerProductHit> _hits = const [];
  bool _loading = false;
  String? _error;
  int _gen = 0;
  late final Set<int> _taken = {for (final p in widget.already) p.id};
  final List<PickedProduct> _picked = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onText(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String v) async {
    final q = v.trim();
    final mine = ++_gen;
    if (q.isEmpty) {
      setState(() {
        _hits = const [];
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final hits = await widget.repo.searchProducts(q);
      if (!mounted || mine != _gen) return;
      setState(() {
        _hits = hits;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || mine != _gen) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось найти товары. Проверьте связь и попробуйте снова.';
      });
    }
  }

  void _tap(BannerProductHit h) {
    if (!widget.multi) {
      Navigator.of(context).pop([h.picked]);
      return;
    }
    setState(() {
      final i = _picked.indexWhere((p) => p.id == h.id);
      if (i >= 0) {
        _picked.removeAt(i);
      } else if (!_taken.contains(h.id)) {
        _picked.add(h.picked);
      }
    });
  }

  String _where(BannerProductHit h) {
    if (h.stores.isEmpty) return 'Сейчас нигде не продаётся';
    final names = h.stores.map((s) => widget.storeNames[s] ?? 'Магазин $s').join(', ');
    return 'В продаже: $names';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multi ? 'Товары в подборку' : 'Выбрать товар'),
        actions: [
          if (widget.multi)
            TextButton(
              onPressed: _picked.isEmpty ? null : () => Navigator.of(context).pop(_picked),
              child: Text(_picked.isEmpty ? 'Готово' : 'Добавить ${_picked.length}'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const ValueKey('banner-product-search'),
              controller: _q,
              autofocus: true,
              onChanged: _onText,
              onSubmitted: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Название, штрихкод или номер товара',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : _hits.isEmpty
                    ? Center(
                        child: Text(_q.text.trim().isEmpty ? 'Начните вводить название' : (_loading ? '' : 'Ничего не нашлось'),
                            style: TextStyle(color: Colors.grey.shade600)),
                      )
                    : ListView.separated(
                        itemCount: _hits.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final h = _hits[i];
                          final taken = _taken.contains(h.id);
                          final on = _picked.any((p) => p.id == h.id);
                          return ListTile(
                            enabled: !taken,
                            onTap: () => _tap(h),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: (h.imageUrl ?? '').isEmpty
                                    ? const ColoredBox(color: Color(0xFFF3F4F5), child: Icon(Icons.image_outlined, size: 20))
                                    : CachedNetworkImage(imageUrl: h.imageUrl!, fit: BoxFit.contain),
                              ),
                            ),
                            title: Text(h.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              taken ? 'Уже в подборке' : '№ ${h.id} · ${_where(h)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: h.stores.isEmpty ? const Color(0xFFC62828) : Colors.grey.shade700,
                              ),
                            ),
                            trailing: widget.multi
                                ? Icon(on ? Icons.check_circle : Icons.add_circle_outline,
                                    color: on ? const Color(0xFF2E7D32) : null)
                                : const Icon(Icons.chevron_right),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Pick one category from the catalog's tree (search by name).
class BannerCategoryPickerPage extends StatefulWidget {
  const BannerCategoryPickerPage({super.key, required this.repo});
  final BannersRepository repo;

  @override
  State<BannerCategoryPickerPage> createState() => _BannerCategoryPickerPageState();
}

class _BannerCategoryPickerPageState extends State<BannerCategoryPickerPage> {
  List<BannerCategory>? _all;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final all = await widget.repo.categories();
      if (mounted) setState(() => _all = all);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось загрузить категории');
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final byId = {for (final c in all ?? const <BannerCategory>[]) c.id: c};
    final shown = (all ?? const <BannerCategory>[])
        .where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Выбрать категорию')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Название категории', border: OutlineInputBorder()),
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_error!)))
              : all == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final c = shown[i];
                        final parent = c.parentId == null ? null : byId[c.parentId!]?.name;
                        return ListTile(
                          title: Text(c.name),
                          subtitle: parent == null ? const Text('Отдел') : Text('в «$parent»'),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
