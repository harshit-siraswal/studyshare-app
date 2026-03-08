import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/ai_token_budget_utils.dart';

void main() {
  group('isPremiumSubscriptionTier', () {
    test('accepts paid plan aliases used by subscriptions', () {
      expect(isPremiumSubscriptionTier('pro'), isTrue);
      expect(isPremiumSubscriptionTier('premium'), isTrue);
      expect(isPremiumSubscriptionTier('max'), isTrue);
      expect(isPremiumSubscriptionTier('monthly'), isTrue);
      expect(isPremiumSubscriptionTier('quarterly'), isTrue);
      expect(isPremiumSubscriptionTier('premium_monthly'), isTrue);
      expect(isPremiumSubscriptionTier('annual-plan'), isTrue);
    });

    test('rejects clearly non-premium tiers', () {
      expect(isPremiumSubscriptionTier(''), isFalse);
      expect(isPremiumSubscriptionTier('free'), isFalse);
      expect(isPremiumSubscriptionTier('basic_monthly_trial'), isFalse);
    });
  });

  group('AiTokenBudgetSnapshot.fromProfile', () {
    final futurePremiumDate = DateTime.utc(2030, 1, 1).toIso8601String();

    test(
      'applies premium multiplier when a paid tier still returns free budget',
      () {
        final snapshot = AiTokenBudgetSnapshot.fromProfile({
          'subscription_tier': 'monthly',
          'subscription_end_date': futurePremiumDate,
          'ai_token_budget': 40160,
          'ai_token_base_budget': 40160,
          'ai_token_budget_multiplier': 1,
          'ai_token_premium_multiplier': 10,
        });

        expect(snapshot.isPremiumActive, isTrue);
        expect(snapshot.freeBudget, 40160);
        expect(snapshot.premiumBudget, 401600);
        expect(snapshot.currentBudget, 401600);
      },
    );

    test(
      'keeps premium budget stable when backend already sends boosted cap',
      () {
        final snapshot = AiTokenBudgetSnapshot.fromProfile({
          'subscription_tier': 'quarterly',
          'subscription_end_date': futurePremiumDate,
          'ai_token_budget': 401600,
          'ai_token_base_budget': 40160,
          'ai_token_budget_multiplier': 1,
          'ai_token_premium_multiplier': 10,
        });

        expect(snapshot.isPremiumActive, isTrue);
        expect(snapshot.freeBudget, 40160);
        expect(snapshot.premiumBudget, 401600);
        expect(snapshot.currentBudget, 401600);
      },
    );

    test('leaves free users on their unmultiplied budget', () {
      final snapshot = AiTokenBudgetSnapshot.fromProfile({
        'subscription_tier': 'free',
        'subscription_end_date': futurePremiumDate,
        'ai_token_budget': 40160,
        'ai_token_base_budget': 40160,
        'ai_token_budget_multiplier': 1,
        'ai_token_premium_multiplier': 10,
      });

      expect(snapshot.isPremiumActive, isFalse);
      expect(snapshot.freeBudget, 40160);
      expect(snapshot.currentBudget, 40160);
    });
  });
}
