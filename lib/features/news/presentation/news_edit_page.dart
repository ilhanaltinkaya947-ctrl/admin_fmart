import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../stores/data/stores_repository.dart';
import '../../stores/models/store_models.dart';
import '../data/news_models.dart';
import '../data/news_repository.dart';
import '../state/news_cubit.dart';
import 'news_card_preview.dart';

/// Write or edit a «Новости» post (28.10). The card at the top is the
/// customer's card, live, in Russian or Kazakh.
class NewsEditPage extends StatefulWidget {
  final NewsPost? post;
  final StoresRepository storesRepo;
  const NewsEditPage({super.key, this.post, required this.storesRepo});

  @override
  State<NewsEditPage> createState() => _NewsEditPageState();
}

class _NewsEditPageState extends State<NewsEditPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _titleKk = TextEditingController();
  final _bodyKk = TextEditingController();
  File? _image;
  bool _removeImage = false;
  bool _active = true;
  bool _pinned = false;
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _startsCleared = false;
  bool _endsCleared = false;
  final Set<int> _stores = {};
  List<StoreDto> _allStores = const [];
  bool _previewKk = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    if (p != null) {
      _title.text = p.title;
      _body.text = p.body ?? '';
      _titleKk.text = p.titleKk ?? '';
      _bodyKk.text = p.bodyKk ?? '';
      _active = p.active;
      _pinned = p.pinned;
      _startsAt = p.startsAt;
      _endsAt = p.endsAt;
      _stores.addAll(p.storeIds);
    }
    for (final c in [_title, _body, _titleKk, _bodyKk]) {
      c.addListener(() => setState(() {}));
    }
    widget.storesRepo.getStores().then((s) {
      if (mounted) setState(() => _allStores = s);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _titleKk, _bodyKk]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Из галереи'),
            onTap: () => Navigator.of(sheetCtx).pop('gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Из файлов'),
            subtitle: const Text('iCloud Drive, Файлы, и т.д.'),
            onTap: () => Navigator.of(sheetCtx).pop('files'),
          ),
          if (_image != null || (widget.post?.imageUrl != null && !_removeImage))
            ListTile(
              leading: const Icon(Icons.hide_image_outlined),
              title: const Text('Без картинки'),
              onTap: () => Navigator.of(sheetCtx).pop('none'),
            ),
          const SizedBox(height: 4),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'none') {
      setState(() {
        _image = null;
        _removeImage = true;
      });
      return;
    }
    File? file;
    if (choice == 'gallery') {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null) file = File(picked.path);
    } else {
      // FileType.custom so iOS opens the Files app, not Photos (see banners).
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic'],
      );
      final path = result?.files.single.path;
      if (path != null && path.isNotEmpty) file = File(path);
    }
    if (file == null || !mounted) return;
    setState(() {
      _image = file;
      _removeImage = false;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startsAt : _endsAt;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current ?? now));
    if (!mounted) return;
    // Time picker cancelled: «С» today = now (not 00:00, which would date
    // the post hours back), «До» = 23:59 of that day (not a day early).
    final today = DateTime(now.year, now.month, now.day) == DateTime(date.year, date.month, date.day);
    final h = time?.hour ?? (isStart ? (today ? now.hour : 0) : 23);
    final m = time?.minute ?? (isStart ? (today ? now.minute : 0) : 59);
    final picked = DateTime(date.year, date.month, date.day, h, m);
    setState(() {
      if (isStart) {
        _startsAt = picked;
        _startsCleared = false;
      } else {
        _endsAt = picked;
        _endsCleared = false;
      }
    });
  }

  void _snack(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? const Color(0xFFD32F2F) : null),
      );

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) return _snack('Напишите заголовок', error: true);
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      return _snack('Дата окончания должна быть позже даты начала', error: true);
    }
    setState(() => _saving = true);
    final repo = context.read<NewsCubit>().repo;
    try {
      final stores = _stores.toList()..sort();
      final p = widget.post;
      if (p == null) {
        await repo.create(
          title: title,
          body: _body.text.trim(),
          titleKk: _titleKk.text.trim(),
          bodyKk: _bodyKk.text.trim(),
          imageFile: _image,
          storeIds: stores,
          active: _active,
          pinned: _pinned,
          startsAt: _startsAt,
          endsAt: _endsAt,
        );
      } else {
        await repo.update(
          id: p.id,
          title: title,
          body: _body.text.trim(),
          titleKk: _titleKk.text.trim(),
          bodyKk: _bodyKk.text.trim(),
          imageFile: _image,
          removeImage: _removeImage,
          storeIds: stores,
          active: _active,
          pinned: _pinned,
          startsAt: _startsAt,
          clearStartsAt: _startsCleared,
          endsAt: _endsAt,
          clearEndsAt: _endsCleared,
        );
      }
      if (!mounted) return;
      await context.read<NewsCubit>().load();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on NewsValidationException catch (e) {
      if (mounted) _snack(e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      if (widget.post == null) {
        // The POST may have reached the server and only the answer got lost:
        // a second Save would publish the post twice (review 28.10). Show the
        // list as it is now instead of inviting a retry here.
        final messenger = ScaffoldMessenger.of(context);
        final nav = Navigator.of(context);
        await context.read<NewsCubit>().load();
        messenger.showSnackBar(const SnackBar(
          content: Text('Нет ответа от сервера. Новость могла сохраниться: проверьте список, прежде чем создавать снова.'),
          duration: Duration(seconds: 6),
        ));
        nav.pop(false);
        return;
      }
      _snack('Не удалось сохранить');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final kkTitle = _titleKk.text.trim();
    final previewTitle = _previewKk && kkTitle.isNotEmpty ? kkTitle : _title.text.trim();
    final previewBody = _previewKk && kkTitle.isNotEmpty ? _bodyKk.text.trim() : _body.text.trim();
    final shownUrl = _removeImage ? null : widget.post?.imageUrl;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F7),
      appBar: AppBar(
        title: Text(widget.post == null ? 'Новая новость' : 'Новость'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Сохранить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(children: [
            const Expanded(
              child: Text('Так увидит клиент', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF70747A))),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('RU')),
                ButtonSegment(value: true, label: Text('KK')),
              ],
              selected: {_previewKk},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _previewKk = s.first),
            ),
          ]),
          const SizedBox(height: 8),
          Center(
            child: NewsCardPreview(
              title: previewTitle,
              body: previewBody,
              imageFile: _image,
              imageUrl: shownUrl,
              dateLabel: newsDateLabel(_startsAt ?? DateTime.now()),
            ),
          ),
          if (_previewKk && kkTitle.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Нет казахского текста: клиенты на казахском увидят русский.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF9A6300))),
            ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.image_outlined),
            label: Text(_image != null || shownUrl != null ? 'Заменить картинку' : 'Добавить картинку'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Как для баннеров: от 1200×700, соотношение 1,5–1,7. Текст на картинке держите в центре: края слегка обрезаются.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF70747A))),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: kNewsTitleMax,
            decoration: const InputDecoration(labelText: 'Заголовок', hintText: 'Например: Вечером −20% на торты'),
          ),
          TextField(
            controller: _body,
            maxLength: kNewsBodyMax,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Текст', hintText: 'Коротко: что, где, до какого числа'),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Қазақша (необязательно)'),
            initiallyExpanded: _titleKk.text.isNotEmpty,
            children: [
              TextField(controller: _titleKk, maxLength: kNewsTitleMax, decoration: const InputDecoration(labelText: 'Тақырып')),
              TextField(
                controller: _bodyKk,
                maxLength: kNewsBodyMax,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Мәтін'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Магазины', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ChoiceChip(
              label: const Text('Все магазины'),
              selected: _stores.isEmpty,
              onSelected: (_) => setState(_stores.clear),
            ),
            for (final s in _allStores)
              FilterChip(
                label: Text(s.storeName),
                selected: _stores.contains(s.storeId),
                onSelected: (v) => setState(() => v ? _stores.add(s.storeId) : _stores.remove(s.storeId)),
              ),
            // The post's stores stay visible even if the store list failed to load.
            for (final id in _stores.where((id) => !_allStores.any((s) => s.storeId == id)))
              FilterChip(
                label: Text('Магазин $id'),
                selected: true,
                onSelected: (_) => setState(() => _stores.remove(id)),
              ),
          ]),
          const SizedBox(height: 16),
          const Text('Когда показывать', style: TextStyle(fontWeight: FontWeight.w600)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('С'),
            subtitle: Text(_startsAt == null ? 'Сразу после сохранения' : _fmt(_startsAt!)),
            trailing: _startsAt == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _startsAt = null;
                      _startsCleared = true;
                    }),
                  ),
            onTap: () => _pickDate(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('До'),
            subtitle: Text(_endsAt == null ? 'Без окончания' : _fmt(_endsAt!)),
            trailing: _endsAt == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _endsAt = null;
                      _endsCleared = true;
                    }),
                  ),
            onTap: () => _pickDate(isStart: false),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Закрепить сверху'),
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Показывать клиентам'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ],
      ),
    );
  }
}
