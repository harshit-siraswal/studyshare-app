import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../utils/ai_token_budget_utils.dart';
import '../../widgets/ai_recharge_dialog.dart';

class AiTokenUsageScreen extends StatefulWidget {
  const AiTokenUsageScreen({
    super.key,
    required this.budget,
    required this.used,
    required this.remaining,
    required this.baseBudget,
    required this.budgetMultiplier,
    required this.premiumMultiplier,
    required this.cycleDays,
    this.cycleStartedAt,
    this.cycleEndsAt,
  });

  final int budget;
  final int used;
  final int remaining;
  final int baseBudget;
  final int budgetMultiplier;
  final int premiumMultiplier;
  final int cycleDays;
  final DateTime? cycleStartedAt;
  final DateTime? cycleEndsAt;

  @override
  State<AiTokenUsageScreen> createState() => _AiTokenUsageScreenState();
}

class _AiTokenUsageScreenState extends State<AiTokenUsageScreen> {
  static const int _tokensPerCredit = 2000;
  /// Default monthly token budget for new/free-tier users
  static const int _defaultBudget = 40000;

  int get _budget => widget.budget > 0 ? widget.budget : _defaultBudget;
  int get _used => widget.used.clamp(0, _budget);
  int get _remaining => widget.remaining.clamp(0, _budget);
  double get _progress => _budget > 0 ? (_used / _budget).clamp(0.0, 1.0) : 0;
  bool get _isExhausted => _budget > 0 && _remaining <= 0;

  String _formatTokenCompact3(int value) {
    final abs = value.abs();
    if (abs < 1000) return value.toString();

    double scaled = value.toDouble();
    String suffix = '';
    if (abs >= 1000000000) {
      scaled = value / 1000000000;
      suffix = 'B';
    } else if (abs >= 1000000) {
      scaled = value / 1000000;
      suffix = 'M';
    } else {
      scaled = value / 1000;
      suffix = 'K';
    }

    return '${scaled.round()}$suffix';
  }

  String _formatTokenWithCommas(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      final remaining = digits.length - index;
      buffer.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  String _formatTokenDetailed(int value) {
    return '${_formatTokenCompact3(value)} (${_formatTokenWithCommas(value)})';
  }

  String _formatCreditCompact(int tokenValue) {
    if (tokenValue <= 0) return '0';
    final credits = tokenValue / _tokensPerCredit;
    return math.max(1, credits.round()).toString();
  }

  String _formatCreditDetailed(int tokenValue) {
    return '${_formatCreditCompact(tokenValue)} credits '
        '(${_formatTokenWithCommas(tokenValue)} tokens)';
  }

  String _formatCreditRange(int minTokens, int maxTokens) {
    return '${_formatCreditCompact(minTokens)} - '
        '${_formatCreditCompact(maxTokens)} credits';
  }

  String _formatCycleDate(DateTime? value) {
    if (value == null) return 'N/A';
    final local = value.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final dateStr = localizations.formatMediumDate(local);
    final timeStr = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$dateStr $timeStr';
  }

  Future<void> _openPurchaseOptions() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AiRechargeDialog(
        onSuccess: () {
          if (!mounted) return;
          Navigator.of(context).pop(true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.getTextColor(context);
    final subTextColor = AppTheme.getTextColor(context, isPrimary: false);
    final cycleLabel =
        '${widget.cycleDays > 0 ? widget.cycleDays : 30} day cycle';
    final usagePercent = _budget > 0
        ? ((_used / _budget) * 100).toStringAsFixed(0)
        : '0';

    return Scaffold(
      backgroundColor: isDark ? Colors.black : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'AI Credits',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            120 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white,
                  border: Border.all(
                    color: _isExhausted
                        ? AppTheme.error.withValues(alpha: 0.35)
                        : AppTheme.primary.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.24 : 0.06,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.token_rounded,
                          color: _isExhausted
                              ? AppTheme.error
                              : AppTheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Monthly AI Credits',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (_isExhausted
                                        ? AppTheme.error
                                        : AppTheme.primary)
                                    .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _isExhausted
                                ? 'Exhausted'
                                : '${_formatCreditCompact(_remaining)} credits left',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _isExhausted
                                  ? AppTheme.error
                                  : AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tap into the full breakdown of your current cycle and recharge when you need more usage.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.4,
                        color: subTextColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recharge rate: \u20b91 = $kVisibleAiRechargeTokensPerRupee AI tokens',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 9,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isExhausted ? AppTheme.error : AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _MetricTile(
                          label: 'Remaining',
                          value: _formatCreditCompact(_remaining),
                          textColor: textColor,
                          subTextColor: subTextColor,
                        ),
                        _MetricTile(
                          label: 'Used',
                          value: _formatCreditCompact(_used),
                          textColor: textColor,
                          subTextColor: subTextColor,
                        ),
                        _MetricTile(
                          label: 'Total',
                          value: _formatCreditCompact(_budget),
                          textColor: textColor,
                          subTextColor: subTextColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Current cycle',
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Total monthly credits',
                      value: _formatCreditDetailed(_budget),
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Used in current cycle',
                      value: '${_formatCreditDetailed(_used)} ($usagePercent%)',
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Remaining credits',
                      value: _formatCreditDetailed(_remaining),
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Cycle length',
                      value: cycleLabel,
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Cycle started',
                      value: _formatCycleDate(widget.cycleStartedAt),
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Cycle ends',
                      value: _formatCycleDate(widget.cycleEndsAt),
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'How this is calculated',
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Token to credit ratio',
                      value:
                          '1 credit = ${_formatTokenWithCommas(_tokensPerCredit)} tokens',
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Base budget',
                      value: _formatTokenDetailed(widget.baseBudget),
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Current multiplier',
                      value: '${widget.budgetMultiplier}x',
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Premium multiplier',
                      value: '${widget.premiumMultiplier}x',
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Billable usage = input tokens + weighted output tokens. '
                      'Larger notes and longer AI replies consume more credits.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.45,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Estimated cost per task',
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'AI chat reply',
                      value:
                          '${_formatCreditRange(300, 1200)} (~${_formatTokenCompact3(300)}-${_formatTokenCompact3(1200)} tokens)',
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Generate summary',
                      value:
                          '${_formatCreditRange(1400, 3200)} (~${_formatTokenCompact3(1400)}-${_formatTokenCompact3(3200)} tokens)',
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Generate flashcards',
                      value:
                          '${_formatCreditRange(1800, 4200)} (~${_formatTokenCompact3(1800)}-${_formatTokenCompact3(4200)} tokens)',
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                    _DetailRow(
                      label: 'Generate quiz',
                      value:
                          '${_formatCreditRange(2200, 5200)} (~${_formatTokenCompact3(2200)}-${_formatTokenCompact3(5200)} tokens)',
                      textColor: textColor,
                      subTextColor: subTextColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: FilledButton.icon(
            onPressed: _openPurchaseOptions,
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('Purchase AI Tokens'),
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.textColor,
    required this.subTextColor,
  });

  final String label;
  final String value;
  final Color textColor;
  final Color subTextColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: subTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.getTextColor(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.textColor,
    required this.subTextColor,
  });

  final String label;
  final String value;
  final Color textColor;
  final Color subTextColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: subTextColor,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
