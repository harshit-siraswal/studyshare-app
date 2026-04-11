import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef CollapsibleProfileHeaderBuilder = Widget Function(
  BuildContext context,
  double collapseProgress,
);

class CollapsibleProfileHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double collapsedHeight;
  final Color backgroundColor;
  final CollapsibleProfileHeaderBuilder builder;

  const CollapsibleProfileHeaderDelegate({
    required this.expandedHeight,
    required this.collapsedHeight,
    required this.backgroundColor,
    required this.builder,
  })  : assert(expandedHeight >= collapsedHeight),
        assert(expandedHeight > 0),
        assert(collapsedHeight > 0);

  @override
  double get maxExtent => expandedHeight;

  @override
  double get minExtent => collapsedHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final collapseRange = math.max(1.0, maxExtent - minExtent);
    final collapseProgress = (shrinkOffset / collapseRange).clamp(0.0, 1.0);

    return Material(
      color: backgroundColor,
      child: SizedBox.expand(
        child: builder(context, collapseProgress),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant CollapsibleProfileHeaderDelegate oldDelegate) {
    return expandedHeight != oldDelegate.expandedHeight ||
        collapsedHeight != oldDelegate.collapsedHeight ||
        backgroundColor != oldDelegate.backgroundColor ||
        builder != oldDelegate.builder;
  }
}