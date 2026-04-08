import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../utils/ai_token_budget_utils.dart';
import 'success_overlay.dart';

/// A focused dialog for AI token recharge only — does NOT show premium
/// subscription plans.  Use this from [AiTokenUsageScreen] so students see
/// only the recharge options they need.
class AiRechargeDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const AiRechargeDialog({super.key, required this.onSuccess});

  @override
  State<AiRechargeDialog> createState() => _AiRechargeDialogState();
}

class _AiRechargeDialogState extends State<AiRechargeDialog> {
  final SubscriptionService _subService = SubscriptionService();
  final AuthService _auth = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = false;
  int _baseMonthlyTokens = 40000;
  int _selectedRechargeRupees = 49;
  final TextEditingController _customRechargeController =
      TextEditingController();

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

  // ── helpers ────────────────────────────────────────────────────────

  // ignore: unused_element
  int _toSafeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatTokenCount(int value) {
    if (value <= 0) return '0';
    return math.max(1, visibleAiTokensFromRaw(value)).toString();
  }

  int _resolveRechargeRupees() {
    final custom = int.tryParse(_customRechargeController.text.trim());
    if (custom != null && custom > 0) return custom;
    return _selectedRechargeRupees;
  }

  int _estimatedRechargeTokens(int rupees) =>
      rawAiTokensForRechargeRupees(rupees);

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
      setState(() {
        _baseMonthlyTokens = math.max(1, tokenSnapshot.freeBudget);
      });
    } catch (_) {
      // Keep defaults if profile fetch fails.
    }
  }

  // ── recharge payment ──────────────────────────────────────────────

  Future<void> _startAiRechargePayment() async {
    if (_isLoading) return;

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

    setState(() => _isLoading = true);
    final phone = _auth.currentUser?.phoneNumber ?? '9999999999';

    final result = await _subService.buyAiTokenRecharge(
      context,
      email,
      phone,
      rechargeRupees: rechargeRupees,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

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

  // ── build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final primaryColor = const Color(0xFFFF6B35);
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final bodyText = isDark
        ? Colors.white.withValues(alpha: 0.76)
        : Colors.black.withValues(alpha: 0.62);

    final rechargeRupees = _resolveRechargeRupees();
    final estimatedTokens = _estimatedRechargeTokens(rechargeRupees);
    final quickPacks = const <int>[10, 19, 29, 49, 99, 149, 199];

    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
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

              // Title
              Icon(Icons.bolt_rounded, size: 40, color: primaryColor),
              const SizedBox(height: 8),
              Text(
                'Recharge AI Tokens',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Low-cost micro top-ups for students.\nPick a pack to see the tokens you\'ll receive.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: bodyText,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Recharge rate: \u20b91 = $kVisibleAiRechargeTokensPerRupee AI tokens',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 12),

              // Quick packs
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: quickPacks.map((pack) {
                  final selected = _selectedRechargeRupees == pack;
                  return ChoiceChip(
                    label: Text('₹$pack'),
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
              const SizedBox(height: 14),

              // Custom amount
              TextField(
                controller: _customRechargeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Custom amount (₹10 – ₹5000)',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixText: '₹',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),

              // Estimate
              Text(
                'You will receive about ${_formatTokenCount(estimatedTokens)} AI tokens.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 24),

              // CTA button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _startAiRechargePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Recharge ₹$rechargeRupees',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Back / dismiss
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
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
}
