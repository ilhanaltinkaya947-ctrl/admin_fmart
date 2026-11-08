import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../stores/models/store_models.dart';
import '../../data/banner_action_draft.dart';
import '../../data/banners_repository.dart';
import 'banner_app_preview.dart';
import 'banner_target_editor.dart';

/// The info page editor («Как работает доставка»): title, blocks (subheading,
/// text, list, picture) in RU and KK, an optional button, and a live preview
/// of the page as the customer app draws it.
class BannerInfoEditor extends StatefulWidget {
  const BannerInfoEditor({
    super.key,
    required this.info,
    required this.repo,
    required this.stores,
    required this.onChanged,
    this.heroFile,
    this.heroUrl,
  });

  final BannerInfoDraft info;
  final BannersRepository repo;
  final List<StoreDto> stores;
  final VoidCallback onChanged;
  final File? heroFile;
  final String? heroUrl;

  @override
  State<BannerInfoEditor> createState() => _BannerInfoEditorState();
}

class _BannerInfoEditorState extends State<BannerInfoEditor> {
  BannerInfoDraft get d => widget.info;
  bool _uploading = false;

  void _changed(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  Future<void> _addImage() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Из галереи'),
              onTap: () => Navigator.of(c).pop('gallery')),
          ListTile(leading: const Icon(Icons.folder_outlined), title: const Text('Из файлов'),
              onTap: () => Navigator.of(c).pop('files')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    File? file;
    if (choice == 'gallery') {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x != null) file = File(x.path);
    } else {
      final r = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic']);
      final path = r?.files.single.path;
      if (path != null) file = File(path);
    }
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await widget.repo.uploadInfoImage(file);
      if (!mounted) return;
      _changed(() => d.blocks.add(InfoBlockDraft(InfoBlockKind.image, url: url)));
    } on BannerValidationException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Не удалось загрузить картинку');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: const Color(0xFFD32F2F)));

  void _preview() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _InfoPreviewPage(info: d, heroFile: widget.heroFile, heroUrl: widget.heroUrl),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Field(
          key: const ValueKey('info-title-ru'),
          label: 'Заголовок страницы',
          initial: d.titleRu,
          max: 80,
          onChanged: (v) => _changed(() => d.titleRu = v),
        ),
        _Field(
          label: 'Заголовок (KK)',
          initial: d.titleKk,
          max: 80,
          warn: () => kkMissing(d.titleRu, d.titleKk),
          onChanged: (v) => _changed(() => d.titleKk = v),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < d.blocks.length; i++) _blockCard(i),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ActionChip(avatar: const Icon(Icons.title, size: 18), label: const Text('Подзаголовок'),
              onPressed: () => _changed(() => d.blocks.add(InfoBlockDraft(InfoBlockKind.heading)))),
          ActionChip(avatar: const Icon(Icons.notes, size: 18), label: const Text('Текст'),
              onPressed: () => _changed(() => d.blocks.add(InfoBlockDraft(InfoBlockKind.paragraph)))),
          ActionChip(avatar: const Icon(Icons.format_list_bulleted, size: 18), label: const Text('Список'),
              onPressed: () => _changed(() => d.blocks.add(InfoBlockDraft(InfoBlockKind.bullets)))),
          ActionChip(
            avatar: _uploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.image_outlined, size: 18),
            label: const Text('Картинка'),
            onPressed: _uploading ? null : _addImage,
          ),
        ]),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const ValueKey('info-cta-switch'),
          contentPadding: EdgeInsets.zero,
          value: d.ctaOn,
          onChanged: (v) => _changed(() => d.ctaOn = v),
          title: const Text('Кнопка внизу страницы'),
          subtitle: const Text('Например «Смотреть подарки»: откроет подборку, акции или товар'),
        ),
        if (d.ctaOn) ...[
          _Field(label: 'Текст кнопки', initial: d.ctaLabelRu, max: 30, onChanged: (v) => _changed(() => d.ctaLabelRu = v)),
          _Field(
            label: 'Текст кнопки (KK)',
            initial: d.ctaLabelKk,
            max: 30,
            warn: () => kkMissing(d.ctaLabelRu, d.ctaLabelKk),
            onChanged: (v) => _changed(() => d.ctaLabelKk = v),
          ),
          const SizedBox(height: 4),
          const Text('Кнопка открывает', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          BannerTargetEditor(
            target: d.cta,
            kinds: BannerActionKind.ctaKinds,
            repo: widget.repo,
            stores: widget.stores,
            onChanged: widget.onChanged,
          ),
        ],
        const SizedBox(height: 12),
        // Live: redrawn on every keystroke above.
        Center(
          child: Container(
            key: const ValueKey('info-live-preview'),
            width: 360,
            height: 520,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.grey.shade400, width: 6),
            ),
            child: BannerInfoPreview(info: d, heroFile: widget.heroFile, heroUrl: widget.heroUrl),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            key: const ValueKey('info-preview'),
            onPressed: _preview,
            icon: const Icon(Icons.open_in_full),
            label: const Text('Во весь экран, RU и KK'),
          ),
        ),
      ],
    );
  }

  Widget _blockCard(int i) {
    final b = d.blocks[i];
    final (IconData icon, String title) = switch (b.kind) {
      InfoBlockKind.heading => (Icons.title, 'Подзаголовок'),
      InfoBlockKind.paragraph => (Icons.notes, 'Текст'),
      InfoBlockKind.bullets => (Icons.format_list_bulleted, 'Список: один пункт на строку'),
      InfoBlockKind.image => (Icons.image_outlined, 'Картинка'),
    };
    final multi = b.kind == InfoBlockKind.paragraph || b.kind == InfoBlockKind.bullets;
    final max = switch (b.kind) {
      InfoBlockKind.heading => 80,
      InfoBlockKind.paragraph => 1500,
      _ => 2600,
    };
    return Card(
      key: ObjectKey(b),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Expanded(child: Text('${i + 1}. $title', style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(
              tooltip: 'Выше',
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: i == 0 ? null : () => _changed(() => d.blocks.insert(i - 1, d.blocks.removeAt(i))),
            ),
            IconButton(
              tooltip: 'Удалить блок',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _changed(() => d.blocks.removeAt(i)),
            ),
          ]),
          if (b.kind == InfoBlockKind.image)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(imageUrl: b.url, height: 140, width: double.infinity, fit: BoxFit.cover),
              ),
            )
          else ...[
            _Field(label: 'RU', initial: b.textRu, max: max, multi: multi, onChanged: (v) => _changed(() => b.textRu = v)),
            _Field(
              label: 'KK',
              initial: b.textKk,
              max: max,
              multi: multi,
              warn: () => kkMissing(b.textRu, b.textKk),
              onChanged: (v) => _changed(() => b.textKk = v),
            ),
          ],
        ]),
      ),
    );
  }
}

