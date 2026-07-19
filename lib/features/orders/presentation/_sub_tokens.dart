import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Local mirror of the customer app's `T` design tokens, scoped to the
/// substitution studio. The admin app is stock Material 3 seeded with brand
/// orange, so reading `Theme.colorScheme` for SURFACES leaks a washed-out peach
/// tint onto the studio. These flat, intentional ink-on-white values keep the
/// studio calm and premium — matching the customer app. Do NOT read
/// `colorScheme` for surfaces in the studio; use `ST.*`.
class ST {
  ST._();

  // Ink
  static const ink = Color(0xFF17181A);
  static const ink2 = Color(0xFF70747A);
  static const ink3 = Color(0xFFA8ACB2);

  // Surfaces — the only three, plus hairline
  static const bg = Color(0xFFF6F6F7); // studio canvas / left browse pane
  static const card = Colors.white; // right pane + cards + header
  static const line = Color(0xFFECEDEF); // hairline dividers/borders
  static const well = Color(0xFFF3F4F5); // search fill, note well, thumbs

  // Brand + semantic (punctuation only — never a surface wash)
  static const brand = Color(0xFFEE6F00);
  static const milk = Color(0xFFFFF1E4);
  static const green = Color(0xFF18A957);
  static const greenMilk = Color(0xFFE9F7EF);

  // Radii scale
  static const rSheet = 28.0;
  static const rCard = 20.0;
  static const rMd = 16.0;
  static const rInner = 14.0;
  static const rChip = 8.0;

  // Type ramp
  static TextStyle title(double s, {Color c = ink}) => TextStyle(
      fontSize: s, fontWeight: FontWeight.w700, color: c, letterSpacing: -0.3, height: 1.2);
  static TextStyle body(double s, {Color c = ink, FontWeight w = FontWeight.w500}) =>
      TextStyle(fontSize: s, fontWeight: w, color: c, height: 1.35);
  static TextStyle label(double s, {Color c = ink2}) =>
      TextStyle(fontSize: s, fontWeight: FontWeight.w600, color: c, height: 1.2);
  static TextStyle price(double s, {Color c = ink}) => TextStyle(
      fontSize: s,
      fontWeight: FontWeight.w800,
      color: c,
      letterSpacing: -0.4,
      fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Mirror of the customer app's PressableScale — a tactile scale + haptic on
/// press, since the admin app has no equivalent. Wrap cards / CTAs so taps feel
/// intentional instead of dead.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  const Pressable(
      {super.key, required this.child, this.onTap, this.scale = 0.97, this.haptic = true});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
