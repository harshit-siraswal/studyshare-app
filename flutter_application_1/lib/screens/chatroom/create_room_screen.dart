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

  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty &&
      (_selectedTags.isNotEmpty || _tagController.text.trim().isNotEmpty);

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

    final typedTag = _tagController.text.trim();
    if (typedTag.isNotEmpty) {
      _addTag(typedTag);
      if (_errorMessage != null) {
        return;
      }
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
    } catch (e) {
      debugPrint('Error creating room: $e');
      _setError(
        'Failed to create room: ${e.toString().replaceAll('Exception: ', '')}',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF191919) : Colors.white; 
    final textColor = isDark ? const Color(0xFFD4D4D4) : const Color(0xFF37352F);
    final mutedColor = isDark ? const Color(0xFF9B9A97) : const Color(0xFF9B9A97);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextButton(
              onPressed: (_isSubmitting || !_isFormValid) ? null : _submit,
              style: TextButton.styleFrom(
                foregroundColor: isDark ? Colors.white : Colors.black,
                disabledForegroundColor: mutedColor,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                backgroundColor: (_isSubmitting || !_isFormValid) 
                    ? Colors.transparent 
                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Create Room',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Untitled Room',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: mutedColor.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 32),
              
              _buildPropertyRow(
                icon: Icons.notes_rounded,
                label: 'Description',
                isDark: isDark,
                mutedColor: mutedColor,
                child: TextField(
                  controller: _descriptionController,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.inter(fontSize: 14, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Empty',
                    hintStyle: GoogleFonts.inter(fontSize: 14, color: mutedColor.withValues(alpha: 0.6)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.only(top: 2, bottom: 2),
                  ),
                ),
              ),
              Divider(color: isDark ? Colors.white10 : Colors.black12, height: 24),
              
              _buildPropertyRow(
                icon: Icons.tag_rounded,
                label: 'Tags',
                isDark: isDark,
                mutedColor: mutedColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ..._selectedTags.map((tag) => _buildTagPill(tag, isDark, true)),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _tagController,
                            style: GoogleFonts.inter(fontSize: 14, color: textColor),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: _selectedTags.isEmpty ? 'Empty' : 'Add...',
                              hintStyle: GoogleFonts.inter(fontSize: 14, color: mutedColor.withValues(alpha: 0.6)),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.only(top: 2, bottom: 2),
                            ),
                            onSubmitted: _addTag,
                          ),
                        ),
                      ],
                    ),
                    if (_tagSuggestions.where((t) => !_selectedTags.contains(t)).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _tagSuggestions
                            .where((t) => !_selectedTags.contains(t))
                            .map((tag) => GestureDetector(
                                  onTap: () => _addTag(tag),
                                  child: _buildTagPill(tag, isDark, false),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(color: isDark ? Colors.white10 : Colors.black12, height: 24),
              
              _buildPropertyRow(
                icon: Icons.timer_outlined,
                label: 'Expiry',
                isDark: isDark,
                mutedColor: mutedColor,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _durationOptions.map((opt) => _buildDurationPill(opt, isDark, textColor, mutedColor)).toList(),
                ),
              ),
              Divider(color: isDark ? Colors.white10 : Colors.black12, height: 24),
              
              _buildPropertyRow(
                icon: _isPrivate ? Icons.lock_outline : Icons.public,
                label: 'Privacy',
                isDark: isDark,
                mutedColor: mutedColor,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _isPrivate = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: !_isPrivate 
                              ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)) 
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Public',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: !_isPrivate ? textColor : mutedColor,
                            fontWeight: !_isPrivate ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _isPrivate = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isPrivate 
                              ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)) 
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Private',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: _isPrivate ? textColor : mutedColor,
                            fontWeight: _isPrivate ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              if (_errorMessage != null) ...[
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: Colors.red.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.inter(color: Colors.red.shade400, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPropertyRow({
    required IconData icon,
    required String label,
    required bool isDark,
    required Color mutedColor,
    required Widget child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Icon(icon, size: 16, color: mutedColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildTagPill(String tag, bool isDark, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected 
            ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05))
            : Colors.transparent,
        border: Border.all(
          color: isSelected 
              ? Colors.transparent 
              : (isDark ? Colors.white24 : Colors.black26),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() => _selectedTags.remove(tag)),
              child: Icon(
                Icons.close,
                size: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDurationPill(_RoomDurationOption option, bool isDark, Color textColor, Color mutedColor) {
    final isSelected = _selectedDurationDays == option.days;
    return GestureDetector(
      onTap: () => _selectDuration(option),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected 
              ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected 
                ? Colors.transparent 
                : (isDark ? Colors.white10 : Colors.black12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              option.title,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isSelected ? textColor : mutedColor,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            if (option.locked) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.lock_outline,
                size: 12,
                color: mutedColor,
              ),
            ] else ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  option.subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: mutedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
