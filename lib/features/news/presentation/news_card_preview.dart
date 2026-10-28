import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The customer app's «Новости» card, drawn the same way (28.10): image at
/// the carousel's 1.84 crop, title on at most 2 lines, text on 2 lines (the
/// rest opens on tap), the date under it. What the admin sees here is the
/// layout the customer gets.
class NewsCardPreview extends StatelessWidget {
  final String title;
  final String body;
  final File? imageFile;
  final String? imageUrl;
  final String dateLabel;
  final double width;

  const NewsCardPreview({
    super.key,
    required this.title,
    required this.body,
    required this.dateLabel,
    this.imageFile,
    this.imageUrl,
    this.width = 343,
  });

  @override
  Widget build(BuildContext context) {
    Widget? image;
    if (imageFile != null) {
      image = Image.file(imageFile!, fit: BoxFit.cover);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      image = CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover);
    }
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECEDEF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null) AspectRatio(aspectRatio: 1.84, child: image),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Заголовок новости' : keepNumbersTogether(title),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: title.isEmpty ? const Color(0xFFA8ACB2) : const Color(0xFF17181A),
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    keepNumbersTogether(body),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.35, color: Color(0xFF70747A)),
                  ),
                ],
                const SizedBox(height: 4),
                Text(dateLabel, style: const TextStyle(fontSize: 12, color: Color(0xFFA8ACB2))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «7 000 ₸» must never break between «7» and «000»: thousands spaces and
/// the space before ₸/%/г/кг become non-breaking (the customer card does the
/// same, so the preview matches).
String keepNumbersTogether(String s) => s
    .replaceAllMapped(RegExp(r'(\d) (?=\d{3}(\D|\$))'), (m) => '${m[1]}\u00A0')
    .replaceAllMapped(RegExp(r'(\d) (?=(₸|%|г|кг|мл|л)(\s|\$|[.,!?)]))'), (m) => '${m[1]}\u00A0');

String newsDateLabel(DateTime d) {
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (day == today) return 'Сегодня, $hm';
  if (day == today.subtract(const Duration(days: 1))) return 'Вчера, $hm';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}, $hm';
}
