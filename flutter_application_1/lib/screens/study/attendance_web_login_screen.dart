import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _isDisposed = false;
  bool _hasShownEmbedWarning = false;

  static const String _loginUrl = 'https://kiet.cybervidya.net/';
  static const String _noTokenMessage = '__NO_TOKEN__';
  static const int _minTokenLength = 8;
  static const String _mobileChromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

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
            await _inspectForCaptchaIssue();
            await _tryCaptureToken();
          },
          onWebResourceError: (error) {
            final description = error.description.toLowerCase();
            if (description.contains('err_blocked_by_orb')) {
              _suggestCaptchaFallback(
                'KIET ERP blocked the embedded login. Open KIET ERP in your '
                'browser and continue with the token fallback below.',
              );
              return;
            }
            if (_looksLikeCaptchaIssue(description)) {
              _suggestCaptchaFallback(
                'KIET ERP rejected the embedded login with a low captcha '
                'score. Open KIET ERP in your browser and continue with the '
                'token fallback below.',
              );
            }
            if (!mounted) return;
            if (error.isForMainFrame != true) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.description)));
          },
        ),
      )
      ..setBackgroundColor(Colors.transparent);

    unawaited(_initializeWebView());

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _isDisposed || _didReturnToken) return;
      _tokenPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isDisposed) return;
        unawaited(_tryCaptureToken());
      });
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tokenPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _openKietLoginInBrowser() async {
    final uri = Uri.parse(_loginUrl);
    final didLaunch = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!didLaunch && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open KIET ERP in browser.')),
      );
    }
  }

  Future<void> _initializeWebView() async {
    try {
      await _controller.setUserAgent(_mobileChromeUserAgent);
    } catch (_) {}

    try {
      final cookieManager = WebViewCookieManager();
      await cookieManager.clearCookies();
    } catch (_) {}

    await _controller.loadRequest(Uri.parse(_loginUrl));
  }

  bool _looksLikeCaptchaIssue(String text) {
    final normalized = text.toLowerCase();
    return (normalized.contains('captcha') &&
            (normalized.contains('low') ||
                normalized.contains('score') ||
                normalized.contains('invalid') ||
                normalized.contains('failed') ||
                normalized.contains('required'))) ||
        normalized.contains('recaptcha') ||
        normalized.contains('g-recaptcha');
  }

  void _suggestCaptchaFallback(String message) {
    if (_hasShownEmbedWarning || !mounted) return;
    setState(() => _hasShownEmbedWarning = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _inspectForCaptchaIssue() async {
    if (_didReturnToken) return;
    try {
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          var bodyText = String(document.body && document.body.innerText || '');
          var normalized = bodyText.toLowerCase();
          if (normalized.indexOf('captcha') !== -1 ||
              normalized.indexOf('recaptcha') !== -1) {
            return bodyText.slice(0, 400);
          }
          return '';
        })();
        ''');
      final text = result.toString().replaceAll('"', '').trim();
      if (_looksLikeCaptchaIssue(text)) {
        _suggestCaptchaFallback(
          'KIET ERP is asking for a captcha verification that WebView may not '
          'pass reliably. Open KIET ERP in your browser and continue with the '
          'token fallback below.',
        );
      }
    } catch (_) {}
  }

  Future<void> _tryCaptureToken() async {
    if (_didReturnToken) return;
    try {
      final result = await _controller.runJavaScriptReturningResult('''
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
        ''');
      _handleBridgeMessage(result.toString());
    } catch (_) {}
    await _inspectForCaptchaIssue();
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
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Attendance sync is available only inside the mobile app. '
                'Browser security blocks the KIET ERP session bridge on web.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _openKietLoginInBrowser,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(
                  'Open KIET ERP',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Use the KIET ERP site directly in your browser if you only '
                'need portal access. To sync attendance into StudyShare, open '
                'this flow in the Android app.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            ],
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
