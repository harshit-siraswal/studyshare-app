import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../widgets/branded_loader.dart';
import '../../services/subscription_service.dart';
import '../../widgets/paywall_dialog.dart';

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
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  late PdfViewerController _pdfViewerController;
  late PdfTextSearchResult _searchResult;
  
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isNightMode = false;
  
  // Search State
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  // Timer State - managed by GlobalTimerOverlay
  
  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _searchResult = PdfTextSearchResult();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearch(String query) {
     if (query.isEmpty) return;
     _searchResult = _pdfViewerController.searchText(query);
     setState(() {}); // Update UI for search results
  }

  void _showSearchDialog() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _pdfViewerController.clearSelection();
        _searchController.clear();
      }
    });
  }

  Future<void> _handleDownload() async {
    final subService = SubscriptionService();
    final isPremium = await subService.isPremium();
    
    if (!mounted) return;

    if (!isPremium) {
      showDialog(
        context: context,
        builder: (context) => PaywallDialog(
          onSuccess: () {
            // Re-trigger download or show success message
             if(mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Premium Unlocked! Downloading...')));
                 _handleDownload();
             }
          },
        ),
      );
    } else {
       try {
         final uri = Uri.parse(widget.pdfUrl);
         if (await canLaunchUrl(uri)) {
           await launchUrl(uri, mode: LaunchMode.externalApplication);
         } else {
           if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch download link')));
         }
       } catch(e) {
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
                     _pdfViewerController.clearSelection();
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
          if (!_showSearch)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: _showSearchDialog,
              tooltip: 'Search',
            ),

          IconButton(
             icon: const Icon(Icons.download_rounded),
             onPressed: _handleDownload,
             tooltip: 'Download',
          ),
            
          // Search Navigation (Only when searching)
          if (_showSearch) ...[
             IconButton(
               icon: const Icon(Icons.keyboard_arrow_up_rounded),
               onPressed: () {
                 _searchResult.previousInstance();
               },
             ),
             IconButton(
               icon: const Icon(Icons.keyboard_arrow_down_rounded),
               onPressed: () {
                 _searchResult.nextInstance();
               },
             ),
          ],
          
          IconButton(
             icon: Icon(_isNightMode ? Icons.light_mode : Icons.dark_mode_rounded),
             onPressed: () => setState(() => _isNightMode = !_isNightMode),
             tooltip: _isNightMode ? 'Light Mode' : 'Night Mode',
          ),
        ],
      ),
      body: Stack(
        children: [
          // PDF Viewer with Inversion Logic (Optimized)
          _isNightMode 
              ? ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    -1,  0,  0, 0, 255,
                     0, -1,  0, 0, 255,
                     0,  0, -1, 0, 255,
                     0,  0,  0, 1,   0,
                  ]),
                  child: _buildPdfViewer(),
                )
              : _buildPdfViewer(), // No overhead for light mode

          if (_isLoading)
            const Center(child: BrandedLoader(message: 'Loading PDF...')),
            
          // Error State
          if (_hasError)
            Container(
              color: _isNightMode ? const Color(0xFF121212) : Colors.white, // Standard error bg, not inverted
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Unable to load PDF directly.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This document might be restricted or require external access.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse(widget.pdfUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open in Browser'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (kIsWeb)
                    Text(
                      'Error: $_errorMessage',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
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
        debugPrint('PDF Load Desc: ${details.description}');
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
}
