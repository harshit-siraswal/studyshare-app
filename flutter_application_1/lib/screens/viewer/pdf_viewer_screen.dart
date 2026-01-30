import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../config/theme.dart';
import '../../widgets/branded_loader.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final String? resourceId;

  const PdfViewerScreen({
    super.key,
    required this.pdfUrl,
    required this.title,
    this.resourceId,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _localPath;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isNightMode = false;
  PDFViewController? _pdfController;
  
  @override
  void initState() {
    super.initState();
    _downloadAndCachePdf();
  }

  Future<void> _downloadAndCachePdf() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Get temp directory
      final dir = await getTemporaryDirectory();
      final fileName = widget.pdfUrl.split('/').last.split('?').first;
      final file = File('${dir.path}/$fileName');

      // Check if already cached
      if (await file.exists()) {
        setState(() {
          _localPath = file.path;
          _isLoading = false;
        });
        return;
      }

      // Download the PDF
      final response = await http.get(Uri.parse(widget.pdfUrl));
      
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        setState(() {
          _localPath = file.path;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to download PDF: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _goToPage(int page) {
    if (_pdfController != null && page >= 0 && page < _totalPages) {
      _pdfController!.setPage(page);
    }
  }

  void _showPageJumpDialog() {
    final controller = TextEditingController(text: '${_currentPage + 1}');
    final isDark = _isNightMode || Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.find_in_page_rounded, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Go to Page',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        'Total $_totalPages pages',
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Page input field
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'Enter page number',
                hintStyle: TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppTheme.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              ),
              onSubmitted: (value) {
                final page = int.tryParse(value);
                if (page != null && page >= 1 && page <= _totalPages) {
                  _goToPage(page - 1);
                  Navigator.pop(context);
                }
              },
            ),
            const SizedBox(height: 16),
            
            // Quick navigation buttons
            Row(
              children: [
                _buildQuickNavButton(context, 'First', Icons.first_page_rounded, () {
                  _goToPage(0);
                  Navigator.pop(context);
                }, isDark),
                const SizedBox(width: 8),
                _buildQuickNavButton(context, 'Previous', Icons.chevron_left_rounded, () {
                  if (_currentPage > 0) _goToPage(_currentPage - 1);
                  Navigator.pop(context);
                }, isDark),
                const SizedBox(width: 8),
                _buildQuickNavButton(context, 'Next', Icons.chevron_right_rounded, () {
                  if (_currentPage < _totalPages - 1) _goToPage(_currentPage + 1);
                  Navigator.pop(context);
                }, isDark),
                const SizedBox(width: 8),
                _buildQuickNavButton(context, 'Last', Icons.last_page_rounded, () {
                  _goToPage(_totalPages - 1);
                  Navigator.pop(context);
                }, isDark),
              ],
            ),
            const SizedBox(height: 20),
            
            // Go button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final page = int.tryParse(controller.text);
                  if (page != null && page >= 1 && page <= _totalPages) {
                    _goToPage(page - 1);
                  }
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'Go to Page',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickNavButton(BuildContext context, String label, IconData icon, VoidCallback onTap, bool isDark) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: AppTheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isNightMode ? Colors.black : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkBackground : Colors.white);
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: _isNightMode ? Colors.grey[900] : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: _isNightMode ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _isNightMode ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_totalPages > 0)
              Text(
                'Page ${_currentPage + 1} of $_totalPages',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
              ),
          ],
        ),
        actions: [
          // Night mode toggle
          IconButton(
            icon: Icon(
              _isNightMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: _isNightMode ? Colors.amber : AppTheme.textMuted,
            ),
            onPressed: () => setState(() => _isNightMode = !_isNightMode),
            tooltip: 'Toggle Night Mode',
          ),
          // Page jump
          if (_totalPages > 0)
            IconButton(
              icon: Icon(
                Icons.find_in_page_rounded,
                color: _isNightMode
                    ? Colors.white
                    : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
              ),
              onPressed: _showPageJumpDialog,
              tooltip: 'Go to Page (Text Search Unavailable)',
            ),
          // Note: Sharing of resource PDFs is disabled to keep downloads as a premium feature.
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const BrandedLoader(
        compact: true,
        message: 'Loading PDF...',
        showQuotes: false,
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 64, color: Colors.red.withOpacity(0.7)),
              const SizedBox(height: 16),
              Text('Failed to load PDF', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: _isNightMode ? Colors.white : Colors.black)),
              const SizedBox(height: 8),
              Text(_errorMessage, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _downloadAndCachePdf,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_localPath == null) {
      return const Center(child: Text('No PDF available'));
    }

    return Container(
      color: _isNightMode ? Colors.black : null,
      child: PDFView(
        filePath: _localPath!,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: false, // Disable spacing between pages for continuous feel
        pageFling: false, // Disable page fling for smooth scrolling
        pageSnap: false, // Disable page snapping for continuous scroll
        nightMode: _isNightMode,
        onRender: (pages) {
          setState(() {
            _totalPages = pages ?? 0;
          });
        },
        onViewCreated: (controller) {
          _pdfController = controller;
        },
        onPageChanged: (page, total) {
          setState(() {
            _currentPage = page ?? 0;
            _totalPages = total ?? 0;
          });
        },
        onError: (error) {
          setState(() {
            _hasError = true;
            _errorMessage = error.toString();
          });
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isNightMode ? Colors.grey[900] : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Previous page
            IconButton(
              onPressed: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
              icon: Icon(Icons.chevron_left_rounded, size: 32),
              color: _currentPage > 0 ? AppTheme.primary : AppTheme.textMuted.withOpacity(0.3),
            ),
            
            // Page slider
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppTheme.primary,
                  inactiveTrackColor: AppTheme.textMuted.withOpacity(0.3),
                  thumbColor: AppTheme.primary,
                  overlayColor: AppTheme.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: _currentPage.toDouble(),
                  min: 0,
                  max: (_totalPages - 1).toDouble().clamp(0, double.infinity),
                  onChanged: (value) => _goToPage(value.round()),
                ),
              ),
            ),
            
            // Next page
            IconButton(
              onPressed: _currentPage < _totalPages - 1 ? () => _goToPage(_currentPage + 1) : null,
              icon: Icon(Icons.chevron_right_rounded, size: 32),
              color: _currentPage < _totalPages - 1 ? AppTheme.primary : AppTheme.textMuted.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }
}
