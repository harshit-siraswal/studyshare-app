import 'dart:async';

import 'package:flutter/foundation.dart';
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
  static const int _minTokenLength = 8;

  bool _isAllowedNavigation(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    if (uri.scheme == 'about') return true;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final isKietOrCybervidyaHost =
        host == 'kiet.cybervidya.net' ||
        host.endsWith('.kiet.cybervidya.net') ||
        host == 'cybervidya.net' ||
        host.endsWith('.cybervidya.net');
    return isKietOrCybervidyaHost ||
        host == 'www.google.com' ||
        host.endsWith('.google.com') ||
        host == 'www.gstatic.com' ||
        host.endsWith('.gstatic.com') ||
        host == 'www.recaptcha.net' ||
        host == 'recaptcha.net' ||
        host.endsWith('.recaptcha.net') ||
        host == 'www.google.co.in' ||
        host == 'googleads.g.doubleclick.net' ||
        host == 'www.googleadservices.com';
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _isLoading = false;
      return;
    }

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
            if (error.isForMainFrame != true) return;
            final rawDescription = error.description.trim();
            final friendlyMessage = rawDescription.isEmpty
                ? 'Please try again.'
                : rawDescription.length > 120
                ? '${rawDescription.substring(0, 117)}...'
                : rawDescription;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Login failed: $friendlyMessage')),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _tokenPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          _tokenPollTimer?.cancel();
          return;
        }
        _tryCaptureToken();
      });
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

          function normalizeToken(rawValue) {
            if (!rawValue) return '';
            var value = String(rawValue).trim();
            if (!value) return '';
            if ((value.startsWith('"') && value.endsWith('"')) ||
                (value.startsWith("'") && value.endsWith("'"))) {
              value = value.slice(1, -1).trim();
            }
            if (!value) return '';
            if ((value.startsWith('{') && value.endsWith('}')) ||
                (value.startsWith('[') && value.endsWith(']'))) {
              try {
                var parsed = JSON.parse(value);
                if (typeof parsed === 'string') {
                  value = parsed.trim();
                }
              } catch (_) {}
            }
            return value;
          }

          function candidateFromStorage(storage) {
            if (!storage) return '';
            var direct = normalizeToken(storage.getItem('authenticationtoken'));
            if (direct) return direct;

            var fallback = '';
            for (var i = 0; i < storage.length; i++) {
              var key = storage.key(i);
              if (!key) continue;
              var lower = key.toLowerCase();
              if (lower.indexOf('token') == -1 &&
                  lower.indexOf('auth') == -1 &&
                  lower.indexOf('session') == -1) {
                continue;
              }
              var value = normalizeToken(storage.getItem(key));
              if (!value) continue;
              if (lower == 'authenticationtoken') {
                return value;
              }
              if (!fallback) {
                fallback = value;
              }
            }
            return fallback;
          }

          function extractToken() {
            var localToken = candidateFromStorage(window.localStorage);
            if (localToken) return localToken;
            return candidateFromStorage(window.sessionStorage);
          }

          function isLikelyAuthenticated() {
            var url = String(window.location.href || '').toLowerCase();
            return url.indexOf('/home') !== -1 ||
                url.indexOf('dashboard') !== -1 ||
                url.indexOf('attendance') !== -1;
          }

          function pushToken(force) {
            try {
              var token = extractToken();
              if (token && (force || isLikelyAuthenticated())) {
                KietAttendanceBridge.postMessage(token);
                return;
              }
              KietAttendanceBridge.postMessage('$_noTokenMessage');
            } catch (error) {
              KietAttendanceBridge.postMessage('$_noTokenMessage');
            }
          }
          pushToken(false);

          var lastUrl = window.location.href;
          new MutationObserver(function() {
            if (window.location.href !== lastUrl) {
              lastUrl = window.location.href;
              pushToken(false);
            }
          }).observe(document, { subtree: true, childList: true });

          window.addEventListener('popstate', function() { pushToken(false); });
          window.addEventListener('hashchange', function() { pushToken(false); });
          setInterval(function() { pushToken(false); }, 1000);
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _tryCaptureToken() async {
    if (_didReturnToken) return;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        '''
        (function() {
          function normalizeToken(rawValue) {
            if (!rawValue) return '';
            var value = String(rawValue).trim();
            if (!value) return '';
            if ((value.startsWith('"') && value.endsWith('"')) ||
                (value.startsWith("'") && value.endsWith("'"))) {
              value = value.slice(1, -1).trim();
            }
            if (!value) return '';
            if ((value.startsWith('{') && value.endsWith('}')) ||
                (value.startsWith('[') && value.endsWith(']'))) {
              try {
                var parsed = JSON.parse(value);
                if (typeof parsed === 'string') {
                  value = parsed.trim();
                }
              } catch (_) {}
            }
            return value;
          }

          function candidateFromStorage(storage) {
            if (!storage) return '';
            var direct = normalizeToken(storage.getItem('authenticationtoken'));
            if (direct) return direct;

            var fallback = '';
            for (var i = 0; i < storage.length; i++) {
              var key = storage.key(i);
              if (!key) continue;
              var lower = key.toLowerCase();
              if (lower.indexOf('token') == -1 &&
                  lower.indexOf('auth') == -1 &&
                  lower.indexOf('session') == -1) {
                continue;
              }
              var value = normalizeToken(storage.getItem(key));
              if (!value) continue;
              if (lower == 'authenticationtoken') return value;
              if (!fallback) fallback = value;
            }
            return fallback;
          }

          var token = candidateFromStorage(window.localStorage) ||
              candidateFromStorage(window.sessionStorage);
          return token || '';
        })();
        ''',
      );
      _handleBridgeMessage(result.toString());
    } catch (_) {}
  }

  void _handleBridgeMessage(String rawToken) {
    if (_didReturnToken) return;
    final normalized = rawToken.trim().replaceAll('"', '').replaceAll("'", '');
    if (normalized.isEmpty ||
        normalized == _noTokenMessage ||
        normalized.length < _minTokenLength) {
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

    if (kIsWeb) {
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
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'KIET ERP attendance sync is available in the StudyShare mobile app.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.45,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

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
