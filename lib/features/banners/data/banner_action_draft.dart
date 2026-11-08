/// What a tap on a home banner opens (08.11, Ilhan: «как у Migros»), as the
/// banner editor holds it. The server validates every save and answers a
/// plain Russian reason on a refusal (contract _contract_banner_actions.md).
///
/// [toJson] is exactly the payload catalog expects for the type; [fromJson]
/// reads what GET /admin/banners returns (`action_type` + `action`).
enum BannerActionKind {
  none('none', 'Только картинка'),
  product('product', 'Товар'),
  collection('collection', 'Подборка'),
  category('category', 'Категория'),
  deals('deals', 'Акции'),
  search('search', 'Поиск'),
  info('info', 'Инфо-страница'),
  shelf('shelf', 'Сезонная полка');

  const BannerActionKind(this.wire, this.label);
  final String wire;
  final String label;

  static BannerActionKind fromWire(String? w) =>
      BannerActionKind.values.firstWhere((k) => k.wire == w, orElse: () => BannerActionKind.none);

  /// What an info page's button may open.
  static const ctaKinds = [product, collection, category, deals, search, shelf];
}

/// A product picked in the editor: its id plus what the picker showed, so the
/// list reads as names rather than numbers.
class PickedProduct {
  final int id;
  final String name;
  final String? imageUrl;
  const PickedProduct({required this.id, this.name = '', this.imageUrl});

  PickedProduct named(String n, String? image) => PickedProduct(id: id, name: n, imageUrl: image ?? imageUrl);

  String get label => name.isEmpty ? 'Товар $id' : name;
}

class BannerTarget {
  BannerTarget({
    this.kind = BannerActionKind.none,
    this.product,
    Map<String, List<PickedProduct>>? lists,
    this.collectionTitleRu = '',
    this.collectionTitleKk = '',
    this.categoryId,
    this.categoryName = '',
    this.query = '',
    this.shelfKey = 'new_year_2027',
  }) : lists = lists ?? {'all': <PickedProduct>[]};

  BannerActionKind kind;
  PickedProduct? product;

  /// Collection lists: "all" = every store; a store id key overrides it there.
  Map<String, List<PickedProduct>> lists;
  String collectionTitleRu;
  String collectionTitleKk;
  int? categoryId;
  String categoryName;
  String query;
  String shelfKey;

  /// The JSON payload for this kind (null for none / deals).
  Map<String, dynamic>? payload() {
    switch (kind) {
      case BannerActionKind.none:
      case BannerActionKind.deals:
        return null;
      case BannerActionKind.product:
        return {'product_id': product?.id};
      case BannerActionKind.collection:
        return {
          if (collectionTitleRu.trim().isNotEmpty) 'title_ru': collectionTitleRu.trim(),
          if (collectionTitleKk.trim().isNotEmpty) 'title_kk': collectionTitleKk.trim(),
          'product_ids': {
            for (final e in lists.entries)
              if (e.value.isNotEmpty) e.key: [for (final p in e.value) p.id],
          },
        };
      case BannerActionKind.category:
        return {'category_id': categoryId};
      case BannerActionKind.search:
        return {'query': query.trim()};
      case BannerActionKind.shelf:
        return {'key': shelfKey.trim()};
      case BannerActionKind.info:
        return null; // the info page owns its payload (BannerInfoDraft)
    }
  }

  /// Every product id this target names (to look their names up).
  List<int> productIds() => [
        if (kind == BannerActionKind.product && product != null) product!.id,
        if (kind == BannerActionKind.collection)
          for (final l in lists.values) for (final p in l) p.id,
      ];

  /// Puts names on products known only by id.
  void applyNames(Map<int, ({String name, String? image})> names) {
    PickedProduct fill(PickedProduct p) {
      final n = names[p.id];
      return (n == null || p.name.isNotEmpty) ? p : p.named(n.name, n.image);
    }

    if (product != null) product = fill(product!);
    for (final k in lists.keys.toList()) {
      lists[k] = [for (final p in lists[k]!) fill(p)];
    }
  }

