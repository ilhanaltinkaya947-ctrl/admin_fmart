import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
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
  bool _active = true;
  File? _pickedImage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.banner;
    if (b != null) {
      _titleCtrl.text = b.title ?? '';
      _linkCtrl.text = b.linkUrl ?? '';
      _active = b.active;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      // We don't pre-resize here — backend validates exact dimensions.
    );
    if (picked == null || !mounted) return;
    setState(() => _pickedImage = File(picked.path));
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

    setState(() => _saving = true);
    try {
      final cubit = context.read<BannersCubit>();
      if (isNew) {
        await cubit.create(
          imageFile: _pickedImage!,
          title: _titleCtrl.text.trim(),
          linkUrl: _linkCtrl.text.trim(),
          active: _active,
        );
      } else {
        await cubit.update(
          id: widget.banner!.id,
          imageFile: _pickedImage,
          title: _titleCtrl.text.trim(),
          linkUrl: _linkCtrl.text.trim(),
          active: _active,
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
