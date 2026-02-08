import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../config/theme.dart';
import '../../widgets/branded_loader.dart';
import '../../services/subscription_service.dart';
import '../../widgets/paywall_dialog.dart';
import '../../widgets/ai_study_tools_sheet.dart';

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
  late PdfViewerController _pdfViewerController;
  late PdfTextSearchResult _searchResult;
  WebViewController? _webViewController;
  
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isNightMode = false;  
  // Search State
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  String get _urlPath => Uri.tryParse(widget.pdfUrl)?.path.toLowerCase() ?? '';

  bool get _isPdf {
    return _urlPath.endsWith('.pdf');
  }

  bool get _isOfficeDoc {
    return _urlPath.endsWith('.doc') || 
           _urlPath.endsWith('.docx') || 
           _urlPath.endsWith('.ppt') || 
           _urlPath.endsWith('.pptx') || 
           _urlPath.endsWith('.xls') || 
           _urlPath.endsWith('.xlsx');
  }

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _searchResult = PdfTextSearchResult();

    if (_isOfficeDoc && !kIsWeb) {
      _initWebView();
    }
  }

  void _initWebView() {
    // encodeURIComponent equivalent
    final encodedUrl = Uri.encodeComponent(widget.pdfUrl);
    final googleDocsUrl = 'https://docs.google.com/gview?embedded=true&url=$encodedUrl';

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView Error: ${error.description}');
            // Show error UI only for main frame failures
            if (error.isForMainFrame ?? false) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                  _errorMessage = error.description ?? 'Failed to load document';
                });
              }
            }
          },        ),
      )
      ..loadRequest(Uri.parse(googleDocsUrl));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearch(String query) {
     if (query.isEmpty) return;
     if (_isPdf) {
       setState(() {
         _searchResult = _pdfViewerController.searchText(query);
       });
     }
  }
  
  void _showSearchDialog() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        if (_isPdf) {
          _pdfViewerController.clearSelection();
          _searchResult.clear();
        }
        _searchController.clear();
      }
    });
  }

  void _openAiTools() {
    final resourceId = widget.resourceId;
    if (resourceId == null || resourceId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AiStudyToolsSheet(
        resourceId: resourceId,
        resourceTitle: widget.title,
        collegeId: widget.collegeId,
      ),
    );
  }

  final SubscriptionService _subscriptionService = SubscriptionService();
  Future<void> _handleDownload() async {
    final isPremium = await _subscriptionService.isPremium();
    
    if (!mounted) return;

    if (!isPremium) {
      // Capture context safety for async callback
      final messenger = ScaffoldMessenger.of(context);
      
      showDialog(
        context: context,
        builder: (context) => PaywallDialog(
          onSuccess: () {
             if (!mounted) return;
             // Use captured messenger
             messenger.showSnackBar(const SnackBar(content: Text('Premium Unlocked! Downloading...')));
             // Retry download - recursion is okay here as isPremium should be true now
             _handleDownload();
          },        ),
      );
    } else {
       try {
         final uri = Uri.parse(widget.pdfUrl);
         if (await canLaunchUrl(uri)) {
           await launchUrl(uri, mode: LaunchMode.externalApplication);
         } else {
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Unable to open link. Please try again.')),
             );
           }
         }
       } catch (e) {
          debugPrint('Error downloading URL: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to open link.')),
            );
          }
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Night mode colors
    final bgColor = _isNightMode ? const Color(0xFF121212) : AppTheme.lightBackground;
    final textColor = _isNightMode ? Colors.white : Colors.black;
    final appBarColor = _isNightMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      // Timer is handled globally by GlobalTimerOverlay
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_showSearch) {
              _showSearchDialog(); // Use back to close search if open
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: _showSearch 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: GoogleFonts.inter(color: textColor),
              cursorColor: textColor,
              onSubmitted: _handleSearch,
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
                filled: true,
                fillColor: _isNightMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                     _searchController.clear();
                     if(_isPdf) _pdfViewerController.clearSelection();
                  },
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            )
            : Text(
              widget.title,
              style: GoogleFonts.inter(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        actions: [
          // Only show search button for PDFs
          if (!_showSearch && _isPdf)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: _showSearchDialog,
              tooltip: 'Search',
            ),

          if (widget.resourceId != null && widget.resourceId!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: _openAiTools,
              tooltip: 'AI Study Tools',
            ),

          IconButton(
             icon: const Icon(Icons.download_rounded),
             onPressed: _handleDownload,
             tooltip: 'Download',
          ),
            
          // Search Navigation (Only when searching AND PDF)
          if (_showSearch && _isPdf) ...[
             IconButton(
               icon: const Icon(Icons.keyboard_arrow_up_rounded),
               onPressed: _searchResult.hasResult 
                   ? () => _searchResult.previousInstance() 
                   : null,
             ),
             IconButton(
               icon: const Icon(Icons.keyboard_arrow_down_rounded),
               onPressed: _searchResult.hasResult 
                   ? () => _searchResult.nextInstance() 
                   : null,
             ),
          ],
          
          if (_isPdf) // Only support night mode toggle for PDF native viewer for now
            IconButton(
              icon: Icon(_isNightMode ? Icons.light_mode : Icons.dark_mode_rounded),
              onPressed: () => setState(() => _isNightMode = !_isNightMode),
              tooltip: _isNightMode ? 'Light Mode' : 'Night Mode',
            ),
        ],
      ),
      body: Stack(
        children: [
          // CONTENT

          // CONTENT is handled below with conditional logic based on error state


            
          // Error State

          if (_hasError)
            _buildErrorState()
          else if (_isPdf)
             _buildPdfContent()
          else if (_isOfficeDoc && _webViewController != null && !kIsWeb)
             _buildWebViewContent()
          else 
             _buildUnsupportedOrWebContent(),

          if (_isLoading)
            const Center(child: BrandedLoader(message: 'Loading Document...')),
        ],
      ),
    );
  }

  Widget _buildPdfContent() {
    return _isNightMode 
      ? ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            -1,  0,  0, 0, 255,
             0, -1,  0, 0, 255,
             0,  0, -1, 0, 255,
             0,  0,  0, 1,   0,
          ]),
          child: _buildSfPdfViewer(),
        )
      : _buildSfPdfViewer();
  }

  Widget _buildSfPdfViewer() {
    return SfPdfViewer.network(
      widget.pdfUrl,
      key: _pdfViewerKey,
      controller: _pdfViewerController,
      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = false;
          });
        }
      },
      onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
        debugPrint('PDF Load Error: ${details.error}');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = details.description;
          });
        }
      },
      enableDoubleTapZooming: true,
    );
  }

  Widget _buildWebViewContent() {
    return WebViewWidget(controller: _webViewController!);
  }

  Widget _buildUnsupportedOrWebContent() {
    // For unsupported types or Web platform fallback
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                final uri = Uri.parse(widget.pdfUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Unable to open link. Please try again.')),
                    );
                  }
                }
              } catch (e) {
                debugPrint('Error launching URL: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Unable to open link. Please try again.')),
                  );
                }
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open External'),
          )
        ],
      ),
    );
  }


  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: AppTheme.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load document',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _isNightMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage.isNotEmpty ? _errorMessage : 'An unknown error occurred',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                 try {
                  final uri = Uri.parse(widget.pdfUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Unable to open link. Please try again.')),
                      );
                    }
                  }
                 } catch (e) {
                   debugPrint('Error launching URL: $e');
                   if (mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(content: Text('Unable to open link. Please try again.')),
                     );
                   }
                 }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open External'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

