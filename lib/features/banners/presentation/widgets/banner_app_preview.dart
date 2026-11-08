import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/banner_action_draft.dart';

/// The customer app's colours (fmart-flutter T tokens), so the preview reads
/// exactly as the slide and page will.
class _App {
  static const ink = Color(0xFF17181A);
  static const ink2 = Color(0xFF70747A);
  static const brand = Color(0xFFEE6F00);
  static const well = Color(0xFFF3F4F5);
  static const line = Color(0xFFECEDEF);
}

/// The pill word the customer app draws (08.11): «Подробнее» on an info page
/// banner, «Смотреть» on every banner that sells something.
String bannerPillText(BannerActionKind kind) =>
    kind == BannerActionKind.info ? 'Подробнее' : 'Смотреть';

/// One home slide as the customer app draws it: 16:8, rounded, the badge top
/// left and the pill bottom right, both only on a banner with an action.
class BannerSlidePreview extends StatelessWidget {
  const BannerSlidePreview({
    super.key,
    this.file,
    this.url,
    required this.kind,
    this.badge = '',
  });

  final File? file;
  final String? url;
  final BannerActionKind kind;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final tappable = kind != BannerActionKind.none;
    Widget art;
    if (file != null) {
      art = Image.file(file!, fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty) {
      art = CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const ColoredBox(color: _App.well));
    } else {
      art = const ColoredBox(color: _App.well, child: Center(child: Icon(Icons.image_outlined, color: _App.ink2)));
    }
    return AspectRatio(
      aspectRatio: 16 / 8,
      child: ClipRRect(
        // 28 on a ~370 pt wide slide in the app: same proportion here.
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            art,
            if (tappable && badge.trim().isNotEmpty)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: _App.brand, borderRadius: BorderRadius.circular(999)),
                  child: Text(badge.trim(),
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            if (tappable)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(11, 5, 7, 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: _App.ink.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(bannerPillText(kind),
                        style: const TextStyle(color: _App.ink, fontSize: 12, fontWeight: FontWeight.w700)),
                    const Icon(Icons.chevron_right, size: 14, color: _App.ink),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The info page as the customer app lays it out (hero, title, blocks,
/// button), RU or KK. Empty KK fields show the RU text, as the app does.
class BannerInfoPreview extends StatelessWidget {
  const BannerInfoPreview({super.key, required this.info, this.kk = false, this.heroFile, this.heroUrl});

  final BannerInfoDraft info;
  final bool kk;
  final File? heroFile;
  final String? heroUrl;

  String _pick(String ru, String k) => (kk && k.trim().isNotEmpty) ? k.trim() : ru.trim();

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(fontSize: 16, color: _App.ink, height: 1.45);
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                if (heroFile != null || (heroUrl ?? '').isNotEmpty) ...[
                  BannerSlidePreview(file: heroFile, url: heroUrl, kind: BannerActionKind.none),
                  const SizedBox(height: 20),
                ],
                Text(_pick(info.titleRu, info.titleKk).isEmpty ? 'Заголовок страницы' : _pick(info.titleRu, info.titleKk),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _App.ink, height: 1.12)),
                const SizedBox(height: 8),
                for (final b in info.blocks) _block(b, body),
              ],
            ),
          ),
          if (info.ctaOn)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _App.line))),
              child: Container(
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _App.brand, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  _pick(info.ctaLabelRu, info.ctaLabelKk).isEmpty ? 'Текст кнопки' : _pick(info.ctaLabelRu, info.ctaLabelKk),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _block(InfoBlockDraft b, TextStyle body) {
    switch (b.kind) {
      case InfoBlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 2),
          child: Text(_pick(b.textRu, b.textKk),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _App.ink)),
        );
      case InfoBlockKind.paragraph:
        return Padding(padding: const EdgeInsets.only(top: 10), child: Text(_pick(b.textRu, b.textKk), style: body));
      case InfoBlockKind.bullets:
        final items = InfoBlockDraft.lines(kk && InfoBlockDraft.lines(b.textKk).isNotEmpty ? b.textKk : b.textRu);
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(children: [
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 12),
                    child: Container(width: 6, height: 6,
                        decoration: const BoxDecoration(color: _App.brand, shape: BoxShape.circle)),
                  ),
                  Expanded(child: Text(it, style: body)),
                ]),
              ),
          ]),
        );
      case InfoBlockKind.image:
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: b.url.isEmpty
                ? const AspectRatio(aspectRatio: 16 / 10, child: ColoredBox(color: _App.well))
                : CachedNetworkImage(imageUrl: b.url, fit: BoxFit.fitWidth, width: double.infinity),
          ),
        );
    }
  }
}
