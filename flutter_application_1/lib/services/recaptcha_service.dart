import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config/app_config.dart';

/// reCAPTCHA v3 token generator for mobile.
///
/// This loads an in-memory HTML page in a WebView and runs:
///   grecaptcha.execute(siteKey, { action })
/// returning the token to Flutter via a JS channel.
class RecaptchaService {
  static Future<String> getToken(
    BuildContext context, {
    String action = 'mobile_write',
  }) async {
    final completer = Completer<String>();

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) {
          return _RecaptchaOverlay(
            action: action,
            onToken: (token) {
              if (!completer.isCompleted) completer.complete(token);
            },
            onError: (err) {
              if (!completer.isCompleted) completer.completeError(err);
            },
          );
        },
      ),
    );

    // The overlay's internal timeout handles cleanup and Navigator.pop(),
    // which causes the push() future above to resolve. The completer is
    // completed (either with a token or an error) before pop, so we can
    // simply return it without an additional service-level timeout.
    return completer.future;
  }
}

class _RecaptchaOverlay extends StatefulWidget {
  final String action;
  final void Function(String token) onToken;
  final void Function(Object error) onError;

  const _RecaptchaOverlay({
    required this.action,
    required this.onToken,
    required this.onError,
  });

  @override
  State<_RecaptchaOverlay> createState() => _RecaptchaOverlayState();
}

class _RecaptchaOverlayState extends State<_RecaptchaOverlay> {
  late final WebViewController _controller;
  bool _isLoading = true;
  Timer? _timeoutTimer;

  bool _isAllowedRecaptchaNavigation(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    if (uri.scheme == 'about') return true;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'www.google.com' ||
        host == 'www.gstatic.com' ||
        host == 'www.recaptcha.net' ||
        host == 'recaptcha.net';
  }

  @override
  void initState() {
    super.initState();
    
    // Safety timeout in case JS never responds.
    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        widget.onError(TimeoutException('Security check timed out'));
        Navigator.of(context).pop();
      }
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'Recaptcha',
        onMessageReceived: (msg) {
          final token = msg.message;
          if (token.isEmpty) {
            widget.onError(Exception('Empty reCAPTCHA token'));
          } else {
            widget.onToken(token);
          }
          if (mounted) Navigator.of(context).pop();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isAllowedRecaptchaNavigation(request.url)) {
              return NavigationDecision.navigate;
            }
            widget.onError(
              Exception('Blocked unexpected reCAPTCHA URL: ${request.url}'),
            );
            if (mounted) Navigator.of(context).pop();
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            widget.onError(Exception(error.description));
            if (mounted) Navigator.of(context).pop();
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(_html(AppConfig.recaptchaSiteKey, widget.action));
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 1,
              height: 1,
              child: WebViewWidget(controller: _controller),
            ),
            if (_isLoading)
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Verifying security...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Builds the in-memory HTML page that executes reCAPTCHA v3.
  ///
  /// [siteKey] and [action] are safely serialized via [jsonEncode] to prevent
  /// JS injection if caller-controlled values contain special characters.
  String _html(String siteKey, String action) {
    final safeSiteKey = jsonEncode(siteKey);
    final safeAction = jsonEncode(action);
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <script src="https://www.google.com/recaptcha/api.js?render=${Uri.encodeComponent(siteKey)}"></script>
    <script>
      function sendToken(token) {
        Recaptcha.postMessage(token);
      }
      function sendError(err) {
        Recaptcha.postMessage("");
      }
      window.onload = function() {
        try {
          grecaptcha.ready(function() {
            grecaptcha.execute($safeSiteKey, {action: $safeAction}).then(function(token) {
              sendToken(token);
            }).catch(function(e) {
              sendError(e);
            });
          });
        } catch (e) {
          sendError(e);
        }
      }
    </script>
  </head>
  <body></body>
</html>
''';
  }
}