  /// A first, local check before the round trip; the server has the last word.
  String? localError() {
    switch (kind) {
      case BannerActionKind.product:
        return product == null ? 'Выберите товар' : null;
      case BannerActionKind.collection:
        return lists.values.every((l) => l.isEmpty) ? 'Добавьте товары в подборку' : null;
      case BannerActionKind.category:
        return categoryId == null ? 'Выберите категорию' : null;
      case BannerActionKind.search:
        return query.trim().length < 2 ? 'Текст поиска: минимум 2 символа' : null;
      case BannerActionKind.shelf:
        return RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(shelfKey.trim()) ? null : 'Неверный код полки';
      default:
        return null;
    }
  }

  /// Reads a stored payload. Products named only by id get a plain label
  /// until the picker is opened.
  static BannerTarget fromJson(String? type, Map<String, dynamic>? a) {
    final kind = BannerActionKind.fromWire(type);
    final t = BannerTarget(kind: kind);
    final d = a ?? const {};
    switch (kind) {
      case BannerActionKind.product:
        final id = _int(d['product_id']);
        if (id != null) t.product = PickedProduct(id: id);
        break;
      case BannerActionKind.collection:
        t.collectionTitleRu = (d['title_ru'] as String?) ?? '';
        t.collectionTitleKk = (d['title_kk'] as String?) ?? '';
        final raw = d['product_ids'];
        final lists = <String, List<PickedProduct>>{'all': []};
        if (raw is Map) {
          raw.forEach((k, v) {
            if (v is List) {
              lists['$k'] = [for (final x in v) if (_int(x) != null) PickedProduct(id: _int(x)!)];
            }
          });
        }
        t.lists = lists;
        break;
      case BannerActionKind.category:
        t.categoryId = _int(d['category_id']);
        break;
      case BannerActionKind.search:
        t.query = (d['query'] as String?) ?? '';
        break;
      case BannerActionKind.shelf:
        t.shelfKey = (d['key'] as String?) ?? '';
        break;
      default:
        break;
    }
    return t;
  }

  static int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}

enum InfoBlockKind { heading, paragraph, bullets, image }

class InfoBlockDraft {
  InfoBlockDraft(this.kind, {this.textRu = '', this.textKk = '', this.url = ''});
  final InfoBlockKind kind;

  /// heading / paragraph text; bullets = one item per line.
  String textRu;
  String textKk;
  String url;

  static List<String> lines(String s) =>
      s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Map<String, dynamic> toJson() {
    switch (kind) {
      case InfoBlockKind.heading:
      case InfoBlockKind.paragraph:
        return {
          'type': kind == InfoBlockKind.heading ? 'heading' : 'paragraph',
          'text_ru': textRu.trim(),
          if (textKk.trim().isNotEmpty) 'text_kk': textKk.trim(),
        };
      case InfoBlockKind.bullets:
        return {
          'type': 'bullets',
          'items_ru': lines(textRu),
          if (lines(textKk).isNotEmpty) 'items_kk': lines(textKk),
        };
      case InfoBlockKind.image:
        return {'type': 'image', 'url': url};
    }
  }

  static InfoBlockDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'heading':
      case 'paragraph':
        return InfoBlockDraft(raw['type'] == 'heading' ? InfoBlockKind.heading : InfoBlockKind.paragraph,
            textRu: '${raw['text_ru'] ?? ''}', textKk: '${raw['text_kk'] ?? ''}');
      case 'bullets':
        String join(Object? v) => v is List ? v.map((e) => '$e').join('\n') : '';
        return InfoBlockDraft(InfoBlockKind.bullets, textRu: join(raw['items_ru']), textKk: join(raw['items_kk']));
      case 'image':
        return InfoBlockDraft(InfoBlockKind.image, url: '${raw['url'] ?? ''}');
    }
    return null;
  }
}

