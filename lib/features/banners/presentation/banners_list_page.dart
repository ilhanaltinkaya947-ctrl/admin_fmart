import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/banner_models.dart';
import '../data/banners_repository.dart';
import '../state/banners_cubit.dart';
import 'banner_edit_page.dart';

class BannersListPage extends StatefulWidget {
  const BannersListPage({super.key});

  @override
  State<BannersListPage> createState() => _BannersListPageState();
}

class _BannersListPageState extends State<BannersListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<BannersCubit>().load();
    });
  }

  Future<void> _openEdit({BannerItem? banner}) async {
    final cubit = context.read<BannersCubit>();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: BannerEditPage(banner: banner),
        ),
      ),
    );
    if (result == true && mounted) cubit.load();
  }

  Future<void> _confirmDelete(BannerItem banner) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить баннер?'),
        content: const Text('Изображение будет удалено навсегда.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Нет')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<BannersCubit>().remove(banner.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Баннер удалён')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить')),
      );
    }
  }

  Future<void> _bulkUploadZip() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;
    if (!mounted) return;

    // Show a non-dismissible spinner while the upload runs — the zip
    // can be 20MB+ and we don't want the admin to think it hung.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final repo = context.read<BannersRepository>();
      final result = await repo.bulkUploadZip(zipFile: File(path));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await context.read<BannersCubit>().load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Загружено: ${result.createdCount}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Создано баннеров: ${result.createdCount}'),
                if (result.skippedCount > 0)
                  Text('Пропущено: ${result.skippedCount}'),
                if (result.errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Ошибки:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...result.errors.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• ${e.filename}: ${e.error}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Баннеры'),
        actions: [
          IconButton(
            tooltip: 'Загрузить zip с баннерами',
            icon: const Icon(Icons.folder_zip_outlined),
            onPressed: _bulkUploadZip,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<BannersCubit>().load(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Новый баннер'),
      ),
      body: BlocBuilder<BannersCubit, BannersState>(
        builder: (context, state) {
          if (state is BannersLoading || state is BannersInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is BannersFailure) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    Text(state.message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => context.read<BannersCubit>().load(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is BannersLoaded && state.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text(
                      'Пока нет баннеров',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Загрузите первый баннер для главной страницы',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _openEdit(),
                      icon: const Icon(Icons.add),
                      label: const Text('Загрузить'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is BannersLoaded && state.items.isNotEmpty) {
            // NOTE: every return below this point must render something. The
            // field report — «не отображается список баннеров», a blank body
            // under a normal AppBar — comes from a state that reached a return
            // painting nothing. ReorderableListView.builder with itemCount 0
            // paints nothing and offers no empty state or retry, so it must
            // never be reachable with an empty list; the isNotEmpty guard above
            // is what prevents that, and the empty case has its own branch.
            return ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: state.items.length,
              onReorder: (oldIdx, newIdx) {
                final ids = BannersRepository.movedOrder(state.items, oldIdx, newIdx);
                if (ids == null) {
                  // We cannot express this move to the server without also
                  // renumbering banners this screen is not showing. Refuse it
                  // loudly instead of writing a position that pulls inactive
                  // or scheduled rows into the storefront's ordering.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Такой порядок нельзя сохранить: рядом есть баннеры, '
                        'которых нет в этом списке. Сначала уберите совпадающие позиции.',
                      ),
                    ),
                  );
                  return;
                }
                context.read<BannersCubit>().reorder(ids);
              },
              itemBuilder: (_, i) {
                final b = state.items[i];
                // RepaintBoundary so dragging one banner doesn't force
                // every other tile (each with a CachedNetworkImage) to
                // re-rasterize per frame — that was the laggy-drag root
                // cause on iPad with 8+ banners.
                return RepaintBoundary(
                  key: ValueKey(b.id),
                  child: _BannerTile(
                    index: i,
                    banner: b,
                    onEdit: () => _openEdit(banner: b),
                    onDelete: () => _confirmDelete(b),
                  ),
                );
              },
            );
          }
          // Reached only for a state this page does not know about. It used
          // to be SizedBox.shrink() — a silent blank screen with no spinner,
          // no message and no way to retry, which is exactly the "list of
          // banners does not display" report from the field. Never render
          // nothing: say so and offer the reload.
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.help_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  Text(
                    'Не удалось показать список баннеров (${state.runtimeType})',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.read<BannersCubit>().load(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Обновить'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BannerTile extends StatelessWidget {
  final int index;
  final BannerItem banner;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BannerTile({
    required this.index,
    required this.banner,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  // The width must be OUTSIDE the AspectRatio. The tile is a
                  // Row, whose children get unbounded width and (here) an
                  // arrival-time unbounded height, so an AspectRatio asked to
                  // size itself from its ratio alone throws
                  // «RenderAspectRatio has unbounded constraints» during
                  // performLayout — and a layout exception blanks the entire
                  // route body while the AppBar and FAB still paint. That is
                  // the reported «не отображается список баннеров»: an empty
                  // panel under a normal header. Size the width first, then let
                  // AspectRatio derive the height from it.
                  child: SizedBox(
                    width: 120,
                    child: AspectRatio(
                      // Must match the customer carousel (_SliderCarousel in
                      // home_page.dart), which is 16/8 with BoxFit.cover. At
                      // 13/8 this thumbnail showed ~19% more image height than
                      // the phone renders, so a banner looked fine here and
                      // came out cropped in the app.
                      aspectRatio: 16 / 8,
                      child: CachedNetworkImage(
                        imageUrl: banner.imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        banner.title?.isNotEmpty == true ? banner.title! : 'Без названия',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _StatusChip(state: banner.publishState),
                          const SizedBox(width: 8),
                          Text(
                            // Derived from sort_order, not the list index: with historical
                            // gaps (0,3,4,5…) a rank would disagree with the number
                            // the edit field shows for the same banner.
                            'Позиция ${banner.sortOrder + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (_windowLabel(banner) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _windowLabel(banner)!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if ((banner.linkUrl ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          banner.linkUrl!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red.shade700,
                  onPressed: onDelete,
                ),
                // Real drag handle: a visible grab icon bound to this
                // tile's actual index. Was an invisible zero-size widget
                // with index:-1, so reorder had no affordance and the
                // index was invalid.
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_handle,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "01.10 — 15.10" style summary of the publish window, or null when the
/// banner has no dates at all (the common case for existing rows).
String? _windowLabel(BannerItem b) {
  String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  final s = b.startsAt;
  final e = b.endsAt;
  if (s == null && e == null) return null;
  if (s != null && e != null) return 'Показ: ${fmt(s)} — ${fmt(e)}';
  if (s != null) return 'Показ с ${fmt(s)}';
  return 'Показ до ${fmt(e!)}';
}

class _StatusChip extends StatelessWidget {
  final BannerPublishState state;
  const _StatusChip({required this.state});

  @override
  Widget build(BuildContext context) {
    // Colour carries the same meaning the chip text does, so a manager can
    // scan the list without reading every label.
    final (Color bg, Color fg) = switch (state) {
      BannerPublishState.live => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      BannerPublishState.scheduled => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      BannerPublishState.expired => (const Color(0xFFF3E5F5), const Color(0xFF6A1B9A)),
      BannerPublishState.disabled => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        state.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
