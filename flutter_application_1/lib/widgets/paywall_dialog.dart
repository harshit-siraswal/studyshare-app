import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'success_overlay.dart';

class PaywallDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const PaywallDialog({super.key, required this.onSuccess});

  @override
  State<PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends State<PaywallDialog> {
  final SubscriptionService _subService = SubscriptionService();
  final AuthService _auth = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = false;
  String _selectedPlan = 'quarterly';
  String? _expandedPlanId = 'quarterly';
  int _baseMonthlyTokens = 40160;
  int _premiumTokenMultiplier = 5;

  static const Map<String, _PlanUiData> _planUi = {
    'monthly': _PlanUiData(
      id: 'monthly',
      title: 'Monthly',
      priceLabel: '\u20b949/month',
      subtitle: '30-day access with all premium tools',
      benefits: [
        'Offline PDF downloads',
        '1-year chat room validity',
        'Premium profile badge',
      ],
    ),
    'quarterly': _PlanUiData(
      id: 'quarterly',
      title: 'Quarterly',
      priceLabel: '\u20b9149',
      subtitle: '90-day access with best value pricing',
      badgeText: 'BEST VALUE',
      benefits: [
        'Offline PDF downloads',
        '1-year chat room validity',
        'Premium profile badge',
      ],
    ),
  };

  bool get _isPurchaseEnabled =>
      _expandedPlanId != null && _expandedPlanId == _selectedPlan;

  int get _premiumMonthlyTokens =>
      _baseMonthlyTokens * math.max(1, _premiumTokenMultiplier);

  @override
  void initState() {
    super.initState();
    _loadTokenPreviewData();
  }

  void _handlePlanTap(String planId) {
    setState(() => _selectedPlan = planId);
  }

  void _handlePriceTap(String planId) {
    setState(() {
      if (_selectedPlan == planId && _expandedPlanId == planId) {
        return;
      }
      _selectedPlan = planId;
      _expandedPlanId = _expandedPlanId == planId ? null : planId;
    });
  }

  int _toSafeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatTokenCount(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      buffer.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  Future<void> _loadTokenPreviewData() async {
    try {
      final profile = await _supabaseService.getCurrentUserProfile(
        maxAttempts: 1,
      );
      if (!mounted || profile.isEmpty) return;

      final budget = _toSafeInt(profile['ai_token_budget']);
      final currentMultiplier = math.max(
        1,
        _toSafeInt(profile['ai_token_budget_multiplier']),
      );
      final configuredPremiumMultiplier = math.max(
        1,
        _toSafeInt(profile['ai_token_premium_multiplier']),
      );
      final premiumMultiplier = configuredPremiumMultiplier > 1
          ? configuredPremiumMultiplier
          : 5;

      var baseBudget = budget;
      if (budget > 0 && currentMultiplier > 1) {
        baseBudget = (budget / currentMultiplier).round();
      }
      if (baseBudget <= 0) {
        baseBudget = _baseMonthlyTokens;
      }

      setState(() {
        _baseMonthlyTokens = math.max(1, baseBudget);
        _premiumTokenMultiplier = premiumMultiplier;
      });
    } catch (_) {
      // Keep defaults if profile fetch fails.
    }
  }

  List<String> _benefitsWithTokenLine(_PlanUiData plan) {
    final tokenLine =
        '${_formatTokenCount(_premiumMonthlyTokens)} AI tokens every 30 days '
        '(${_premiumTokenMultiplier}x free)';
    return <String>[tokenLine, ...plan.benefits];
  }

  Future<void> _startPayment() async {
    if (!_isPurchaseEnabled) return;

    final email = _auth.userEmail;
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to continue.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);

    final phone = _auth.currentUser?.phoneNumber ?? '9999999999';

    final result = await _subService.buyPremium(
      context,
      email,
      phone,
      planId: _selectedPlan,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result) {
        Navigator.pop(context);

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => SuccessOverlay(
              variant: SuccessOverlayVariant.premiumUpgrade,
              title: 'Pro Activated',
              message:
                  'Premium activated successfully. Enjoy all pro features.',
              badgeLabel: 'Premium Member',
              onDismiss: () {
                Navigator.pop(context);
                widget.onSuccess();
              },
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment failed. Please try again or contact support.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _restorePurchase() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context);
      widget.onSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchases restored successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final primaryColor = const Color(0xFFFF6B35);
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final bodyText = isDark
        ? Colors.white.withValues(alpha: 0.76)
        : Colors.black.withValues(alpha: 0.62);
    final premiumTokenLabel = _formatTokenCount(_premiumMonthlyTokens);
    final purchaseCta = _selectedPlan == 'quarterly'
        ? 'Buy \u20b9149 Plan'
        : 'Buy \u20b949 Plan';
    final helperText = _isPurchaseEnabled
        ? 'Includes $premiumTokenLabel AI tokens every 30 days.'
        : 'Tap price to view benefits, then purchase.';

    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              Text(
                'StudyShare Premium',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Choose your plan and tap the price to preview everything you get.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: bodyText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _buildPlanCard(
                plan: _planUi['monthly']!,
                primaryColor: primaryColor,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildPlanCard(
                plan: _planUi['quarterly']!,
                primaryColor: primaryColor,
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  helperText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isPurchaseEnabled
                        ? primaryColor.withValues(alpha: 0.9)
                        : bodyText,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _restorePurchase,
                  child: Text(
                    'Restore Purchase',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoading || !_isPurchaseEnabled)
                      ? null
                      : _startPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              purchaseCta,
                              style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_selectedPlan == 'monthly')
                              Text(
                                'Cancel Anytime',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: GoogleFonts.inter(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
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

  Widget _buildPlanCard({
    required _PlanUiData plan,
    required Color primaryColor,
    required bool isDark,
  }) {
    final benefits = _benefitsWithTokenLine(plan);
    final isSelected = _selectedPlan == plan.id;
    final isExpanded = _expandedPlanId == plan.id;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : Colors.black.withValues(alpha: 0.58);
    final cardBg = isSelected
        ? (isDark
              ? primaryColor.withValues(alpha: 0.14)
              : primaryColor.withValues(alpha: 0.08))
        : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white);
    final borderColor = isSelected
        ? primaryColor
        : (isDark ? Colors.white12 : Colors.grey.shade200);
    final benefitsBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : primaryColor.withValues(alpha: 0.06);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _handlePlanTap(plan.id),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: borderColor,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? primaryColor : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? primaryColor
                                : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.title,
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                              ),
                            ),
                            if (plan.subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                plan.subtitle!,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: subtitleColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _handlePriceTap(plan.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: isSelected
                                ? primaryColor.withValues(alpha: 0.18)
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.04)),
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : (isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300),
                            ),
                          ),
                          child: Text(
                            plan.priceLabel,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (benefits.isNotEmpty)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: isExpanded
                          ? Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 14),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: benefitsBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white12
                                      : primaryColor.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'What you get',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: titleColor,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ...benefits.map(
                                    (benefit) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.check_circle_rounded,
                                            size: 16,
                                            color: primaryColor,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              benefit,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: subtitleColor,
                                                fontWeight: FontWeight.w600,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            if (plan.badgeText != null)
              Positioned(
                top: -12,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    plan.badgeText!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanUiData {
  final String id;
  final String title;
  final String priceLabel;
  final String? subtitle;
  final String? badgeText;
  final List<String> benefits;

  const _PlanUiData({
    required this.id,
    required this.title,
    required this.priceLabel,
    required this.benefits,
    this.subtitle,
    this.badgeText,
  });
}
