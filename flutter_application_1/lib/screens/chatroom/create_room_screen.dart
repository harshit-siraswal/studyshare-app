import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/theme.dart';
import '../../services/subscription_service.dart';
import '../../services/supabase_service.dart';

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
    } catch (error) {
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
    final fillColor = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF7F7FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Create Room',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionLabel('Room Name', isDark),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: _fieldDecoration(
                  hintText: 'Placement Prep 2026',
                  fillColor: fillColor,
                ),
              ),
              const SizedBox(height: 18),
              _buildSectionLabel('Description', isDark),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: _fieldDecoration(
                  hintText: 'What is this room for?',
                  fillColor: fillColor,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _buildSectionLabel('Tags', isDark),
                  const SizedBox(width: 8),
                  Text(
                    '(Required)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: _fieldDecoration(
                        hintText: 'Add a tag like #dsa',
                        fillColor: fillColor,
                      ),
                      onSubmitted: _addTag,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSubmitting ? null : _addTag,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                    ),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._selectedTags.map(
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
                  ),
                  if (_selectedTags.isEmpty)
                    ...const ['#placement', '#hackathon', '#dsa'].map(
                      (tag) => ActionChip(
                        label: Text(tag),
                        onPressed: _isSubmitting ? null : () => _addTag(tag),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              _buildSectionLabel('Visibility', isDark),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Public'),
                      selected: !_isPrivate,
                      onSelected: _isSubmitting
                          ? null
                          : (selected) {
                              if (selected) {
                                setState(() => _isPrivate = false);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Private'),
                      selected: _isPrivate,
                      onSelected: _isSubmitting
                          ? null
                          : (selected) {
                              if (selected) {
                                setState(() => _isPrivate = true);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _buildSectionLabel('Duration', isDark),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Permanent Room',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              if (!_isPremium) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'PRO',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isPremium
                                ? 'Keep the room active beyond the default temporary period.'
                                : 'Free users get temporary rooms. Upgrade for permanent rooms.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isPermanent,
                      onChanged: (!_isPremium || _isLoadingPremium || _isSubmitting)
                          ? null
                          : (value) {
                              setState(() => _isPermanent = value);
                            },
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
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Create Room',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required Color fillColor,
  }) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildSectionLabel(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }
}
