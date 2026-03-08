import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../utils/ai_token_budget_utils.dart';
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
  bool _isRechargeLoading = false;
  String _selectedPlan = 'quarterly';
  String? _expandedPlanId = 'quarterly';
  int _baseMonthlyTokens = 40160;
  int _premiumTokenMultiplier = 10;
  double _baseBudgetInr = 1;
  int _selectedRechargeRupees = 49;
  final TextEditingController _customRechargeController =
      TextEditingController();

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

  bool get _isPurchaseEnabled => _planUi.containsKey(_selectedPlan);

  int get _premiumMonthlyTokens =>
      _baseMonthlyTokens * math.max(1, _premiumTokenMultiplier);

  int get _freeVisibleTokens => visibleAiTokensFromRaw(_baseMonthlyTokens);

  int get _premiumVisibleTokens =>
      _freeVisibleTokens * math.max(1, _premiumTokenMultiplier);

  int get _tokensPerRupee => math.max(
    1,
    (_baseMonthlyTokens / math.max(0.01, _baseBudgetInr)).round(),
  );

  @override
  void initState() {
    super.initState();
    _loadTokenPreviewData();
  }

  @override
  void dispose() {
    _customRechargeController.dispose();
    super.dispose();
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

  double _toSafeDouble(dynamic value, {double fallback = 1}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _formatTokenCount(int value) {
    if (value <= 0) return '0';
    return math.max(1, visibleAiTokensFromRaw(value)).toString();
  }

  Future<void> _loadTokenPreviewData() async {
    try {
      final profile = await _supabaseService.getCurrentUserProfile(
        maxAttempts: 1,
      );
      if (!mounted || profile.isEmpty) return;

      final tokenSnapshot =
          await AiTokenBudgetSnapshot.fromProfileWithLocalPremium(
            profile,
            defaultBudget: _baseMonthlyTokens,
          );
      final budgetInr = _toSafeDouble(profile['ai_budget_inr'], fallback: 1);

      setState(() {
        _baseMonthlyTokens = math.max(1, tokenSnapshot.freeBudget);
        _premiumTokenMultiplier = tokenSnapshot.premiumMultiplier;
        _baseBudgetInr = budgetInr > 0 ? budgetInr : 1;
      });
    } catch (_) {
      // Keep defaults if profile fetch fails.
    }
  }

  List<String> _benefitsWithTokenLine(_PlanUiData plan) {
    final tokenLine =
        '${_formatTokenCount(_premiumMonthlyTokens)} AI tokens every 30 days '
        '(${_premiumTokenMultiplier}x the free plan)';
    return <String>[tokenLine, ...plan.benefits];
  }

  int _resolveRechargeRupees() {
    final custom = int.tryParse(_customRechargeController.text.trim());
    if (custom != null && custom > 0) {
      return custom;
    }
    return _selectedRechargeRupees;
  }

  int _estimatedRechargeTokens(int rupees) {
    return math.max(1, rupees * _tokensPerRupee);
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

  Future<void> _startAiRechargePayment() async {
    if (_isRechargeLoading || _isLoading) return;

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

    final rechargeRupees = _resolveRechargeRupees();
    if (rechargeRupees < 10 || rechargeRupees > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recharge amount must be between ₹10 and ₹5000.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isRechargeLoading = true);
    final phone = _auth.currentUser?.phoneNumber ?? '9999999999';

    final result = await _subService.buyAiTokenRecharge(
      context,
      email,
      phone,
      rechargeRupees: rechargeRupees,
    );

    if (!mounted) return;
    setState(() => _isRechargeLoading = false);

    if (result) {
      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => SuccessOverlay(
          variant: SuccessOverlayVariant.premiumUpgrade,
          title: 'AI Tokens Added',
          message:
              'Recharge successful. ${_formatTokenCount(_estimatedRechargeTokens(rechargeRupees))} AI tokens credited.',
          badgeLabel: 'AI Recharge',
          onDismiss: () {
            Navigator.pop(context);
            widget.onSuccess();
          },
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI recharge failed. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
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
    final freePlanTokenLabel = _freeVisibleTokens.toString();
    final premiumTokenLabel = _premiumVisibleTokens.toString();
    final purchaseCta = _selectedPlan == 'quarterly'
        ? 'Buy \u20b9149 Plan'
        : 'Buy \u20b949 Plan';
    final helperText = _isPurchaseEnabled
        ? 'Free users get $freePlanTokenLabel AI tokens every 30 days. '
              'Premium includes $premiumTokenLabel AI tokens every 30 days.'
        : 'Select a plan to continue.';

    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: SingleChildScrollView(
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
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white12
                        : primaryColor.withValues(alpha: 0.24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student-friendly AI pricing',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Free plan: $freePlanTokenLabel AI tokens every 30 days.\n'
                      'Premium: $premiumTokenLabel AI tokens every 30 days. Need more? Use micro top-ups from \u20b919.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: bodyText,
                        height: 1.35,
                      ),
                    ),
                  ],
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
              _buildAiRechargeSection(
                isDark: isDark,
                primaryColor: primaryColor,
                titleColor: scheme.onSurface,
                subtitleColor: bodyText,
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (_isRechargeLoading || _isLoading)
                      ? null
                      : _startAiRechargePayment,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: primaryColor.withValues(alpha: 0.6),
                    ),
                    foregroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _isRechargeLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Recharge AI Tokens',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
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

  Widget _buildAiRechargeSection({
    required bool isDark,
    required Color primaryColor,
    required Color titleColor,
    required Color subtitleColor,
  }) {
    final rechargeRupees = _resolveRechargeRupees();
    final estimatedTokens = _estimatedRechargeTokens(rechargeRupees);
    final quickPacks = const <int>[19, 29, 49, 99, 149, 199];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : primaryColor.withValues(alpha: 0.05),
        border: Border.all(
          color: isDark ? Colors.white12 : primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student AI Recharge',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Low-cost micro top-ups for students. Pick a pack below to see the AI tokens you will receive.',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: subtitleColor,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: quickPacks.map((pack) {
              final selected = _selectedRechargeRupees == pack;
              return ChoiceChip(
                label: Text('\u20b9$pack'),
                selected: selected,
                onSelected: (value) {
                  if (!value) return;
                  setState(() {
                    _selectedRechargeRupees = pack;
                    _customRechargeController.clear();
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _customRechargeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Custom recharge amount (\u20b910 - \u20b95000)',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixText: '\u20b9',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'You will receive about ${_formatTokenCount(estimatedTokens)} AI tokens.',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primaryColor,
            ),
          ),
        ],
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
