import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../../core/api/api_client.dart';

class MediaRepository {
  final ApiClient api;

  MediaRepository({required this.api});

  Future<String?> uploadProductImage({
    required int productId,
    required File imageFile,
  }) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      imageFile.absolute.path,
      minWidth: 1024,
      minHeight: 1024,
      quality: 85,
    );

    if (compressed == null) return null;

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        compressed,
        filename: 'product_$productId.jpg',
      ),
    });

    final resp = await api.dio.post(
      '/gw/catalog/products/admin/$productId/upload-image',
      data: formData,
    );

    return resp.data['image_url'] as String?;
  }
}
