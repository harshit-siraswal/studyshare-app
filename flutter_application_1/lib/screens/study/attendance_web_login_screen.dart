import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/theme.dart';

class AttendanceWebLoginScreen extends StatefulWidget {
  const AttendanceWebLoginScreen({super.key});

  @override
  State<AttendanceWebLoginScreen> createState() =>
      _AttendanceWebLoginScreenState();
}

class _AttendanceWebLoginScreenState extends State<AttendanceWebLoginScreen> {
  late final WebViewController _controller;
  Timer? _tokenPollTimer;
  bool _isLoading = true;
  bool _didReturnToken = false;

  static const String _loginUrl = 'https://kiet.cybervidya.net/';
  static const String _noTokenMessage = '__NO_TOKEN__';

  bool _isAllowedNavigation(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    if (uri.scheme == 'about') return true;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host.contains('kiet.cybervidya.net') ||
        host == 'www.google.com' ||
        host == 'www.gstatic.com' ||
        host == 'www.recaptcha.net' ||
        host == 'recaptcha.net';
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'KietAttendanceBridge',
        onMessageReceived: (message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isAllowedNavigation(request.url)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _isLoading = false);
            await _installBridge();
            await _tryCaptureToken();
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.description)));
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));

    _tokenPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tryCaptureToken();
    });
  }

  @override
  void dispose() {
    _tokenPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _installBridge() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          if (window.__studyshareKietBridgeInstalled) {
            return;
          }
          window.__studyshareKietBridgeInstalled = true;

          function pushToken() {
            try {
              var token = window.localStorage.getItem('authenticationtoken') || '';
              KietAttendanceBridge.postMessage(token || '$_noTokenMessage');
            } catch (error) {
              KietAttendanceBridge.postMessage('$_noTokenMessage');
            }
          }

          pushToken();

          var lastUrl = window.location.href;
          new MutationObserver(function() {
            if (window.location.href !== lastUrl) {
              lastUrl = window.location.href;
              pushToken();
            }
          }).observe(document, { subtree: true, childList: true });

          window.addEventListener('popstate', pushToken);
          window.addEventListener('hashchange', pushToken);
          setInterval(pushToken, 1000);
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _tryCaptureToken() async {
    if (_didReturnToken) return;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "window.localStorage.getItem('authenticationtoken') || ''",
      );
      _handleBridgeMessage(result.toString());
    } catch (_) {}
  }

  void _handleBridgeMessage(String rawToken) {
    if (_didReturnToken) return;
    final normalized = rawToken.trim().replaceAll('"', '').replaceAll("'", '');
    if (normalized.isEmpty || normalized == _noTokenMessage) {
      return;
    }

    _didReturnToken = true;
    _tokenPollTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.darkBackground
          : AppTheme.lightBackground,
      appBar: AppBar(
        title: Text(
          'Connect KIET ERP',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.12),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Sign in on the official KIET ERP page. After login and any reCAPTCHA step, StudyShare will wait for the authenticated page and capture the session token automatically.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: isDark
                                ? AppTheme.darkTextPrimary
                                : AppTheme.lightTextPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
