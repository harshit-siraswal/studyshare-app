
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../config/theme.dart';

class PDFViewerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? resourceId;

  const PDFViewerScreen({
    super.key,
    required this.url,
    required this.title,
    this.resourceId,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  late PdfViewerController _pdfViewerController;
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  File? _cachedPdfFile;
  bool _isWarmingPdfCache = false;
  bool _isPdfCacheLookupComplete = true;
  
  // Search state
  PdfTextSearchResult _searchResult = PdfTextSearchResult();
  final TextEditingController _searchController = TextEditingController();
  bool _showSearchBar = false;
  VoidCallback? _searchListener;

  @override
  void initState() {
    _pdfViewerController = PdfViewerController();
    if (!kIsWeb && widget.url.startsWith('http')) {
      _isPdfCacheLookupComplete = false;
      unawaited(_restoreCachedPdfIfAvailable());
    }
    super.initState();
  }

  @override
  void dispose() {
    if (_searchListener != null) {
      _searchResult.removeListener(_searchListener!);
    }
    _searchController.dispose();
    _pdfViewerController.dispose();
    super.dispose();
  }

  void _handleSearch(String query) {
    if (query.isEmpty) return;

    // Remove previous listener to prevent duplicate setState calls.
    if (_searchListener != null) {
      _searchResult.removeListener(_searchListener!);
      _searchListener = null;
    }

    _searchResult = _pdfViewerController.searchText(query);

    _searchListener = () {
      if (mounted) setState(() {});
    };
    _searchResult.addListener(_searchListener!);
  }

  void _clearSearch() {
    setState(() {
      _showSearchBar = false;
      _searchController.clear();
      _searchResult.clear();
    });
  }

  Future<void> _restoreCachedPdfIfAvailable() async {
    File? restoredFile;
    try {
      final cached = await DefaultCacheManager().getFileFromCache(widget.url);
      if (cached != null && await cached.file.exists()) {
        restoredFile = cached.file;
      }
    } catch (e) {
      debugPrint('Failed to restore cached study PDF: $e');
    } finally {
      if (mounted) {
        setState(() {
          _cachedPdfFile = restoredFile;
          _isPdfCacheLookupComplete = true;
        });
      }
    }
  }

  Future<void> _warmPdfCache() async {
    if (_isWarmingPdfCache || kIsWeb || !widget.url.startsWith('http')) return;
    _isWarmingPdfCache = true;
    try {
      final cached = await DefaultCacheManager().getFileFromCache(widget.url);
      if (cached != null && await cached.file.exists()) {
        if (!mounted) return;
        setState(() {
          _cachedPdfFile = cached.file;
        });
        return;
      }
      final downloaded = await DefaultCacheManager().downloadFile(widget.url);
      if (!mounted) return;
      if (await downloaded.file.exists()) {
        setState(() {
          _cachedPdfFile = downloaded.file;
        });
      }
    } catch (e) {
      debugPrint('Failed to warm study PDF cache: $e');
    } finally {
      _isWarmingPdfCache = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: _showSearchBar
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: GoogleFonts.inter(color: textColor),
                decoration: InputDecoration(
                  hintText: 'Find in document...',
                  hintStyle: GoogleFonts.inter(color: Colors.grey),
                  border: InputBorder.none,
                ),
                onSubmitted: _handleSearch,
              )
            : Text(
                widget.title,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: textColor,
                ),
              ),
        actions: [
          if (_showSearchBar) ...[
            Center(
              child: Text(
                '${_searchResult.currentInstanceIndex}/${_searchResult.totalInstanceCount}',
                style: GoogleFonts.inter(color: textColor, fontSize: 12),
              ),
            ),
            IconButton(
              icon: Icon(Icons.keyboard_arrow_up_rounded, color: textColor),
              onPressed: () {
                _searchResult.previousInstance();
              },
            ),
            IconButton(
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor),
              onPressed: () {
                _searchResult.nextInstance();
              },
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: textColor),
              onPressed: _clearSearch,
            ),
          ] else
            IconButton(
              icon: Icon(Icons.search_rounded, color: textColor),
              onPressed: () {
                setState(() => _showSearchBar = true);
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Hero(
            tag: widget.resourceId != null ? 'resource_card_${widget.resourceId}' : 'pdf_viewer_${widget.url}',
            flightShuttleBuilder: (
              flightContext,
              animation,
              flightDirection,
              fromHeroContext,
              toHeroContext,
            ) {
              return Material(
                color: Theme.of(flightContext).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            child: const SizedBox.expand(),
          ),
          if (!kIsWeb &&
              widget.url.startsWith('http') &&
              !_isPdfCacheLookupComplete)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!kIsWeb &&
              _cachedPdfFile != null &&
              _cachedPdfFile!.existsSync())
            SfPdfViewer.file(
              _cachedPdfFile!,
              key: _pdfViewerKey,
              controller: _pdfViewerController,
              onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                debugPrint('PDF Loaded from cache: ${details.document.pages.count} pages');
              },
              onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                debugPrint('Cached PDF Load Failed: ${details.error}');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to load PDF: ${details.description}')),
                );
              },
            )
          else
            SfPdfViewer.network(
              widget.url,
              key: _pdfViewerKey,
              controller: _pdfViewerController,
              onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                debugPrint('PDF Loaded: ${details.document.pages.count} pages');
                unawaited(_warmPdfCache());
              },
              onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                debugPrint('PDF Load Failed: ${details.error}');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to load PDF: ${details.description}')),
                );
              },
            ),
        ],
      ),
    );
  }
}
