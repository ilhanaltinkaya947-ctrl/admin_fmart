import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/media_repository.dart';

class ProductImageUpload extends StatefulWidget {
  final int productId;
  final String? currentImageUrl;
  final MediaRepository mediaRepo;
  final ValueChanged<String>? onUploaded;

  const ProductImageUpload({
    super.key,
    required this.productId,
    required this.mediaRepo,
    this.currentImageUrl,
    this.onUploaded,
  });

  @override
  State<ProductImageUpload> createState() => _ProductImageUploadState();
}

class _ProductImageUploadState extends State<ProductImageUpload> {
  bool _uploading = false;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.currentImageUrl;
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
    );

    if (picked == null) return;

    setState(() => _uploading = true);

    try {
      final url = await widget.mediaRepo.uploadProductImage(
        productId: widget.productId,
        imageFile: File(picked.path),
      );

      if (url != null) {
        setState(() => _imageUrl = url);
        widget.onUploaded?.call(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Фото загружено'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _uploading = false);
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2048,
      maxHeight: 2048,
    );

    if (picked == null) return;

    setState(() => _uploading = true);

    try {
      final url = await widget.mediaRepo.uploadProductImage(
        productId: widget.productId,
        imageFile: File(picked.path),
      );

      if (url != null) {
        setState(() => _imageUrl = url);
        widget.onUploaded?.call(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Фото загружено'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _uploading
              ? const Center(child: CircularProgressIndicator())
              : _imageUrl != null && _imageUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: _imageUrl!,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.image_outlined, size: 48, color: Colors.grey),
                    ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _pickAndUpload,
                icon: const Icon(Icons.photo_library),
                label: const Text('Галерея'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Камера'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
