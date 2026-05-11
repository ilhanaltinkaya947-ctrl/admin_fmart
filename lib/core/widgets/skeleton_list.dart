import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton placeholder for list-style loading states across the admin
/// app. Replaces bare `CircularProgressIndicator` centred on empty
/// screens with row-shaped shimmer cards so the perceived load feels
/// snappier and the layout doesn't shift when data arrives.
class SkeletonList extends StatelessWidget {
  final int rows;
  final double rowHeight;
  final EdgeInsetsGeometry padding;
  final bool hasAvatar;

  const SkeletonList({
    super.key,
    this.rows = 6,
    this.rowHeight = 76,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.hasAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    final base = Colors.grey.shade300;
    final highlight = Colors.grey.shade100;

    return ListView.separated(
      padding: padding,
      itemCount: rows,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          height: rowHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (hasAvatar) ...[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 160,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
