import 'dart:convert';
import 'dart:ui';
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
import 'viewer/pdf_viewer_screen.dart';

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
  String content;
  List<RagSource> sources;
  bool cached;
  bool noLocal;

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

/// Context for pinning a RAG chat to a specific resource/PDF.
class ResourceContext {
  final String fileId;
  final String title;
  final String? subject;
  final String? semester;
  final String? branch;

  const ResourceContext({
    required this.fileId,
    required this.title,
    this.subject,
    this.semester,
    this.branch,
  });

  /// Human-readable label shown in the context banner.
  String get label {
    final parts = <String>[];
    if (semester != null && semester!.isNotEmpty) parts.add('Sem $semester');
    if (branch != null && branch!.isNotEmpty) parts.add(branch!);
    if (subject != null && subject!.isNotEmpty) parts.add(subject!);
    return parts.isEmpty ? title : parts.join(' · ');
  }
}

class AIChatScreen extends StatefulWidget {
  final String collegeId;
  final String collegeName;
  /// Optional: if set, all RAG queries are pinned to this resource.
  final ResourceContext? resourceContext;

  const AIChatScreen({
    super.key,
    required this.collegeId,
    required this.collegeName,
    this.resourceContext,
  });

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> with TickerProviderStateMixin {
  final BackendApiService _api = BackendApiService();
  final AuthService _auth = AuthService();
  final AiChatLocalService _localChat = AiChatLocalService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _splashAnimationController;
  late final Animation<double> _iconScaleAnimation;
  late final Animation<Offset> _iconSlideAnimation;
  late final Animation<double> _splashTitleAnimation;
  late final Animation<Offset> _titleSlideAnimation;
  late final Animation<double> _splashSubtitleAnimation;
  late final Animation<Offset> _subtitleSlideAnimation;
  late final AnimationController _suggestionsController;
  late final List<CurvedAnimation> _suggestionAnimations;
  late final List<CurvedAnimation> _suggestionFadeAnimations;

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
    _splashAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _iconScaleAnimation = CurvedAnimation(
      parent: _splashAnimationController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
    );
    _iconSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2), // Less slide, just a subtle pop
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _splashAnimationController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
    ));
    
    _splashTitleAnimation = CurvedAnimation(
      parent: _splashAnimationController,
      curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
    );
    _titleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(_splashTitleAnimation);

    _splashSubtitleAnimation = CurvedAnimation(
      parent: _splashAnimationController,
      curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
    );
    _subtitleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(_splashSubtitleAnimation);

    _suggestionsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _suggestionAnimations = List.generate(_suggestions.length, (index) {
      return CurvedAnimation(
        parent: _suggestionsController,
        curve: Interval(
          (index / _suggestions.length) * 0.5,
          1.0,
          curve: Curves.easeOutBack,
        ),
      );
    });
    _suggestionFadeAnimations = List.generate(_suggestions.length, (index) {
      return CurvedAnimation(
        parent: _suggestionsController,
        curve: Interval(
          (index / _suggestions.length) * 0.5,
          1.0,
          curve: Curves.easeOut,
        ),
      );
    });
    
    // Defer splash animation until after stored sessions load
    _loadStoredSessions();
  }

  /// Injects an AI greeting when chat is opened with a pinned resource.
  void _injectResourceGreeting() {
    final ctx = widget.resourceContext;
    if (ctx == null) return;

    final parts = <String>[];
    if (ctx.subject != null && ctx.subject!.isNotEmpty) parts.add(ctx.subject!);
    if (ctx.semester != null && ctx.semester!.isNotEmpty) parts.add('Semester ${ctx.semester}');
    if (ctx.branch != null && ctx.branch!.isNotEmpty) parts.add(ctx.branch!);

    final meta = parts.isEmpty ? '' : ' (${parts.join(', ')})';

    final greeting =
        'I have loaded "${ctx.title}"$meta. Ask me anything from this document — I will answer based on its contents. If I need to search beyond your notes, I will let you know.';

    setState(() {
      _messages.add(AIChatMessage(isUser: false, content: greeting));
    });
  }

  @override
  void dispose() {
    for (final anim in _suggestionAnimations) {
      anim.dispose();
    }
    for (final anim in _suggestionFadeAnimations) {
      anim.dispose();
    }
    _splashAnimationController.dispose();
    _suggestionsController.dispose();
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

    // If opened with a resource context, always start fresh so history
    // from unrelated sessions is not shown.
    if (widget.resourceContext != null) {
      _activeSessionId = _newSessionId();
      _messages.clear();
      _injectResourceGreeting();
    } else if (_messages.isEmpty && mounted) {
      _splashAnimationController.forward().then((_) {
        if (_messages.isEmpty && mounted) {
          _suggestionsController.forward();
        }
      });
    }

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

    // Reset and replay splash animations for the empty chat
    _splashAnimationController.reset();
    _suggestionsController.reset();
    _splashAnimationController.forward().then((_) {
      if (_messages.isEmpty && mounted) {
        _suggestionsController.forward();
      }
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

    AIChatMessage? aiMessage;
    var malformedChunkCount = 0;

    try {
      aiMessage = AIChatMessage(
        isUser: false,
        content: '',
      );

      setState(() {
        _messages.add(aiMessage!);
        _isLoading = false;
      });

      final stream = _api.queryRagStream(
        question: sendPrompt,
        collegeId: widget.collegeId,
        fileId: widget.resourceContext?.fileId,
        allowWeb: true,
      );

      await for (final chunkStr in stream) {
        if (!mounted) break;
        try {
          final chunk = jsonDecode(chunkStr);
          final type = chunk['type'];
          
          if (type == 'metadata') {
            final data = chunk['data'] as Map<String, dynamic>? ?? {};
            final sourcesRaw = (data['sources'] as List?) ?? const [];
            final sources = sourcesRaw
                .whereType<Map>()
                .map((s) => RagSource.fromJson(Map<String, dynamic>.from(s)))
                .toList();

            setState(() {
              aiMessage!.sources = sources;
              aiMessage!.noLocal = data['no_local'] == true;
            });
          } else if (type == 'chunk') {
            setState(() {
              aiMessage!.content += (chunk['text']?.toString() ?? '');
            });
            _scrollToBottom();
          } else if (type == 'error') {
            setState(() {
              aiMessage!.content += '\n\nError: ${chunk['message']}';
            });
            _scrollToBottom();
          } else if (type == 'done') {
            // Done
          }
        } catch (e, st) {
          debugPrint('Chunk parse error: $e\nStack: $st');
          malformedChunkCount++;
        }
      }
      
      if (malformedChunkCount > 0) {
        debugPrint('Stream finished with $malformedChunkCount malformed chunks.');
      }
      
      await _persistCurrentSession();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (aiMessage != null) {
            aiMessage.content += '\n\n${e.toString().replaceFirst('Exception: ', '')}';
          } else {
            _messages.add(
              AIChatMessage(
                isUser: false,
                content: e.toString().replaceFirst('Exception: ', ''),
              ),
            );
          }
        });
        await _persistCurrentSession();
      }
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
        ? (isDark ? AppTheme.iosBlueDark : AppTheme.iosBlueLight)
        : (isDark ? AppTheme.iosBubbleDark : AppTheme.iosBubbleLight);
    final textColor = msg.isUser
        ? Colors.white
        : (isDark ? Colors.white : Colors.black);

    return Container(
      margin: EdgeInsets.only(
        top: 6,
        bottom: 6,
        left: msg.isUser ? 48 : 0,
        right: msg.isUser ? 0 : 48,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(msg.isUser ? 20 : 4),
          bottomRight: Radius.circular(msg.isUser ? 4 : 20),
        ),
        boxShadow: msg.isUser
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!msg.isUser)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.asset('assets/images/ai_logo.png', width: 14, height: 14),
                ),
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
                          if (uri != null) {
                            final isInternal = uri.host.endsWith('.mystudyspace.me');
                            if (isInternal) {
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PdfViewerScreen(
                                    pdfUrl: s.fileUrl!,
                                    title: s.title,
                                    resourceId: s.fileId,
                                    collegeId: widget.collegeId,
                                  ),
                                ),
                              );
                            } else if (await canLaunchUrl(uri)) {
                              if (!mounted) return;
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            } else {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not open ${s.title}')),
                              );
                            }
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
            FocusManager.instance.primaryFocus?.unfocus();
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
          ? const Color(0xFF000000)
          : const Color(0xFFF2F2F7),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: (isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7)).withValues(alpha: 0.8),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
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
            child: _messages.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SlideTransition(
                            position: _iconSlideAnimation,
                            child: ScaleTransition(
                              scale: _iconScaleAnimation,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset(
                                  'assets/images/ai_logo.png',
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SlideTransition(
                            position: _titleSlideAnimation,
                            child: FadeTransition(
                              opacity: _splashTitleAnimation,
                              child: Text(
                                'How can I help you study today?',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : Colors.black87,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SlideTransition(
                            position: _subtitleSlideAnimation,
                            child: FadeTransition(
                              opacity: _splashSubtitleAnimation,
                              child: Text(
                                'I can analyze your notes, summarize PDFs, or generate practice questions based on your specific college materials.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: List.generate(_suggestions.length, (index) {
                              final animation = _suggestionAnimations[index];
                              return ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: _suggestionFadeAnimations[index],
                                  child: ActionChip(
                                    label: Text(
                                      _suggestions[index],
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                    backgroundColor: isDark
                                        ? Colors.white10
                                        : Colors.black.withValues(alpha: 0.05),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: isDark ? Colors.white12 : Colors.black12,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    onPressed: () {
                                      _controller.text = _suggestions[index];
                                      FocusManager.instance.primaryFocus?.unfocus();
                                    },
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE9E9EB),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                                bottomLeft: Radius.circular(4),
                                bottomRight: Radius.circular(20),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const BrandedLoader(
                              compact: true,
                              showQuotes: false,
                              message: 'Thinking...',
                            ),
                          ),
                        );
                      }
                      
                      final m = _messages[index];
                      return Align(
                        alignment: m.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: _buildMessageBubble(m, isDark),
                        ),
                      );
                    },
                  ),
          ),
          // Input area
          SafeArea(
            top: false,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7)).withValues(alpha: 0.85),
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
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
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? Colors.transparent
                            : const Color(0xFFD1D1D6),
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
            ),
          ),
        ],
      ),
    );
  }
}