/// An info page («Как работает доставка») as the editor holds it.
class BannerInfoDraft {
  BannerInfoDraft({
    this.titleRu = '',
    this.titleKk = '',
    List<InfoBlockDraft>? blocks,
    this.ctaOn = false,
    this.ctaLabelRu = '',
    this.ctaLabelKk = '',
    BannerTarget? cta,
  })  : blocks = blocks ?? [InfoBlockDraft(InfoBlockKind.paragraph)],
        cta = cta ?? BannerTarget(kind: BannerActionKind.deals);

  String titleRu;
  String titleKk;
  List<InfoBlockDraft> blocks;
  bool ctaOn;
  String ctaLabelRu;
  String ctaLabelKk;
  BannerTarget cta;

  Map<String, dynamic> toJson() => {
        'title_ru': titleRu.trim(),
        if (titleKk.trim().isNotEmpty) 'title_kk': titleKk.trim(),
        'blocks': [for (final b in blocks) b.toJson()],
        if (ctaOn)
          'cta': {
            'label_ru': ctaLabelRu.trim(),
            if (ctaLabelKk.trim().isNotEmpty) 'label_kk': ctaLabelKk.trim(),
            'action_type': cta.kind.wire,
            'action': cta.payload() ?? <String, dynamic>{},
          },
      };

  String? localError() {
    if (titleRu.trim().isEmpty) return 'Страница: заполните заголовок';
    if (blocks.isEmpty) return 'Страница: добавьте хотя бы один блок';
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final empty = switch (b.kind) {
        InfoBlockKind.image => b.url.isEmpty,
        InfoBlockKind.bullets => InfoBlockDraft.lines(b.textRu).isEmpty,
        _ => b.textRu.trim().isEmpty,
      };
      if (empty) return 'Страница: блок ${i + 1} пустой';
    }
    if (ctaOn) {
      if (ctaLabelRu.trim().isEmpty) return 'Кнопка: заполните текст';
      return cta.localError();
    }
    return null;
  }

  static BannerInfoDraft fromJson(Map<String, dynamic>? a) {
    final d = a ?? const {};
    final blocks = <InfoBlockDraft>[];
    final raw = d['blocks'];
    if (raw is List) {
      for (final b in raw) {
        final x = InfoBlockDraft.fromJson(b);
        if (x != null) blocks.add(x);
      }
    }
    final cta = d['cta'];
    return BannerInfoDraft(
      titleRu: (d['title_ru'] as String?) ?? '',
      titleKk: (d['title_kk'] as String?) ?? '',
      blocks: blocks.isEmpty ? null : blocks,
      ctaOn: cta is Map,
      ctaLabelRu: cta is Map ? '${cta['label_ru'] ?? ''}' : '',
      ctaLabelKk: cta is Map ? '${cta['label_kk'] ?? ''}' : '',
      cta: cta is Map
          ? BannerTarget.fromJson('${cta['action_type']}',
              cta['action'] is Map ? (cta['action'] as Map).cast<String, dynamic>() : null)
          : null,
    );
  }
}

/// The whole action of a banner: its type, its target, or its info page.
class BannerActionDraft {
  BannerActionDraft({BannerTarget? target, BannerInfoDraft? info})
      : target = target ?? BannerTarget(),
        info = info ?? BannerInfoDraft();

  BannerTarget target;
  BannerInfoDraft info;

  BannerActionKind get kind => target.kind;
  set kind(BannerActionKind k) => target.kind = k;

  Map<String, dynamic>? payload() => kind == BannerActionKind.info ? info.toJson() : target.payload();

  String? localError() => kind == BannerActionKind.info ? info.localError() : target.localError();

  static BannerActionDraft fromJson(String? type, Map<String, dynamic>? action) {
    final kind = BannerActionKind.fromWire(type);
    if (kind == BannerActionKind.info) {
      return BannerActionDraft(target: BannerTarget(kind: kind), info: BannerInfoDraft.fromJson(action));
    }
    return BannerActionDraft(target: BannerTarget.fromJson(type, action));
  }
}
