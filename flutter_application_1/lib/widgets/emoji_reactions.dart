import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
/// A widget that displays emoji reactions for a comment.
/// Shows reaction counts and allows users to add/remove their reactions.
class EmojiReactions extends StatefulWidget {
  final String commentId;
  final String commentType; // 'notice' or 'post'
  final bool compact; // If true, show minimal UI
  final SupabaseService? supabaseService;
  final AuthService? authService;
  
  const EmojiReactions({
    super.key,
    required this.commentId,
    required this.commentType,
    this.compact = false,
    this.supabaseService,
    this.authService,
  });

  @override
  State<EmojiReactions> createState() => _EmojiReactionsState();
}

class _EmojiReactionsState extends State<EmojiReactions> {
  late final SupabaseService _supabaseService;
  late final AuthService _authService;
  
  // Available emoji reactions
  static const List<String> _availableEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
  
  Map<String, List<String>> _reactions = {};
  bool _isLoading = true;
  
  String? get _currentUserEmail => _authService.userEmail;

  @override
  void initState() {
    super.initState();
    _supabaseService = widget.supabaseService ?? SupabaseService();
    _authService = widget.authService ?? AuthService();
    _loadReactions();
  }

  Future<void> _loadReactions() async {
    try {
      final result = await _supabaseService.getCommentReactions(
        commentId: widget.commentId,
        commentType: widget.commentType,
      );
      
      if (mounted) {
        setState(() {
          _reactions = Map<String, List<String>>.from(
            (result['reactions'] as Map).map(
              (key, value) => MapEntry(key as String, List<String>.from(value)),
            ),
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load reactions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  Future<void> _toggleReaction(String emoji) async {
    if (_currentUserEmail == null) return;
    
    try {
      final added = await _supabaseService.toggleReaction(
        commentId: widget.commentId,
        commentType: widget.commentType,
        userEmail: _currentUserEmail!,
        emoji: emoji,
      );
      
      // Update UI after successful toggle
      if (mounted) {
        setState(() {
          if (added) {
            _reactions.putIfAbsent(emoji, () => []);
            _reactions[emoji]!.add(_currentUserEmail!);
          } else {
            _reactions[emoji]?.remove(_currentUserEmail!);
            if (_reactions[emoji]?.isEmpty ?? false) {
              _reactions.remove(emoji);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add reaction. Please try again.')),
        );
      }
    }
  }

  bool _hasReacted(String emoji) {
    return _currentUserEmail != null && 
           (_reactions[emoji]?.contains(_currentUserEmail!) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_isLoading) {
      return const SizedBox(height: 24);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Display existing reactions
        if (_reactions.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _reactions.entries.map((entry) {
              final emoji = entry.key;
              final users = entry.value;
              final hasReacted = _hasReacted(emoji);
              
              return GestureDetector(
                onTap: () => _toggleReaction(emoji),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasReacted
                        ? AppTheme.primary.withValues(alpha: 0.15)
                        : (isDark ? const Color(0xFF334155) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(16),
                    border: hasReacted
                        ? Border.all(color: AppTheme.primary.withValues(alpha: 0.5), width: 1)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        users.length.toString(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hasReacted 
                              ? AppTheme.primary 
                              : (isDark ? Colors.white70 : Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        
        // Add reaction button
        if (!widget.compact)
          Padding(
            padding: EdgeInsets.only(top: _reactions.isNotEmpty ? 8 : 0),
            child: GestureDetector(
              onTap: () => _showEmojiPicker(context, isDark),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_reaction_outlined,
                      size: 16,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'React',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showEmojiPicker(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add Reaction',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _availableEmojis.map((emoji) {
                final hasReacted = _hasReacted(emoji);
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _toggleReaction(emoji);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: hasReacted
                          ? AppTheme.primary.withValues(alpha: 0.2)
                          : (isDark ? const Color(0xFF334155) : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(12),
                      border: hasReacted
                          ? Border.all(color: AppTheme.primary, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );
  }
}

/// A simple inline emoji button for quick reactions.
/// Shows the most popular reaction for a comment with a quick-add button.
class QuickEmojiReaction extends StatelessWidget {
  final String commentId;
  final String commentType;
  final VoidCallback? onTap;
  
  const QuickEmojiReaction({
    super.key,
    required this.commentId,
    required this.commentType,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👍', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 2),
            Icon(
              Icons.add,
              size: 12,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ],
        ),
      ),
    );
  }
}
