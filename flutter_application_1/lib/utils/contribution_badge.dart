import 'dart:math' as math;

import 'package:flutter/material.dart';

class ContributionBadge {
  final String id;
  final String label;
  final String description;
  final int minContributions;
  final int? nextThreshold;
  final Color color;
  final IconData icon;
  final bool isPremiumReward;

  const ContributionBadge({
    required this.id,
    required this.label,
    required this.description,
    required this.minContributions,
    required this.nextThreshold,
    required this.color,
    required this.icon,
    this.isPremiumReward = false,
  });
}

class ContributionBadgeCatalog {
  static const List<ContributionBadge> tiers = [
    ContributionBadge(
      id: 'newcomer',
      label: 'Newcomer',
      description: 'Start sharing resources with your peers.',
      minContributions: 0,
      nextThreshold: 1,
      color: Color(0xFF64748B),
      icon: Icons.star_border_rounded,
    ),
    ContributionBadge(
      id: 'helper',
      label: 'Helper',
      description: 'First contribution posted.',
      minContributions: 1,
      nextThreshold: 5,
      color: Color(0xFF0EA5E9),
      icon: Icons.thumb_up_alt_rounded,
    ),
    ContributionBadge(
      id: 'scholar',
      label: 'Scholar',
      description: 'Shared at least five resources.',
      minContributions: 5,
      nextThreshold: 10,
      color: Color(0xFF6366F1),
      icon: Icons.menu_book_rounded,
    ),
    ContributionBadge(
      id: 'pro',
      label: 'Pro',
      description: 'Reached 10 contributions. You\'re a Pro!',
      minContributions: 10,
      nextThreshold: 15,
      color: Color(0xFF10B981),
      icon: Icons.verified_rounded,
      isPremiumReward: true,
    ),
    ContributionBadge(
      id: 'mentor',
      label: 'Mentor',
      description: 'Consistent contributor with 15+ resources.',
      minContributions: 15,
      nextThreshold: 35,
      color: Color(0xFF8B5CF6),
      icon: Icons.psychology_alt_rounded,
    ),
    ContributionBadge(
      id: 'legend',
      label: 'Legend',
      description: 'Top contributor with 35+ resources.',
      minContributions: 35,
      nextThreshold: 75,
      color: Color(0xFFF59E0B),
      icon: Icons.workspace_premium_rounded,
    ),
    ContributionBadge(
      id: 'hall_of_fame',
      label: 'Hall of Fame',
      description: 'Elite contributor with 75+ resources.',
      minContributions: 75,
      nextThreshold: null,
      color: Color(0xFFEF4444),
      icon: Icons.military_tech_rounded,
    ),
  ];

  static ContributionBadge resolve(int contributionCount) {
    for (int i = tiers.length - 1; i >= 0; i--) {
      if (contributionCount >= tiers[i].minContributions) {
        return tiers[i];
      }
    }
    return tiers.first;
  }

  static double progressToNext(int contributionCount) {
    final current = resolve(contributionCount);
    final next = current.nextThreshold;
    if (next == null) return 1;

    final span = math.max(1, next - current.minContributions);
    final progressed = contributionCount - current.minContributions;
    return (progressed / span).clamp(0.0, 1.0);
  }
}
