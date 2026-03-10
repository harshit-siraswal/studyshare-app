import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/resource.dart';

/// Multiplier mapping raw backend AI token units to a single user-visible
/// "AI token". Used by [AiTokenBudgetSnapshot] and token-display helpers to
/// convert between internal balances and the friendly counts shown in the UI.
/// Constraints: must be > 0; changing this value shifts every token count the
/// user sees, so coordinate with backend quota allocations.
const int kRawAiTokensPerVisibleToken = 2000;
const int _contributorPremiumThreshold = 10;
const Duration _contributorPremiumDuration = Duration(days: 30);

String normalizeSubscriptionTier(String? tier) {
  final normalized = tier?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return '';
  return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

bool isPremiumSubscriptionTier(String? tier) {
  final normalizedTier = normalizeSubscriptionTier(tier);
  if (normalizedTier.isEmpty) return false;

  const exactPremiumTiers = <String>{
    'pro',
    'premium',
    'max',
    'monthly',
    'quarterly',
    'yearly',
    'annual',
  };
  if (exactPremiumTiers.contains(normalizedTier)) {
    return true;
  }

  final tokens = normalizedTier
      .split('_')
      .where((token) => token.isNotEmpty)
      .toSet();
  if (tokens.isEmpty) return false;

  const premiumMarkers = <String>{'pro', 'premium', 'max'};
  if (tokens.any(premiumMarkers.contains)) {
    return true;
  }

  const paidCadenceMarkers = <String>{
    'monthly',
    'quarterly',
    'yearly',
    'annual',
  };
  const freeMarkers = <String>{'free', 'basic', 'trial', 'guest'};
  return tokens.any(paidCadenceMarkers.contains) &&
      !tokens.any(freeMarkers.contains);
}

int visibleAiTokensFromRaw(int rawTokenCount) {
  if (rawTokenCount <= 0) return 0;
  return math.max(1, rawTokenCount ~/ kRawAiTokensPerVisibleToken);
}

int visibleAiTokenShortfallFromRaw(
  int remainingRawTokens, {
  int requiredVisibleTokens = 1,
}) {
  return math.max(
    0,
    requiredVisibleTokens - visibleAiTokensFromRaw(remainingRawTokens),
  );
}

/// Normalized AI token budget values derived from the current user profile.
class AiTokenBudgetSnapshot {
  /// The raw base budget before any purchased boosts or premium multiplier.
  final int baseBudget;

  /// The free-plan budget after applying user-specific purchased boosts.
  final int freeBudget;

  /// The premium-plan budget for the same user scope.
  final int premiumBudget;

  /// The effective budget for the user's current active tier.
  final int currentBudget;

  /// Purchased/user-specific multiplier applied to the base budget.
  final int budgetMultiplier;

  /// Premium multiplier applied on top of the free-plan budget.
  final int premiumMultiplier;

  /// Whether the profile currently has active premium access.
  final bool isPremiumActive;

  const AiTokenBudgetSnapshot({
    required this.baseBudget,
    required this.freeBudget,
    required this.premiumBudget,
    required this.currentBudget,
    required this.budgetMultiplier,
    required this.premiumMultiplier,
    required this.isPremiumActive,
  });

  /// Builds a resilient token snapshot from a backend profile payload.
  factory AiTokenBudgetSnapshot.fromProfile(
    Map<String, dynamic> profile, {
    int defaultBudget = 40160,
  }) {
    final budgetFromApi = _toSafeInt(profile['ai_token_budget']);
    final baseBudgetFromApi = _toSafeInt(profile['ai_token_base_budget']);
    final rawBudgetMultiplier = math.max(
      1,
      _toSafeInt(profile['ai_token_budget_multiplier']),
    );
    final rawPremiumMultiplier = math.max(
      1,
      _toSafeInt(profile['ai_token_premium_multiplier']),
    );
    final premiumMultiplier = rawPremiumMultiplier > 1
        ? rawPremiumMultiplier
        : 10;

    final tier = normalizeSubscriptionTier(profile['subscription_tier']);
    final subscriptionEnd = DateTime.tryParse(
      profile['subscription_end_date']?.toString() ?? '',
    );
    final hasActiveSubscriptionWindow =
        subscriptionEnd != null &&
        subscriptionEnd.toUtc().isAfter(DateTime.now().toUtc());
    final isPremiumActive =
        hasActiveSubscriptionWindow && isPremiumSubscriptionTier(tier);
    final normalizedBudgetMultiplier =
        isPremiumActive && premiumMultiplier > 1
        ? math.max(1, (rawBudgetMultiplier / premiumMultiplier).round())
        : rawBudgetMultiplier;
    final inferredFreeBudget = baseBudgetFromApi > 0
        ? math.max(1, baseBudgetFromApi * normalizedBudgetMultiplier)
        : math.max(1, defaultBudget * normalizedBudgetMultiplier);

    // Prefer the explicit base budget when the backend provides it. Some paid
    // profiles still return the free-plan `ai_token_budget`, so scaling down
    // the API budget would incorrectly hide the premium multiplier in the UI.
    final freeBudget = () {
      if (budgetFromApi > 0) {
        if (isPremiumActive && premiumMultiplier > 1) {
          if (budgetFromApi <= inferredFreeBudget) {
            return inferredFreeBudget;
          }
          return math.max(
            1,
            math.max(
              inferredFreeBudget,
              (budgetFromApi / premiumMultiplier).round(),
            ),
          );
        }
        return budgetFromApi;
      }

      if (baseBudgetFromApi > 0) {
        return inferredFreeBudget;
      }

      return inferredFreeBudget;
    }();

    final baseBudget = baseBudgetFromApi > 0
        ? baseBudgetFromApi
        : math.max(1, (freeBudget / normalizedBudgetMultiplier).round());
    final budgetMultiplier = math.max(1, (freeBudget / baseBudget).round());
    final premiumBudget = math.max(1, freeBudget * premiumMultiplier);
    final computedCurrentBudget = isPremiumActive ? premiumBudget : freeBudget;
    final currentBudget = budgetFromApi > 0
        ? math.max(budgetFromApi, computedCurrentBudget)
        : computedCurrentBudget;

    return AiTokenBudgetSnapshot(
      baseBudget: baseBudget,
      freeBudget: freeBudget,
      premiumBudget: premiumBudget,
      currentBudget: currentBudget,
      budgetMultiplier: budgetMultiplier,
      premiumMultiplier: premiumMultiplier,
      isPremiumActive: isPremiumActive,
    );
  }

  /// Builds a token snapshot and falls back to the locally cached premium
  /// purchase state when the backend profile has not caught up yet.
  static Future<AiTokenBudgetSnapshot> fromProfileWithLocalPremium(
    Map<String, dynamic> profile, {
    int defaultBudget = 40160,
  }) async {
    final serverSnapshot = AiTokenBudgetSnapshot.fromProfile(
      profile,
      defaultBudget: defaultBudget,
    );
    if (serverSnapshot.isPremiumActive) {
      return serverSnapshot;
    }

    final currentEmail =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '';
    final profileEmail =
        profile['email']?.toString().trim().toLowerCase() ?? '';
    final resolvedEmail = profileEmail.isNotEmpty ? profileEmail : currentEmail;
    if (resolvedEmail.isEmpty) {
      return serverSnapshot;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedEmail =
          prefs.getString('premium_email')?.trim().toLowerCase() ?? '';
      final cachedTier = prefs.getString('premium_tier')?.trim() ?? '';
      final cachedUntil = prefs.getString('premium_until')?.trim() ?? '';
      final cachedExpiry = DateTime.tryParse(cachedUntil);
      final hasValidLocalPremium =
          cachedEmail == resolvedEmail &&
          cachedTier.isNotEmpty &&
          cachedExpiry != null &&
          cachedExpiry.toUtc().isAfter(DateTime.now().toUtc());

      if (!hasValidLocalPremium) {
        final contributorSnapshot = await _resolveContributorPremiumSnapshot(
          profile,
          prefs: prefs,
          resolvedEmail: resolvedEmail,
          defaultBudget: defaultBudget,
        );
        if (contributorSnapshot != null) {
          return contributorSnapshot;
        }
        return serverSnapshot;
      }

      final mergedProfile = Map<String, dynamic>.from(profile)
        ..['subscription_tier'] = cachedTier
        ..['subscription_end_date'] = cachedUntil;
      return AiTokenBudgetSnapshot.fromProfile(
        mergedProfile,
        defaultBudget: defaultBudget,
      );
    } catch (e) {
      debugPrint('Error accessing SharedPreferences for premium cache: $e');
      return serverSnapshot;
    }
  }

  static Future<AiTokenBudgetSnapshot?> _resolveContributorPremiumSnapshot(
    Map<String, dynamic> profile, {
    required SharedPreferences prefs,
    required String resolvedEmail,
    required int defaultBudget,
  }) async {
    try {
      final response = await Supabase.instance.client
          .from('resources')
          .select('id')
          .eq('uploaded_by_email', resolvedEmail)
          .or(
            Resource.buildStatusOrFilter(const [
              Resource.approvedStatus,
            ], includeLegacyApprovalFlag: true),
          )
          .count(CountOption.exact);

      if (response.count < _contributorPremiumThreshold) {
        return null;
      }

      final premiumUntil = DateTime.now()
          .toUtc()
          .add(_contributorPremiumDuration)
          .toIso8601String();
      await prefs.setString('premium_email', resolvedEmail);
      await prefs.setString('premium_tier', 'pro');
      await prefs.setString('premium_until', premiumUntil);

      final mergedProfile = Map<String, dynamic>.from(profile)
        ..['subscription_tier'] = 'pro'
        ..['subscription_end_date'] = premiumUntil;
      return AiTokenBudgetSnapshot.fromProfile(
        mergedProfile,
        defaultBudget: defaultBudget,
      );
    } catch (e) {
      debugPrint('Failed to resolve contributor premium entitlement: $e');
      return null;
    }
  }

  static int _toSafeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
