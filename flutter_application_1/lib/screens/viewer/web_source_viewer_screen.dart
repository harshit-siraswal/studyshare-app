import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebSourceViewerScreen extends StatefulWidget {
  final String initialUrl;
  final String title;

  const WebSourceViewerScreen({
    super.key,
    required this.initialUrl,
    required this.title,
  });

  @override
  State<WebSourceViewerScreen> createState() => _WebSourceViewerScreenState();
}

class _WebSourceViewerScreenState extends State<WebSourceViewerScreen> {
  WebViewController? _controller;
  int _progress = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadError = 'In-app web preview is not available here.';
      return;
    }

    final uri = Uri.tryParse(widget.initialUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      _loadError = 'This web source could not be opened in the app.';
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1020))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress.clamp(0, 100));
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _progress = 0;
              _loadError = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _progress = 100);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _loadError = error.description.isNotEmpty
                  ? error.description
                  : 'Failed to load this web source.';
            });
          },
        ),
      )
      ..loadRequest(uri);
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.initialUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final canShowWebView = controller != null && _loadError == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Open externally',
            onPressed: _openExternally,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (canShowWebView && _progress < 100)
            LinearProgressIndicator(value: _progress / 100),
          Expanded(
            child: canShowWebView
                ? WebViewWidget(controller: controller)
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.public_off_rounded,
                            size: 44,
                            color: Colors.white54,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _loadError ?? 'This web source could not be opened.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _openExternally,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('Open in Browser'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
