import 'package:flutter/material.dart';

import '../../../stores/models/store_models.dart';
import '../../data/banner_action_draft.dart';
import '../../data/banners_repository.dart';
import 'banner_pickers.dart';

/// Picks what a banner (or an info page's button) opens and its target.
/// Edits [target] in place and calls [onChanged] after every change.
class BannerTargetEditor extends StatefulWidget {
  const BannerTargetEditor({
    super.key,
    required this.target,
    required this.kinds,
    required this.repo,
    required this.stores,
    required this.onChanged,
  });

  final BannerTarget target;
  final List<BannerActionKind> kinds;
  final BannersRepository repo;
  final List<StoreDto> stores;
  final VoidCallback onChanged;

  @override
  State<BannerTargetEditor> createState() => _BannerTargetEditorState();
}

class _BannerTargetEditorState extends State<BannerTargetEditor> {
  late final _query = TextEditingController(text: widget.target.query);
  late final _shelf = TextEditingController(text: widget.target.shelfKey);
  late final _titleRu = TextEditingController(text: widget.target.collectionTitleRu);
  late final _titleKk = TextEditingController(text: widget.target.collectionTitleKk);
  String _scope = 'all';

  BannerTarget get t => widget.target;

  @override
  void dispose() {
    for (final c in [_query, _shelf, _titleRu, _titleKk]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  Map<int, String> get _storeNames => {for (final s in widget.stores) s.storeId: s.storeName};

  Future<void> _pickProduct() async {
    final got = await Navigator.of(context).push<List<PickedProduct>>(MaterialPageRoute(
      builder: (_) => BannerProductPickerPage(repo: widget.repo, storeNames: _storeNames),
    ));
    if (got == null || got.isEmpty || !mounted) return;
    _changed(() => t.product = got.first);
  }

  Future<void> _addToCollection() async {
    final list = t.lists.putIfAbsent(_scope, () => <PickedProduct>[]);
    final got = await Navigator.of(context).push<List<PickedProduct>>(MaterialPageRoute(
      builder: (_) => BannerProductPickerPage(repo: widget.repo, multi: true, already: list, storeNames: _storeNames),
    ));
    if (got == null || got.isEmpty || !mounted) return;
    _changed(() => list.addAll(got.where((p) => !list.any((q) => q.id == p.id))));
  }

  Future<void> _pickCategory() async {
    final got = await Navigator.of(context).push<BannerCategory>(MaterialPageRoute(
      builder: (_) => BannerCategoryPickerPage(repo: widget.repo),
    ));
    if (got == null || !mounted) return;
    _changed(() {
      t.categoryId = got.id;
      t.categoryName = got.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final k in widget.kinds)
              ChoiceChip(
                key: ValueKey('banner-kind-${k.wire}'),
                label: Text(k.label),
                selected: t.kind == k,
                onSelected: (_) => _changed(() => t.kind = k),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _body(),
      ],
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      );

  Widget _body() {
    switch (t.kind) {
      case BannerActionKind.none:
        return _hint('Баннер просто картинка: нажать на него нельзя.');
      case BannerActionKind.deals:
        return _hint('Откроется раздел «Акции» выбранного покупателем магазина.');
      case BannerActionKind.info:
        return const SizedBox.shrink(); // the info page editor sits below
      case BannerActionKind.product:
        final p = t.product;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hint('Откроется карточка товара. В магазине, где товара сейчас нет, баннер не покажется.'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shopping_bag_outlined),
            title: Text(p == null ? 'Товар не выбран' : p.label),
            subtitle: p == null ? null : Text('№ ${p.id}'),
            trailing: OutlinedButton(onPressed: _pickProduct, child: Text(p == null ? 'Выбрать' : 'Изменить')),
          ),
        ]);
      case BannerActionKind.category:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hint('Откроется список товаров категории.'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.category_outlined),
            title: Text(t.categoryId == null
                ? 'Категория не выбрана'
                : (t.categoryName.isEmpty ? 'Категория ${t.categoryId}' : t.categoryName)),
            trailing: OutlinedButton(onPressed: _pickCategory, child: Text(t.categoryId == null ? 'Выбрать' : 'Изменить')),
          ),
        ]);
      case BannerActionKind.search:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hint('Откроется поиск по этому тексту, как если бы покупатель набрал его сам.'),
          TextField(
            controller: _query,
            maxLength: 60,
            onChanged: (v) => _changed(() => t.query = v),
            decoration: const InputDecoration(labelText: 'Текст поиска', hintText: 'например, мороженое', border: OutlineInputBorder()),
          ),
        ]);
      case BannerActionKind.shelf:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hint('Откроется сезонная полка целиком. Пока полки с этим ключом нет в магазине, баннер там не покажется.'),
          TextField(
            controller: _shelf,
            onChanged: (v) => _changed(() => t.shelfKey = v.trim()),
            decoration: const InputDecoration(labelText: 'Ключ полки', hintText: 'new_year_2027', border: OutlineInputBorder()),
          ),
        ]);
      case BannerActionKind.collection:
        return _collection();
    }
  }

  Widget _collection() {
    final list = t.lists[_scope] ?? const <PickedProduct>[];
    final ownLists = {for (final e in t.lists.entries) if (e.key != 'all' && e.value.isNotEmpty) e.key};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hint('Откроется сетка товаров. В каждом магазине видно только то, что там сейчас продаётся. '
            'Если в магазине не продаётся ни один, баннер там не покажется.'),
        TextField(
          controller: _titleRu,
          maxLength: 60,
          onChanged: (v) => _changed(() => t.collectionTitleRu = v),
          decoration: const InputDecoration(labelText: 'Заголовок страницы', hintText: 'Новогодние подарки', border: OutlineInputBorder(), counterText: ''),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleKk,
          maxLength: 60,
          onChanged: (v) => _changed(() => t.collectionTitleKk = v),
          decoration: InputDecoration(
            labelText: 'Заголовок (KK)',
            border: const OutlineInputBorder(),
            counterText: '',
            helperText: kkMissing(_titleRu.text, _titleKk.text),
            helperStyle: const TextStyle(color: Color(0xFFB26A00)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Список товаров', style: TextStyle(fontWeight: FontWeight.w600)),
        _hint('«Для всех магазинов» действует везде. Свой список магазина заменяет его в этом магазине.'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ChoiceChip(
            label: const Text('Для всех магазинов'),
            selected: _scope == 'all',
            onSelected: (_) => setState(() => _scope = 'all'),
          ),
          for (final s in widget.stores)
            ChoiceChip(
              label: Text(ownLists.contains('${s.storeId}') ? '${s.storeName} (свой)' : s.storeName),
              selected: _scope == '${s.storeId}',
              onSelected: (_) => setState(() => _scope = '${s.storeId}'),
            ),
        ]),
        const SizedBox(height: 8),
        if (list.isEmpty)
          _hint(_scope == 'all' ? 'Пока пусто' : 'Своего списка нет: здесь действует список «Для всех магазинов».'),
        for (var i = 0; i < list.length; i++)
          ListTile(
            key: ValueKey('coll-$_scope-${list[i].id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(list[i].label, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('№ ${list[i].id}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Выше',
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: i == 0 ? null : () => _changed(() => list.insert(i - 1, list.removeAt(i))),
              ),
              IconButton(
                tooltip: 'Убрать',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _changed(() => list.removeAt(i)),
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addToCollection,
            icon: const Icon(Icons.add),
            label: const Text('Добавить товары'),
          ),
        ),
      ],
    );
  }
}

/// The editor's warning when RU is filled and KK is not: Kazakh customers
/// would read the Russian text.
String? kkMissing(String ru, String kk) =>
    (ru.trim().isNotEmpty && kk.trim().isEmpty) ? 'Нет текста на казахском: покупатели увидят русский' : null;
