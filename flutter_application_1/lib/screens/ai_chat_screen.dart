import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../widgets/branded_loader.dart';

class RagSource {
  final String fileId;
  final String title;
  final int? startPage;
  final int? endPage;
  final double? score;
  final String? fileUrl;

  RagSource({
    required this.fileId,
    required this.title,
    this.startPage,
    this.endPage,
    this.score,
    this.fileUrl,
  });

  factory RagSource.fromJson(Map<String, dynamic> json) {
    final pages = json['pages'] as Map<String, dynamic>?;
    final start = pages?['start'];
    final end = pages?['end'];
    return RagSource(
      fileId: json['file_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Source',
      startPage: start is int ? start : int.tryParse(start?.toString() ?? ''),
      endPage: end is int ? end : int.tryParse(end?.toString() ?? ''),
      score: (json['score'] is num) ? (json['score'] as num).toDouble() : null,
      fileUrl: json['file_url']?.toString(),
    );
  }
}

class AIChatMessage {
  final bool isUser;
  final String content;
  final List<RagSource> sources;
  final bool cached;
  final bool noLocal;

  AIChatMessage({
    required this.isUser,
    required this.content,
    this.sources = const [],
    this.cached = false,
    this.noLocal = false,
  });
}

class AIChatScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;

  const AIChatScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
  });

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final BackendApiService _api = BackendApiService();
  final AuthService _auth = AuthService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  final List<AIChatMessage> _messages = [];

  static const List<String> _suggestions = [
    'Summarize Unit 2 from my latest PDF.',
    'Give me 5 MCQs on Operating Systems with answers.',
    'Explain stack vs queue with a real-world example.',
    'List key formulas from my notes for quick revision.',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) return;
    await Future.delayed(const Duration(milliseconds: 50));
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (!_auth.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to use AI chat.')),
      );
      return;
    }

    setState(() {
      _messages.add(AIChatMessage(isUser: true, content: text));
      _isLoading = true;
      _controller.clear();
    });
    await _scrollToBottom();

    try {
      final response = await _api.queryRag(
        question: text,
        collegeId: widget.collegeId,
        allowWeb: true,
      );

      final sourcesRaw = (response['sources'] as List?) ?? const [];
      final sources = sourcesRaw
          .whereType<Map>()
          .map((s) => RagSource.fromJson(Map<String, dynamic>.from(s)))
          .toList();

      setState(() {
        _messages.add(
          AIChatMessage(
            isUser: false,
            content: response['answer']?.toString() ?? 'No answer returned.',
            sources: sources,
            cached: response['cached'] == true,
            noLocal: response['no_local'] == true,
          ),
        );
      });
    } catch (e) {
      setState(() {
        _messages.add(
          AIChatMessage(
            isUser: false,
            content: e.toString().replaceFirst('Exception: ', ''),
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        await _scrollToBottom();
      }
    }
  }

  Widget _buildMessageBubble(AIChatMessage msg, bool isDark) {
    final bgColor = msg.isUser
        ? AppTheme.primary.withValues(alpha: isDark ? 0.35 : 0.2)
        : (isDark ? AppTheme.darkCard : Colors.white);
    final textColor = msg.isUser
        ? (isDark ? Colors.white : AppTheme.darkTextPrimary)
        : (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: msg.isUser
              ? Colors.transparent
              : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!msg.isUser)
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Studyspace AI',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
                if (msg.noLocal) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'No PDF match',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (msg.cached) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Cached',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: AppTheme.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          if (!msg.isUser) const SizedBox(height: 8),
          Text(
            msg.content,
            style: GoogleFonts.inter(fontSize: 14, color: textColor),
          ),
          if (!msg.isUser && msg.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Sources',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: msg.sources.map((s) {
                final label = s.startPage != null && s.endPage != null
                    ? '${s.title} (p${s.startPage}-${s.endPage})'
                    : s.title;
                return InkWell(
                  onTap: s.fileUrl == null
                      ? null
                      : () async {
                          final uri = Uri.tryParse(s.fileUrl!);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionChips(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _suggestions.map((s) {
        return ActionChip(
          label: Text(
            s,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          onPressed: () {
            _controller.text = s;
            FocusScope.of(context).requestFocus(FocusNode());
          },
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Chat',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            Text(
              widget.collegeName,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear chat',
            onPressed: _messages.isEmpty
                ? null
                : () {
                    setState(() => _messages.clear());
                  },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                if (_messages.isEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Image.asset(
                            'assets/icon/app_icon.png',
                            width: 56,
                            height: 56,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Text(
                        'Ask AI about your PDFs',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'I will search your study materials first. If nothing matches, I will answer generally.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSuggestionChips(isDark),
                      const SizedBox(height: 24),
                    ],
                  ),
                ..._messages.map((m) {
                  return Align(
                    alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _buildMessageBubble(m, isDark),
                    ),
                  );
                }).toList(),
                if (_isLoading)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                        ),
                      ),
                      child: const BrandedLoader(
                        compact: true,
                        showQuotes: false,
                        message: 'Thinking...',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Ask about your PDFs...',
                        hintStyle: GoogleFonts.inter(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isLoading ? null : _sendMessage,
                    icon: Icon(
                      Icons.send_rounded,
                      color: _isLoading ? Colors.grey : AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
