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
  bool _isPremium = false;
  bool _isTier2 = false;
  bool _isLoadingPremium = true;
  bool _isSubmitting = false;
  int _selectedDurationDays = SupabaseService.kDefaultExpiryDays;
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
      final isTier2 = isPremium ? await _subscriptionService.isTier2() : false;
      if (!mounted) return;
      setState(() {
        _isPremium = isPremium;
        _isTier2 = isTier2;
        _isLoadingPremium = false;
        if (!_isPremium &&
            _selectedDurationDays > SupabaseService.kDefaultExpiryDays) {
          _selectedDurationDays = SupabaseService.kDefaultExpiryDays;
        } else if (!_isTier2 &&
            _selectedDurationDays > SupabaseService.kPremiumExpiryDays) {
          _selectedDurationDays = SupabaseService.kPremiumExpiryDays;
        }
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

  List<_RoomDurationOption> get _durationOptions {
    return <_RoomDurationOption>[
      const _RoomDurationOption(
        days: SupabaseService.kDefaultExpiryDays,
        title: '7 days',
        subtitle: 'Standard',
      ),
      _RoomDurationOption(
        days: SupabaseService.kPremiumExpiryDays,
        title: '30 days',
        subtitle: _isPremium ? 'Premium' : 'Premium only',
        locked: !_isPremium,
      ),
      if (_isTier2)
        const _RoomDurationOption(
          days: SupabaseService.kTier2ExpiryDays,
          title: '90 days',
          subtitle: 'Max',
        ),
    ];
  }

  Future<void> _selectDuration(_RoomDurationOption option) async {
    if (_isSubmitting || _isLoadingPremium) return;
    if (option.locked) {
      await _showPremiumPaywall();
      return;
    }
    setState(() => _selectedDurationDays = option.days);
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
      final result = await _supabaseService.createChatRoom(
        name: trimmedName,
        description: _descriptionController.text,
        isPrivate: _isPrivate,
        userEmail: widget.userEmail,
        collegeId: widget.collegeId,
        tags: _selectedTags,
        durationInDays: _selectedDurationDays,
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
    final pageBg = isDark ? const Color(0xFF070B12) : Colors.white;
    final dividerColor = isDark ? Colors.white10 : const Color(0xFFE2E8F0);
    final mutedColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final fieldFill = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF8FAFC);
    final borderColor = isDark ? Colors.white10 : const Color(0xFFE2E8F0);

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
              Text(
                'Keep it focused: one clear topic, a few sharp tags, and the right visibility.',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.5,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMetaChip(
                    label: _isPrivate ? 'Private room' : 'Public room',
                    icon: _isPrivate
                        ? Icons.lock_rounded
                        : Icons.public_rounded,
                    isDark: isDark,
                  ),
                  _buildMetaChip(
                    label: '$_selectedDurationDays day expiry',
                    icon: Icons.schedule_rounded,
                    isDark: isDark,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildLabel('Room Name', isDark),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: _fieldDecoration(
                  hintText: 'Placement Prep 2026',
                  isDark: isDark,
                  fillColor: fieldFill,
                  borderColor: borderColor,
                ),
              ),
              const SizedBox(height: 18),
              _buildLabel('Description', isDark),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: _fieldDecoration(
                  hintText:
                      'What should members expect, and who is this room for?',
                  isDark: isDark,
                  fillColor: fieldFill,
                  borderColor: borderColor,
                ),
              ),
              const SizedBox(height: 24),
              Divider(color: dividerColor, height: 1),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildLabel('Tags', isDark)),
                  Text(
                    'Required',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Use a few tags students would actually search for.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.45,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 12),
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
                        fillColor: fieldFill,
                        borderColor: borderColor,
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
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Icon(Icons.add_rounded, size: 22),
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
                              labelStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
                              side: BorderSide(color: borderColor),
                              backgroundColor: pageBg,
                            ),
                          )
                          .toList()
                    : _selectedTags
                          .map(
                            (tag) => Chip(
                              label: Text(tag),
                              labelStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                              deleteIconColor: AppTheme.primary,
                              onDeleted: _isSubmitting
                                  ? null
                                  : () {
                                      setState(() {
                                        _selectedTags.remove(tag);
                                      });
                                    },
                              side: BorderSide(
                                color: AppTheme.primary.withValues(alpha: 0.24),
                              ),
                              backgroundColor: AppTheme.primary.withValues(
                                alpha: isDark ? 0.18 : 0.08,
                              ),
                            ),
                          )
                          .toList(),
              ),
              const SizedBox(height: 24),
              Divider(color: dividerColor, height: 1),
              const SizedBox(height: 24),
              _buildLabel('Visibility', isDark),
              const SizedBox(height: 8),
              Text(
                'Private rooms stay hidden from Discover and join by room code only.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.45,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildSegmentOption(
                      title: 'Public',
                      subtitle: 'Visible in Discover',
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
                    child: _buildSegmentOption(
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
              const SizedBox(height: 24),
              Divider(color: dividerColor, height: 1),
              const SizedBox(height: 24),
              _buildLabel('Room Duration', isDark),
              const SizedBox(height: 8),
              Text(
                'Rooms expire automatically. Paid plans simply unlock longer fixed windows.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.45,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _durationOptions
                    .map(
                      (option) =>
                          _buildDurationOption(option: option, isDark: isDark),
                    )
                    .toList(),
              ),
              if (!_isPremium) ...[
                const SizedBox(height: 10),
                Text(
                  'Free accounts can create 7-day rooms. Upgrade to unlock longer expiry windows.',
                  style: GoogleFonts.inter(
                    fontSize: 11.8,
                    height: 1.45,
                    color: mutedColor,
                  ),
                ),
              ] else if (_isTier2) ...[
                const SizedBox(height: 10),
                Text(
                  'Max plan rooms can stay active for up to 90 days before they expire automatically.',
                  style: GoogleFonts.inter(
                    fontSize: 11.8,
                    height: 1.45,
                    color: mutedColor,
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 18),
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
                  elevation: 0,
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
                  ? 'Private rooms stay hidden and can only be joined with the room code.'
                  : 'Public rooms appear in Discover and still get a shareable room code.',
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

  Widget _buildLabel(String title, bool isDark) {
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
    required Color fillColor,
    required Color borderColor,
  }) {
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
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(color: AppTheme.primary, width: 1.2),
      ),
    );
  }

  Widget _buildMetaChip({
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentOption({
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
                ? AppTheme.primary.withValues(alpha: isDark ? 0.18 : 0.08)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.03)
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
    required _RoomDurationOption option,
    required bool isDark,
  }) {
    final selected = _selectedDurationDays == option.days;
    return InkWell(
      onTap: _isSubmitting ? null : () => _selectDuration(option),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? AppTheme.primary.withValues(alpha: isDark ? 0.18 : 0.08)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : const Color(0xFFF8FAFC)),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (option.locked)
              Icon(
                Icons.lock_rounded,
                size: 16,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              )
            else
              Icon(
                selected ? Icons.check_circle_rounded : Icons.schedule_rounded,
                size: 16,
                color: selected
                    ? AppTheme.primary
                    : (isDark ? Colors.white70 : const Color(0xFF475569)),
              ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.title,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  option.subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomDurationOption {
  final int days;
  final String title;
  final String subtitle;
  final bool locked;

  const _RoomDurationOption({
    required this.days,
    required this.title,
    required this.subtitle,
    this.locked = false,
  });
}
