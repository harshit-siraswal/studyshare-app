import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../services/subscription_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/paywall_dialog.dart';

class CreateRoomScreen extends StatefulWidget {
  final String collegeId;
  final String userEmail;

  const CreateRoomScreen({
    super.key,
    required this.collegeId,
    required this.userEmail,
  });

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();

  final List<String> _selectedTags = <String>[];

  bool _isPrivate = false;
  bool _isPermanent = false;
  bool _isPremium = false;
  bool _isLoadingPremium = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  static const List<String> _tagSuggestions = <String>[
    '#dsa',
    '#placement',
    '#hackathon',
    '#revision',
    '#semester',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _supabaseService.attachContext(context);
    });
    _loadPremiumStatus();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    _subscriptionService.dispose();
    super.dispose();
  }

  Future<void> _loadPremiumStatus() async {
    try {
      final isPremium = await _subscriptionService.isPremium();
      if (!mounted) return;
      setState(() {
        _isPremium = isPremium;
        _isLoadingPremium = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPremium = false);
    }
  }

  Future<void> _showPremiumPaywall() async {
    await showDialog<void>(
      context: context,
      builder: (_) => PaywallDialog(onSuccess: _loadPremiumStatus),
    );
  }

  void _setError(String? message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  void _addTag([String? rawValue]) {
    final value = (rawValue ?? _tagController.text).trim();
    if (value.isEmpty) return;

    final normalized = value.startsWith('#') ? value : '#$value';
    final tagBody = normalized.substring(1);
    const maxTagLength = 24;

    if (tagBody.length < 2) {
      _setError('Tag must have at least 2 characters after #.');
      return;
    }
    if (tagBody.length > maxTagLength) {
      _setError('Tag cannot exceed $maxTagLength characters.');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(tagBody)) {
      _setError(
        'Tag can only contain letters, numbers, underscores, and hyphens.',
      );
      return;
    }
    if (_selectedTags.contains(normalized)) {
      _setError('Tag already added.');
      return;
    }

    setState(() {
      _selectedTags.add(normalized);
      _tagController.clear();
      _errorMessage = null;
    });
  }

  Future<void> _handlePermanentSelection(bool value) async {
    if (_isSubmitting || _isLoadingPremium) return;
    if (!value) {
      setState(() => _isPermanent = false);
      return;
    }
    if (_isPremium) {
      setState(() => _isPermanent = true);
      return;
    }
    await _showPremiumPaywall();
  }

  Future<void> _submit() async {
    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      _setError('Room name is required.');
      return;
    }
    if (_selectedTags.isEmpty) {
      _setError('Please add at least one tag.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final duration = _isPermanent
          ? SupabaseService.kUnlimitedDuration
          : SupabaseService.kDefaultExpiryDays;

      final result = await _supabaseService.createChatRoom(
        name: trimmedName,
        description: _descriptionController.text,
        isPrivate: _isPrivate,
        userEmail: widget.userEmail,
        collegeId: widget.collegeId,
        tags: _selectedTags,
        durationInDays: duration,
      );

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (_) {
      _setError('Failed to create room. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF070B12) : const Color(0xFFF5F7FB);
    final surfaceColor = isDark ? const Color(0xFF111827) : Colors.white;
    final borderColor = isDark ? Colors.white10 : const Color(0xFFE2E8F0);
    final mutedColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          'Create Room',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 22,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 132),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroCard(
                isDark: isDark,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                mutedColor: mutedColor,
              ),
              const SizedBox(height: 18),
              _buildSurface(
                isDark: isDark,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeading(
                      'Basics',
                      'Set the room name and what members should expect.',
                      isDark: isDark,
                      mutedColor: mutedColor,
                    ),
                    const SizedBox(height: 18),
                    _buildInputLabel('Room Name', isDark),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: _fieldDecoration(
                        hintText: 'Placement Prep 2026',
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInputLabel('Description', isDark),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 4,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: _fieldDecoration(
                        hintText:
                            'What is this room for, who should join, and what will be shared here?',
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSurface(
                isDark: isDark,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeading(
                      'Tags',
                      'Help the right students discover the room quickly.',
                      isDark: isDark,
                      mutedColor: mutedColor,
                      trailing: Text(
                        'Required',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagController,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: _fieldDecoration(
                              hintText: 'Add a tag like #dsa',
                              isDark: isDark,
                            ),
                            onSubmitted: _addTag,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 54,
                          width: 54,
                          child: FilledButton(
                            onPressed: _isSubmitting ? null : _addTag,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Icon(Icons.add_rounded, size: 24),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedTags.isEmpty
                          ? _tagSuggestions
                                .map(
                                  (tag) => ActionChip(
                                    label: Text(tag),
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => _addTag(tag),
                                  ),
                                )
                                .toList()
                          : _selectedTags
                                .map(
                                  (tag) => Chip(
                                    label: Text(tag),
                                    onDeleted: _isSubmitting
                                        ? null
                                        : () {
                                            setState(() {
                                              _selectedTags.remove(tag);
                                            });
                                          },
                                  ),
                                )
                                .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSurface(
                isDark: isDark,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeading(
                      'Visibility',
                      'Public rooms appear in Discover. Private rooms stay hidden and join by code only.',
                      isDark: isDark,
                      mutedColor: mutedColor,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildVisibilityOption(
                            title: 'Public',
                            subtitle: 'Shown in Discover',
                            icon: Icons.public_rounded,
                            selected: !_isPrivate,
                            isDark: isDark,
                            onTap: _isSubmitting
                                ? null
                                : () => setState(() => _isPrivate = false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildVisibilityOption(
                            title: 'Private',
                            subtitle: 'Join with code',
                            icon: Icons.lock_rounded,
                            selected: _isPrivate,
                            isDark: isDark,
                            onTap: _isSubmitting
                                ? null
                                : () => setState(() => _isPrivate = true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSurface(
                isDark: isDark,
                surfaceColor: surfaceColor,
                borderColor: borderColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeading(
                      'Duration',
                      'Free users create 7-day rooms. Premium unlocks permanent rooms and later expiry extensions.',
                      isDark: isDark,
                      mutedColor: mutedColor,
                    ),
                    const SizedBox(height: 16),
                    _buildDurationOption(
                      title: 'Temporary Room',
                      subtitle: 'Active for 7 days from creation.',
                      selected: !_isPermanent,
                      isDark: isDark,
                      badge: 'Default',
                      onTap: () => _handlePermanentSelection(false),
                    ),
                    const SizedBox(height: 12),
                    _buildDurationOption(
                      title: 'Permanent Room',
                      subtitle: _isPremium
                          ? 'No default expiry. Best for long-running communities.'
                          : 'Premium only. Also unlocks room expiry extension.',
                      selected: _isPermanent,
                      isDark: isDark,
                      badge: _isPremium ? 'Unlocked' : 'PRO',
                      trailingIcon: _isPremium
                          ? Icons.workspace_premium_rounded
                          : Icons.lock_rounded,
                      onTap: () => _handlePermanentSelection(true),
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: GoogleFonts.inter(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Create Room',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isPrivate
                  ? 'Private rooms stay off Discover and join through the room code.'
                  : 'Public rooms can still share a code, but they remain visible in Discover.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard({
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
    required Color mutedColor,
  }) {
    return _buildSurface(
      isDark: isDark,
      surfaceColor: surfaceColor,
      borderColor: borderColor,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: AppTheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Build a room students will actually use',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Keep the setup focused: clear purpose, a few strong tags, and the right visibility.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.45,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSurface({
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeading(
    String title,
    String subtitle, {
    required bool isDark,
    required Color mutedColor,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.45,
                  color: mutedColor,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ],
    );
  }

  Widget _buildInputLabel(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : const Color(0xFF334155),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required bool isDark,
  }) {
    final fillColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.inter(
        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
      ),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.2),
      ),
    );
  }

  Widget _buildVisibilityOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required bool isDark,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? AppTheme.primary.withValues(alpha: isDark ? 0.22 : 0.1)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF8FAFC)),
            border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? AppTheme.primary
                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: selected
                        ? AppTheme.primary
                        : (isDark ? Colors.white30 : const Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.35,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationOption({
    required String title,
    required String subtitle,
    required bool selected,
    required bool isDark,
    required String badge,
    required VoidCallback onTap,
    IconData? trailingIcon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSubmitting ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? AppTheme.primary.withValues(alpha: isDark ? 0.2 : 0.08)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF8FAFC)),
            border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badge == 'PRO'
                                ? const Color(0xFFFFF3C4)
                                : AppTheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: badge == 'PRO'
                                  ? const Color(0xFF8A5A00)
                                  : AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.4,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  if (trailingIcon != null)
                    Icon(
                      trailingIcon,
                      size: 18,
                      color: selected
                          ? AppTheme.primary
                          : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                    ),
                  const SizedBox(height: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: selected
                        ? AppTheme.primary
                        : (isDark ? Colors.white30 : const Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
