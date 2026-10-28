import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../stores/data/stores_repository.dart';
import '../data/news_models.dart';
import '../state/news_cubit.dart';
import 'news_card_preview.dart';
import 'news_edit_page.dart';

/// Admin → «Новости» (28.10): posts customers read in Уведомления → Новости.
class NewsListPage extends StatefulWidget {
  final StoresRepository storesRepo;
  const NewsListPage({super.key, required this.storesRepo});

  @override
  State<NewsListPage> createState() => _NewsListPageState();
}

class _NewsListPageState extends State<NewsListPage> {
  Map<int, String> _storeNames = const {};

  @override
  void initState() {
    super.initState();
    widget.storesRepo.getStores().then((s) {
      if (mounted) setState(() => _storeNames = {for (final x in s) x.storeId: x.storeName});
    }).catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NewsCubit>().load();
    });
  }

  Future<void> _open([NewsPost? post]) async {
    final cubit = context.read<NewsCubit>();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: NewsEditPage(post: post, storesRepo: widget.storesRepo),
      ),
    ));
  }

  Future<void> _delete(NewsPost p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить новость?'),
        content: Text('«${p.title}» исчезнет у клиентов.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<NewsCubit>().remove(p.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось удалить')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F7),
      appBar: AppBar(
        title: const Text('Новости'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => context.read<NewsCubit>().load()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Новость'),
      ),
      body: BlocBuilder<NewsCubit, NewsState>(
        builder: (context, state) {
          if (state is NewsLoading || state is NewsInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is NewsFailure) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(state.message, textAlign: TextAlign.center)));
          }
          final items = (state as NewsLoaded).items;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Новостей пока нет.\nНажмите «Новость», чтобы написать первую.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _Tile(
              post: items[i],
              storeNames: _storeNames,
              onTap: () => _open(items[i]),
              onDelete: () => _delete(items[i]),
              onToggle: () => context.read<NewsCubit>().setActive(items[i], !items[i].active),
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final NewsPost post;
  final Map<int, String> storeNames;
  final VoidCallback onTap, onDelete, onToggle;
  const _Tile({
    required this.post,
    required this.storeNames,
    required this.onTap,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final state = post.publishState;
    final color = switch (state) {
      NewsPublishState.live => const Color(0xFF18A957),
      NewsPublishState.scheduled => const Color(0xFF2D6FF7),
      NewsPublishState.expired => const Color(0xFF70747A),
      NewsPublishState.disabled => const Color(0xFFE5484D),
    };
    final stores = post.storeIds.isEmpty
        ? 'Все магазины'
        : post.storeIds.map((id) => storeNames[id] ?? 'магазин $id').join(', ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 92,
                height: 50,
                child: post.imageUrl == null
                    ? const ColoredBox(color: Color(0xFFF3F4F5), child: Icon(Icons.article_outlined, color: Color(0xFFA8ACB2)))
                    : CachedNetworkImage(imageUrl: post.imageUrl!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (post.pinned) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.push_pin, size: 14)),
                  Expanded(
                    child: Text(keepNumbersTogether(post.title), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(state.label, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
                Text('${newsDateLabel(post.publishedAt)} · $stores',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF70747A))),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'del' ? onDelete() : onToggle(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'toggle', child: Text(post.active ? 'Скрыть' : 'Показывать')),
                const PopupMenuItem(value: 'del', child: Text('Удалить')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