/// A text field that owns its controller (blocks come and go).
class _Field extends StatefulWidget {
  const _Field({
    super.key,
    required this.label,
    required this.initial,
    required this.max,
    required this.onChanged,
    this.multi = false,
    this.warn,
  });

  final String label;
  final String initial;
  final int max;
  final bool multi;
  final ValueChanged<String> onChanged;
  final String? Function()? warn;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: TextField(
        controller: _c,
        maxLength: widget.max,
        minLines: widget.multi ? 2 : 1,
        maxLines: widget.multi ? 8 : 1,
        onChanged: (v) {
          widget.onChanged(v);
          setState(() {});
        },
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          counterText: '',
          helperText: widget.warn?.call(),
          helperStyle: const TextStyle(color: Color(0xFFB26A00)),
        ),
      ),
    );
  }
}

class _InfoPreviewPage extends StatefulWidget {
  const _InfoPreviewPage({required this.info, this.heroFile, this.heroUrl});
  final BannerInfoDraft info;
  final File? heroFile;
  final String? heroUrl;

  @override
  State<_InfoPreviewPage> createState() => _InfoPreviewPageState();
}

class _InfoPreviewPageState extends State<_InfoPreviewPage> {
  bool _kk = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Так увидит покупатель'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('RU')), ButtonSegment(value: true, label: Text('KK'))],
              selected: {_kk},
              onSelectionChanged: (s) => setState(() => _kk = s.first),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: BannerInfoPreview(info: widget.info, kk: _kk, heroFile: widget.heroFile, heroUrl: widget.heroUrl),
        ),
      ),
    );
  }
}
