import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../data/banner_models.dart';
import '../data/banners_repository.dart';
import '../state/banners_cubit.dart';

/// Create or edit a single banner.
///
/// On Save: validates form fields, sends multipart to backend. The backend
/// also enforces dimensions/ratio (1.5–1.7) and returns 400 with a Russian
/// message if the image is wrong size — that surfaces here as a snackbar
/// without crashing.
class BannerEditPage extends StatefulWidget {
  final BannerItem? banner;
  const BannerEditPage({super.key, this.banner});

  @override
  State<BannerEditPage> createState() => _BannerEditPageState();
}

class _BannerEditPageState extends State<BannerEditPage> {
  final _titleCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  bool _active = true;
  File? _pickedImage;
  bool _saving = false;
  DateTime? _startsAt;
  DateTime? _endsAt;
  // Tracked separately from the value so "clear an existing date" is
  // expressible: null + touched means delete it, null + untouched means
  // "was never set, send nothing".
  bool _startsCleared = false;
  bool _endsCleared = false;

  @override
  void initState() {
    super.initState();
    final b = widget.banner;
    if (b != null) {
      _titleCtrl.text = b.title ?? '';
      _linkCtrl.text = b.linkUrl ?? '';
      _positionCtrl.text = '${b.sortOrder}';
      _active = b.active;
      _startsAt = b.startsAt;
      _endsAt = b.endsAt;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _linkCtrl.dispose();
    _positionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final current = isStart ? _startsAt : _endsAt;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (!mounted) return;
    final picked = DateTime(
      date.year, date.month, date.day,
      time?.hour ?? 0, time?.minute ?? 0,
    );
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

  /// Reject an impossible window before the round-trip. The backend enforces
  /// the same rule and returns 400, but catching it here keeps the operator's
  /// input on screen instead of bouncing them out of the form.
  String? _windowError() {
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      return 'Дата окончания должна быть позже даты начала';
    }
    return null;
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _pick() async {
    // Two sources because iOS image_picker only reaches the Photos library —
    // banner artwork often arrives via Telegram/email and lives in Files/iCloud
    // Drive. file_picker covers those.
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    File? file;
    if (choice == 'gallery') {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // No pre-resize — backend validates exact dimensions.
      );
      if (picked != null) file = File(picked.path);
    } else if (choice == 'files') {
      // FileType.image opens UIImagePickerController which lands in
      // Photos, not Files — defeats the whole point of the "Из файлов"
      // option. FileType.custom with an explicit extension whitelist
      // forces UIDocumentPickerViewController = iOS Files app.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic'],
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path != null && path.isNotEmpty) file = File(path);
    }
    if (file == null || !mounted) return;
    setState(() => _pickedImage = file);
  }

  Future<void> _save() async {
    if (_saving) return;

    // For new banners, an image is required. For edits the image is optional.
    final isNew = widget.banner == null;
    if (isNew && _pickedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите изображение')),
      );
      return;
    }

