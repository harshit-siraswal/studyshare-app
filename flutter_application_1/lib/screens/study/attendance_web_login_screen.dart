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
  final TextEditingController _manualTokenController = TextEditingController();
  bool _isLoading = true;
  bool _didReturnToken = false;
  bool _isDisposed = false;
  String? _manualTokenError;
  bool _manualEntryExpanded = false;
  bool _captchaFallbackSuggested = false;

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
    _manualTokenController.dispose();
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

  void _submitManualToken() {
    final token = _manualTokenController.text.trim();
    if (token.length < _minTokenLength) {
      setState(
        () => _manualTokenError = 'Enter a valid KIET authentication token.',
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(token);
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
    if (_captchaFallbackSuggested) {
      if (!_manualEntryExpanded && mounted) {
        setState(() => _manualEntryExpanded = true);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _captchaFallbackSuggested = true;
      _manualEntryExpanded = true;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildManualFallback(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondary = isDark ? Colors.white70 : Colors.black54;
    final panelColor = isDark ? const Color(0xFF1F1F22) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: panelColor.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_captchaFallbackSuggested) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: isDark ? 0.18 : 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'KIET ERP may reject embedded sign-in with a low captcha '
                      'score. If the in-app page keeps failing, open KIET ERP '
                      'in your browser and paste the '
                      '`authenticationtoken` here.',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.35,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Having trouble with the in-app login?',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _manualEntryExpanded = !_manualEntryExpanded,
                ),
                child: Text(
                  _manualEntryExpanded ? 'Hide' : 'Use token',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_manualEntryExpanded) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openKietLoginInBrowser,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(
                'Open KIET ERP',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualTokenController,
              decoration: InputDecoration(
                labelText: 'KIET authentication token',
                hintText: 'Paste authenticationtoken value',
                errorText: _manualTokenError,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
              minLines: 1,
              onChanged: (_) {
                if (_manualTokenError != null) {
                  setState(() => _manualTokenError = null);
                }
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tip: In the KIET ERP tab, open devtools and copy localStorage.authenticationtoken.',
                style: GoogleFonts.inter(fontSize: 11, color: secondary),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _submitManualToken,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                'Continue with token',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
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
                'Browser security blocks embedded KIET ERP on web. Use KIET ERP in a new tab, then paste your authentication token below.',
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
              const SizedBox(height: 20),
              TextField(
                controller: _manualTokenController,
                decoration: InputDecoration(
                  labelText: 'KIET authentication token',
                  hintText: 'Paste authenticationtoken value',
                  errorText: _manualTokenError,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
                minLines: 1,
                onChanged: (_) {
                  if (_manualTokenError != null) {
                    setState(() => _manualTokenError = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Tip: In KIET ERP tab, open browser devtools and copy localStorage.authenticationtoken.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitManualToken,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  'Continue with token',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
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
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(top: false, child: _buildManualFallback(isDark)),
          ),
        ],
      ),
    );
  }
}
