import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/cloudinary_service.dart';
import '../services/ai_chat_local_service.dart';
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

class _ChatAttachment {
  final String name;
  final String url;
  final bool isPdf;

  const _ChatAttachment({
    required this.name,
    required this.url,
    required this.isPdf,
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
  final AiChatLocalService _localChat = AiChatLocalService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  final List<AIChatMessage> _messages = [];
  final List<_ChatAttachment> _attachments = [];
  bool _isUploadingAttachment = false;
  List<LocalAiChatSession> _sessions = [];
  String? _activeSessionId;
  bool _isHistoryLoading = true;

  static const List<String> _suggestions = [
    'Summarize Unit 2 from my latest PDF.',
    'Give me 5 MCQs on Operating Systems with answers.',
    'Explain stack vs queue with a real-world example.',
    'List key formulas from my notes for quick revision.',
  ];

  @override
  void initState() {
    super.initState();
    _loadStoredSessions();
  }

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

  String get _storageEmail {
    final email = _auth.userEmail;
    if (email == null || email.trim().isEmpty) return 'guest';
    return email.trim().toLowerCase();
  }

  String _newSessionId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _deriveSessionTitle(List<AIChatMessage> messages) {
    final firstUser = messages.firstWhere(
      (message) => message.isUser && message.content.trim().isNotEmpty,
      orElse: () => AIChatMessage(isUser: true, content: 'New chat'),
    );
    final normalized = firstUser.content
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return 'New chat';
    return normalized.length > 52
        ? '${normalized.substring(0, 52).trim()}...'
        : normalized;
  }

  LocalAiChatMessage _toLocalMessage(AIChatMessage message) {
    return LocalAiChatMessage(
      isUser: message.isUser,
      content: message.content,
      sources: message.sources
          .map(
            (source) => {
              'file_id': source.fileId,
              'title': source.title,
              'pages': {'start': source.startPage, 'end': source.endPage},
              'score': source.score,
              'file_url': source.fileUrl,
            },
          )
          .toList(),
      cached: message.cached,
      noLocal: message.noLocal,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  AIChatMessage _fromLocalMessage(LocalAiChatMessage message) {
    return AIChatMessage(
      isUser: message.isUser,
      content: message.content,
      sources: message.sources
          .map((source) => RagSource.fromJson(source))
          .toList(),
      cached: message.cached,
      noLocal: message.noLocal,
    );
  }

  Future<void> _persistCurrentSession() async {
    final sessionId = _activeSessionId ?? _newSessionId();
    final now = DateTime.now().toIso8601String();
    final session = LocalAiChatSession(
      id: sessionId,
      title: _deriveSessionTitle(_messages),
      updatedAt: now,
      messages: _messages.map(_toLocalMessage).toList(),
    );

    final updated = <LocalAiChatSession>[
      session,
      ..._sessions.where((item) => item.id != sessionId),
    ];

    await _localChat.saveSessions(
      userEmail: _storageEmail,
      collegeId: widget.collegeId,
      sessions: updated,
    );

    if (!mounted) return;
    setState(() {
      _activeSessionId = sessionId;
      _sessions = updated;
    });
  }

  Future<void> _loadStoredSessions() async {
    final loaded = await _localChat.loadSessions(
      userEmail: _storageEmail,
      collegeId: widget.collegeId,
    );

    if (!mounted) return;
    setState(() {
      _sessions = loaded;
      _isHistoryLoading = false;
      if (loaded.isNotEmpty) {
        final latest = loaded.first;
        _activeSessionId = latest.id;
        _messages
          ..clear()
          ..addAll(latest.messages.map(_fromLocalMessage));
      } else {
        _activeSessionId = _newSessionId();
      }
    });
    await _scrollToBottom();
  }

  Future<void> _startNewChat() async {
    if (_messages.isNotEmpty) {
      await _persistCurrentSession();
    }

    if (!mounted) return;
    setState(() {
      _activeSessionId = _newSessionId();
      _messages.clear();
      _attachments.clear();
      _controller.clear();
    });
  }

  Future<void> _openSession(LocalAiChatSession session) async {
    if (_messages.isNotEmpty) {
      await _persistCurrentSession();
    }

    if (!mounted) return;
    setState(() {
      _activeSessionId = session.id;
      _messages
        ..clear()
        ..addAll(session.messages.map(_fromLocalMessage));
      _attachments.clear();
      _controller.clear();
    });
    await _scrollToBottom();
  }

  Future<void> _deleteSession(String sessionId) async {
    final updated = _sessions
        .where((session) => session.id != sessionId)
        .toList();
    await _localChat.saveSessions(
      userEmail: _storageEmail,
      collegeId: widget.collegeId,
      sessions: updated,
    );

    if (!mounted) return;
    setState(() {
      _sessions = updated;
      if (_activeSessionId == sessionId) {
        _activeSessionId = _newSessionId();
        _messages.clear();
      }
    });
  }

  void _openHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.78,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        'Previous Chats',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
                          await _startNewChat();
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('New Chat'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _sessions.isEmpty
                      ? Center(
                          child: Text(
                            'No saved chats yet',
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: _sessions.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final session = _sessions[index];
                            final isActive = session.id == _activeSessionId;
                            final updatedAt =
                                DateTime.tryParse(session.updatedAt) ??
                                DateTime.now();
                            final subtitle = session.messages.isNotEmpty
                                ? session.messages.last.content
                                : 'No messages';

                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                Navigator.pop(sheetCtx);
                                await _openSession(session);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppTheme.primary.withValues(alpha: 0.14)
                                      : (isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.05,
                                              )
                                            : Colors.grey.shade50),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isActive
                                        ? AppTheme.primary.withValues(
                                            alpha: 0.5,
                                          )
                                        : (isDark
                                              ? Colors.white12
                                              : Colors.grey.shade200),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            session.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.black54,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${updatedAt.day}/${updatedAt.month}/${updatedAt.year} ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppTheme.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      onPressed: () =>
                                          _deleteSession(session.id),
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final hasAttachments = _attachments.isNotEmpty;
    if ((text.isEmpty && !hasAttachments) ||
        _isLoading ||
        _isUploadingAttachment) {
      return;
    }

    if (!_auth.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to use AI chat.')),
      );
      return;
    }

    final userPrompt = text.isEmpty
        ? 'Please analyze the attached files and help me study.'
        : text;
    final sendPrompt = _buildPromptWithAttachments(userPrompt);
    final userVisible = hasAttachments
        ? '$userPrompt\n\nAttachments: ${_attachments.map((a) => a.name).join(', ')}'
        : userPrompt;

    setState(() {
      _messages.add(AIChatMessage(isUser: true, content: userVisible));
      _isLoading = true;
      _controller.clear();
      _attachments.clear();
    });
    await _persistCurrentSession();
    await _scrollToBottom();

    try {
      final response = await _api.queryRag(
        question: sendPrompt,
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
      await _persistCurrentSession();
    } catch (e) {
      setState(() {
        _messages.add(
          AIChatMessage(
            isUser: false,
            content: e.toString().replaceFirst('Exception: ', ''),
          ),
        );
      });
      await _persistCurrentSession();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        await _scrollToBottom();
      }
    }
  }

  String _buildPromptWithAttachments(String basePrompt) {
    if (_attachments.isEmpty) return basePrompt;
    final attachmentLines = _attachments
        .map((a) => '- ${a.name} (${a.isPdf ? 'PDF' : 'Image'}): ${a.url}')
        .join('\n');
    return '$basePrompt\n\nUser attachments:\n$attachmentLines';
  }

  Future<void> _pickAttachment() async {
    if (_isUploadingAttachment || _isLoading) return;

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      withData: true,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
    );

    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final filename = file.name.toLowerCase();
    final isPdf = filename.endsWith('.pdf');

    setState(() => _isUploadingAttachment = true);
    try {
      final url = await CloudinaryService.uploadFile(file);
      if (!mounted) return;
      setState(() {
        _attachments.add(
          _ChatAttachment(name: file.name, url: url, isPdf: isPdf),
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${file.name} attached')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Attachment upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _attachments.length) return;
    setState(() => _attachments.removeAt(index));
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
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
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.04),
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
          backgroundColor: isDark
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.04),
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
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Chat',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            Text(
              widget.collegeName,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: isDark
                    ? AppTheme.darkTextMuted
                    : AppTheme.lightTextMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chat history',
            onPressed: _isHistoryLoading ? null : _openHistorySheet,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: (_messages.isEmpty && _attachments.isEmpty)
                ? null
                : _startNewChat,
            icon: const Icon(Icons.add_comment_outlined),
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
                        'Ask AI about your PDFs and images',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'I will search your study materials first. You can also attach images or PDFs with the paperclip button.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSuggestionChips(isDark),
                      const SizedBox(height: 24),
                    ],
                  ),
                ..._messages.map((m) {
                  return Align(
                    alignment: m.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _buildMessageBubble(m, isDark),
                    ),
                  );
                }),
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
                          color: isDark
                              ? AppTheme.darkBorder
                              : AppTheme.lightBorder,
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
              child: Column(
                children: [
                  if (_attachments.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(_attachments.length, (index) {
                            final attachment = _attachments[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.black12,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    attachment.isPdf
                                        ? Icons.picture_as_pdf_rounded
                                        : Icons.image_rounded,
                                    size: 14,
                                    color: AppTheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 160,
                                    ),
                                    child: Text(
                                      attachment.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _removeAttachment(index),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF111827)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? Colors.white12
                            : const Color(0xFFD6DEE8),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Attach image or PDF',
                          onPressed: (_isLoading || _isUploadingAttachment)
                              ? null
                              : _pickAttachment,
                          icon: _isUploadingAttachment
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.add_rounded,
                                  color: isDark
                                      ? Colors.white70
                                      : AppTheme.primary,
                                ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 6,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Message AI...',
                              hintStyle: GoogleFonts.inter(
                                color: isDark
                                    ? AppTheme.darkTextMuted
                                    : AppTheme.lightTextMuted,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: (_isLoading || _isUploadingAttachment)
                                ? Colors.grey
                                : AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: (_isLoading || _isUploadingAttachment)
                                ? null
                                : _sendMessage,
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
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