    // Normalise + light-validate the link URL: prefix https:// if the
    // operator typed "google.com" without a scheme, and reject obvious
    // garbage so customers don't tap dead banners. Empty link is fine —
    // banner without a tap target is supported.
    final rawLink = _linkCtrl.text.trim();
    String? normalisedLink;
    if (rawLink.isNotEmpty) {
      var l = rawLink;
      if (!l.startsWith('http://') && !l.startsWith('https://')) {
        l = 'https://$l';
      }
      final uri = Uri.tryParse(l);
      if (uri == null || !uri.hasAuthority || (uri.host).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ссылка указана некорректно')),
        );
        return;
      }
      normalisedLink = l;
    }

    final windowErr = _windowError();
    if (windowErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(windowErr), backgroundColor: const Color(0xFFD32F2F)),
      );
      return;
    }

    // Blank means "let the backend append it"; only an explicit number pins a
    // position. Guard against nonsense like -5 or "abc".
    final rawPosition = _positionCtrl.text.trim();
    int? position;
    if (rawPosition.isNotEmpty) {
      final parsed = int.tryParse(rawPosition);
      if (parsed == null || parsed < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Позиция должна быть целым числом от 0')),
        );
        return;
      }
      position = parsed;
    }

    setState(() => _saving = true);
    try {
      final cubit = context.read<BannersCubit>();
      if (isNew) {
        await cubit.create(
          imageFile: _pickedImage!,
          title: _titleCtrl.text.trim(),
          linkUrl: normalisedLink ?? '',
          sortOrder: position,
          active: _active,
          startsAt: _startsAt,
          endsAt: _endsAt,
        );
      } else {
        await cubit.update(
          id: widget.banner!.id,
          imageFile: _pickedImage,
          title: _titleCtrl.text.trim(),
          linkUrl: normalisedLink ?? '',
          sortOrder: position,
          active: _active,
          startsAt: _startsAt,
          clearStartsAt: _startsCleared,
          endsAt: _endsAt,
          clearEndsAt: _endsCleared,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BannerValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: const Color(0xFFD32F2F)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.banner == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'Новый баннер' : 'Редактирование')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ImagePickerCard(
            picked: _pickedImage,
            existingUrl: widget.banner?.imageUrl,
            onPick: _pick,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFFEE6F00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Рекомендуемый размер: 1300 × 800. '
                    'Соотношение сторон 1.5–1.7. Лишнее обрежется.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Название (для админки)',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _linkCtrl,
            decoration: const InputDecoration(
              labelText: 'Ссылка (необязательно)',
              hintText: 'https://...',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Показывать на главной'),
            contentPadding: EdgeInsets.zero,
          ),
          TextField(
            controller: _positionCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Позиция (0 — самый первый)',
              helperText: 'Оставьте пустым, чтобы баннер встал в конец',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Показ по расписанию',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Необязательно. Без дат баннер показывается пока включён '
            'переключатель выше.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          _ScheduleRow(
            label: 'Начало показа',
            value: _startsAt == null ? null : _fmt(_startsAt!),
            onPick: () => _pickDateTime(isStart: true),
            onClear: _startsAt == null && !_startsCleared
                ? null
                : () => setState(() {
                      _startsAt = null;
                      _startsCleared = true;
                    }),
          ),
          const SizedBox(height: 8),
          _ScheduleRow(
            label: 'Конец показа',
            value: _endsAt == null ? null : _fmt(_endsAt!),
            onPick: () => _pickDateTime(isStart: false),
            onClear: _endsAt == null && !_endsCleared
                ? null
                : () => setState(() {
                      _endsAt = null;
                      _endsCleared = true;
                    }),
          ),
          if (_windowError() != null) ...[
            const SizedBox(height: 8),
            Text(
              _windowError()!,
              style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: const Text('Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePickerCard extends StatelessWidget {
  final File? picked;
  final String? existingUrl;
  final VoidCallback onPick;

  const _ImagePickerCard({
    required this.picked,
    required this.existingUrl,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 13 / 8,
      child: Material(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPick,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _previewLayer(),
          ),
        ),
      ),
    );
  }

  Widget _previewLayer() {
    if (picked != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(picked!, fit: BoxFit.cover),
          const Positioned(
            right: 8,
            top: 8,
            child: _ChangeBadge(),
          ),
        ],
      );
    }
    if (existingUrl != null && existingUrl!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(imageUrl: existingUrl!, fit: BoxFit.cover),
          const Positioned(
            right: 8,
            top: 8,
            child: _ChangeBadge(),
          ),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text(
            'Выбрать изображение',
            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text('Изменить', style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

/// One row of the publish-window editor: a label, the chosen timestamp (or a
/// placeholder), a pick button, and a clear button that only appears once
/// there is something to clear.
class _ScheduleRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _ScheduleRow({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ?? 'Не задано',
                    style: TextStyle(
                      fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
                      color: value == null ? Colors.grey.shade600 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Очистить',
                icon: const Icon(Icons.clear, size: 20),
                onPressed: onClear,
              ),
            const Icon(Icons.calendar_month_outlined, size: 20),
          ],
        ),
      ),
    );
  }
}
