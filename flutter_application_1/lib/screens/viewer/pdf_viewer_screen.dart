import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/ai_study_tools_sheet.dart';
import '../../widgets/branded_loader.dart';
import '../../widgets/paywall_dialog.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final String? resourceId;
  final String? collegeId;

  const PdfViewerScreen({
    super.key,
    required this.pdfUrl,
    required this.title,
    this.resourceId,
    this.collegeId,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  final BackendApiService _api = BackendApiService();
  final SubscriptionService _subscriptionService = SubscriptionService();

  late PdfViewerController _pdfViewerController;
  late PdfTextSearchResult _searchResult;
  WebViewController? _webViewController;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isNightMode = false;

  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _searchSequence = 0;
  VoidCallback? _pdfSearchListener;

  bool _isOcrSearching = false;
  List<Map<String, dynamic>> _ocrMatches = [];
  String? _ocrSearchError;

  String get _urlPath => Uri.tryParse(widget.pdfUrl)?.path.toLowerCase() ?? '';

  bool get _isNetwork => widget.pdfUrl.startsWith('http');

  bool get _isPdf => _urlPath.endsWith('.pdf');

  bool get _isOfficeDoc {
    return _urlPath.endsWith('.doc') ||
        _urlPath.endsWith('.docx') ||
        _urlPath.endsWith('.ppt') ||
        _urlPath.endsWith('.pptx') ||
        _urlPath.endsWith('.xls') ||
        _urlPath.endsWith('.xlsx');
  }

  bool _isAllowedOfficeViewerNavigation(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    if (uri.scheme == 'about') return true;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'docs.google.com';
  }

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _searchResult = PdfTextSearchResult();

    if (_isOfficeDoc && !kIsWeb) {
      _initWebView();
    } else if (!_isNetwork && kIsWeb) {
      _isLoading = false;
      _hasError = true;
      _errorMessage = 'Local files not supported on web.';
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    if (_pdfSearchListener != null) {
      _searchResult.removeListener(_pdfSearchListener!);
    }
    _pdfViewerController.dispose();
    super.dispose();
  }

  void _initWebView() {
    final encodedUrl = Uri.encodeComponent(widget.pdfUrl);
    final googleDocsUrl = 'https://docs.google.com/gview?embedded=true&url=$encodedUrl';

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isAllowedOfficeViewerNavigation(request.url)) {
              return NavigationDecision.navigate;
            }
            debugPrint(
              'Blocked unexpected Office WebView URL: ${request.url}',
            );
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                  _errorMessage = error.description;
                });
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(googleDocsUrl));
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _clearSearchState();
      }
    });
  }

  void _clearSearchState() {
    if (_isPdf) {
      if (_pdfSearchListener != null) {
        _searchResult.removeListener(_pdfSearchListener!);
        _pdfSearchListener = null;
      }
      _pdfViewerController.clearSelection();
      _searchResult.clear();
    }
    _searchController.clear();
    _searchDebounce?.cancel();
    _ocrMatches = [];
    _ocrSearchError = null;
    _isOcrSearching = false;
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    final requestId = ++_searchSequence;

    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(_clearSearchState);
      return;
    }

    if (_isPdf) {
      if (_pdfSearchListener != null) {
        _searchResult.removeListener(_pdfSearchListener!);
      }
      
      final result = _pdfViewerController.searchText(trimmed);
      _searchResult = result;
      
      _pdfSearchListener = () {
        if (mounted) {
          setState(() {});
          if (!kIsWeb && result.isSearchCompleted && result.totalInstanceCount == 0 && requestId == _searchSequence && !_isOcrSearching) {
            _runOcrFallbackSearch(trimmed, requestId);
          }
        }
      };
      
      result.addListener(_pdfSearchListener!);
      
      setState(() {
        _ocrMatches = [];
        _ocrSearchError = null;
        _isOcrSearching = false;
      });
    }
  }

  Future<void> _runOcrFallbackSearch(String query, int requestId) async {
    if (!_isPdf || widget.resourceId == null || widget.resourceId!.isEmpty) return;

    setState(() {
      _isOcrSearching = true;
      _ocrSearchError = null;
      _ocrMatches = [];
    });

    try {
      final data = await _api.findInAiText(
        fileId: widget.resourceId!,
        query: query,
        collegeId: widget.collegeId,
        useOcr: true,
        forceOcr: true,
        ocrProvider: 'google',
      );

      if (!mounted || requestId != _searchSequence) return;

      final rawMatches = (data['matches'] as List?) ?? const [];
      final matches = rawMatches
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      setState(() {
        _ocrMatches = matches;
        _isOcrSearching = false;
      });
    } catch (e) {
      if (!mounted || requestId != _searchSequence) return;
      debugPrint('OCR search failed: $e');
      setState(() {
        _isOcrSearching = false;
        _ocrSearchError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _openOcrMatchesSheet() {
    if (_ocrMatches.isEmpty) return;
    final isDark = _isNightMode;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                  child: Row(
                    children: [
                      Text(
                        'OCR Matches (${_ocrMatches.length})',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close OCR matches',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _ocrMatches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final snippet = _ocrMatches[index]['snippet']?.toString() ?? '';
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkCard : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          snippet,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.5,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
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

  void _openAiTools() {
    final resourceId = widget.resourceId;
    if (resourceId == null || resourceId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => AiStudyToolsSheet(
        resourceId: resourceId,
        resourceTitle: widget.title,
        collegeId: widget.collegeId,
      ),
    );
  }

  Future<void> _performDownloadOrLaunch() async {
    try {
      final uri = Uri.parse(widget.pdfUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open link. Please try again.')),
        );
      }
    } catch (e) {
      debugPrint('Failed to launch URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open link.')),
        );
      }
    }
  }

  Future<void> _handleDownload() async {
    final isPremium = await _subscriptionService.isPremium();
    if (!mounted) return;

    if (!isPremium) {
      final messenger = ScaffoldMessenger.of(context);
      showDialog(
        context: context,
        builder: (context) => PaywallDialog(
          onSuccess: () {
            if (!mounted) return;
            messenger.showSnackBar(const SnackBar(content: Text('Premium unlocked! Downloading...')));
            _performDownloadOrLaunch();
          },
        ),
      );
      return;
    }

    await _performDownloadOrLaunch();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isNightMode ? const Color(0xFF121212) : AppTheme.lightBackground;
    final textColor = _isNightMode ? Colors.white : Colors.black;
    final appBarColor = _isNightMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_showSearch) {
              _toggleSearch();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          widget.title,
          style: GoogleFonts.inter(color: textColor, fontSize: 16, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: _showSearch
            ? PreferredSize(
                preferredSize: const Size.fromHeight(70),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _isNightMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: textColor.withValues(alpha: 0.75), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            onChanged: _onSearchChanged,
                            onSubmitted: _performSearch,
                            style: GoogleFonts.inter(color: textColor, fontSize: 15),
                            cursorColor: textColor,
                            decoration: InputDecoration(
                              hintText: 'Find in PDF...',
                              hintStyle: GoogleFonts.inter(color: textColor.withValues(alpha: 0.5), fontSize: 14),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _performSearch('');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          if (_isPdf)
            IconButton(
              icon: Icon(_showSearch ? Icons.close_rounded : Icons.search_rounded),
              onPressed: _toggleSearch,
              tooltip: 'Find in PDF',
            ),
          if (_showSearch && _isPdf) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: Text(
                  '${_searchResult.currentInstanceIndex}/${_searchResult.totalInstanceCount}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: textColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              tooltip: 'Previous match',
              onPressed: _searchResult.hasResult ? () => _searchResult.previousInstance() : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              tooltip: 'Next match',
              onPressed: _searchResult.hasResult ? () => _searchResult.nextInstance() : null,
            ),
          ],
          if (widget.resourceId != null && widget.resourceId!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: _openAiTools,
              tooltip: 'AI Study Tools',
            ),
          if (_isPdf && _isNetwork)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: _handleDownload,
              tooltip: 'Download',
            ),
          if (_isPdf)
            IconButton(
              icon: Icon(_isNightMode ? Icons.light_mode : Icons.dark_mode_rounded),
              onPressed: () => setState(() => _isNightMode = !_isNightMode),
              tooltip: _isNightMode ? 'Light Mode' : 'Night Mode',
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_hasError)
            _buildErrorState()
          else if (_isPdf)
            _buildPdfContent()
          else if (_isOfficeDoc && _webViewController != null && !kIsWeb)
            WebViewWidget(controller: _webViewController!)
          else if (_isOfficeDoc && kIsWeb)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.browser_not_supported_rounded, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Office document viewing is not fully supported on Web natively.',
                    style: GoogleFonts.inter(color: Colors.grey, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _handleDownload,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download to View'),
                  )
                ],
              ),
            )
          else
            _buildUnsupportedContent(),
          if (_showSearch && (_isOcrSearching || _ocrMatches.isNotEmpty || _ocrSearchError != null))
            Positioned(
              top: 0,
              left: 12,
              right: 12,
              child: _buildOcrStatusCard(),
            ),
          if (_isLoading)
            const Center(child: BrandedLoader(message: 'Loading Document...')),
        ],
      ),
    );
  }

  Widget _buildOcrStatusCard() {
    final isDark = _isNightMode;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _isNightMode ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isNightMode ? AppTheme.darkBorder : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          if (_isOcrSearching)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isOcrSearching
                  ? 'No embedded text match. Searching OCR text...'
                  : _ocrMatches.isNotEmpty
                      ? 'Found ${_ocrMatches.length} OCR matches for this PDF.'
                      : (_ocrSearchError ?? 'No OCR match found'),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isNightMode ? Colors.white70 : const Color(0xFF334155),
              ),
            ),
          ),
          if (_ocrMatches.isNotEmpty)
            TextButton(
              onPressed: _openOcrMatchesSheet,
              child: const Text('View'),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfContent() {
    if (_isNightMode) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
        child: _buildSfPdfViewer(),
      );
    }
    return _buildSfPdfViewer();
  }

  Widget _buildSfPdfViewer() {
    void onLoaded(PdfDocumentLoadedDetails details) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }
    }
    void onFailed(PdfDocumentLoadFailedDetails details) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = details.description;
        });
      }
    }

    if (_isNetwork) {
      return SfPdfViewer.network(
        widget.pdfUrl,
        key: _pdfViewerKey,
        controller: _pdfViewerController,
        onDocumentLoaded: onLoaded,
        onDocumentLoadFailed: onFailed,
        enableDoubleTapZooming: true,
      );
    } else {
      String filePath = widget.pdfUrl;
      try {
        if (!kIsWeb) {
          final uri = Uri.tryParse(filePath);
          if (uri != null && uri.scheme == 'file') {
            filePath = uri.toFilePath();
          }
          return SfPdfViewer.file(
            File(filePath),
            key: _pdfViewerKey,
            controller: _pdfViewerController,
            onDocumentLoaded: onLoaded,
            onDocumentLoadFailed: onFailed,
            enableDoubleTapZooming: true,
          );
        } else {
          return _buildUnsupportedContent();
        }
      } catch (e) {
        debugPrint('Failed to load local PDF file: $e');
        return _buildErrorState();
      }
    }
  }

  Widget _buildUnsupportedContent() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () async {
          final uri = Uri.parse(widget.pdfUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        icon: const Icon(Icons.open_in_new),
        label: const Text('Open External'),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: AppTheme.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load document',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage.isNotEmpty ? _errorMessage : 'An unknown error occurred',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
