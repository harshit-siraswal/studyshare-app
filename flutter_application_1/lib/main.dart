import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, debugPrintStack, kIsWeb;
import 'dart:ui' show PlatformDispatcher;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart'; // Deep linking
import 'dart:convert';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'dart:io' show Platform;
import 'dart:collection';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';

import 'l10n/app_localizations.dart';
import 'config/app_config.dart';
import 'config/theme.dart';
import 'config/firebase_options.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/college_selection_screen.dart';
import 'screens/auth/banned_user_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/notices/notice_detail_screen.dart';
import 'services/auth_service.dart';
import 'services/download_service.dart';
import 'services/push_notification_service.dart';
import 'services/backend_api_service.dart';
import 'providers/theme_provider.dart';
import 'widgets/global_timer_overlay.dart';
import 'widgets/branded_loader.dart';
import 'utils/app_navigator.dart';
import 'utils/theme_animator.dart';
import 'services/supabase_service.dart';
import 'models/department_account.dart';
import 'services/home_widget_service.dart';

String? _getCollegeIdFromPrefs(SharedPreferences prefs) {
  try {
    final collegeJson = prefs.getString('selectedCollege');
    if (collegeJson != null && collegeJson.isNotEmpty) {
      final data = jsonDecode(collegeJson) as Map<String, dynamic>;
      if (data['id'] is String && (data['id'] as String).isNotEmpty) {
        return data['id'];
      }
    }
  } catch (e) {
    debugPrint('Error decoding selectedCollege JSON: $e');
  }
  return prefs.getString('selectedCollegeId');
}

final Queue<String> _pendingDeepLinks = Queue<String>();
bool _isProcessingPendingDeepLinks = false;
bool _deepLinkProcessingScheduled = false;

void queueDeepLink(String actionUrl) {
  if (actionUrl.isEmpty) return;
  if (_pendingDeepLinks.contains(actionUrl)) return;
  _pendingDeepLinks.addLast(actionUrl);
  debugPrint('Queued deep link for later navigation: $actionUrl');
  if (appNavigatorKey.currentState != null) {
    unawaited(processPendingDeepLinks());
  }
}

Future<void> processPendingDeepLinks() async {
  if (_isProcessingPendingDeepLinks || _pendingDeepLinks.isEmpty) return;
  final navigatorState = appNavigatorKey.currentState;
  if (navigatorState == null) return;

  _isProcessingPendingDeepLinks = true;
  try {
    while (_pendingDeepLinks.isNotEmpty) {
      final deepLink = _pendingDeepLinks.removeFirst();
      try {
        await navigatorState.pushNamed(deepLink);
      } catch (e) {
        debugPrint('Failed to process queued deep link "$deepLink": $e');
      }
    }
  } finally {
    _isProcessingPendingDeepLinks = false;
  }
}

/// Request necessary app permissions
/// Returns true if all critical permissions are granted or not required
Future<bool> _requestPermissions() async {
  if (kIsWeb) return true; // Skip on web

  if (Platform.isAndroid) {
    // Do not block app startup on broad media/storage permissions.
    // Those are requested at the exact feature entry points (picker/share).
    // Only notifications are requested here and failures are non-blocking.
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        await Permission.notification.request();
      }
    } on PlatformException catch (e) {
      debugPrint(
        'Notification permission request failed (PlatformException): ${e.message ?? e}',
      );
    } on Exception catch (e) {
      debugPrint(
        'Notification permission request error (${e.runtimeType}): $e',
      );
    }
    return true;
  }

  return true; // iOS or other platforms, handled by plist or similar
}

// Top-level navigator key for global access

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handler — works in release mode
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(label: 'FlutterError stack', stackTrace: details.stack);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return false; // Let the framework treat this as unhandled/fatal
  };

  // Validate configuration and log any warnings
  // Validate configuration
  final configResult = AppConfig.validate();

  if (!configResult.isValid) {
    for (final error in configResult.errors) {
      // Use debugPrint for logged output (print may be stripped or swallowed)
      debugPrint('CRITICAL CONFIG ERROR: $error');
    }
    debugPrint(
      'Continuing startup with fallback/default configuration values.',
    );
  }

  for (final warning in configResult.warnings) {
    debugPrint('Configuration Warning: $warning');
  }

  // Initialization is deferred to AppRoot to allow the splash screen to render immediately.

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const AppRoot());
}

enum AppState {
  loading,
  noConnection,
  permissionError,
  initializationError,
  ready,
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  AppState _appState = AppState.loading;
  SharedPreferences? _prefs;
  ThemeProvider? _themeProvider;
  final PushNotificationService _pushService = PushNotificationService();
  final BackendApiService _backendApi = BackendApiService();
  final AuthService _authService = AuthService();
  StreamSubscription? _authStateSubscription;
  bool _firebaseInitialized = false;
  String? _initializationErrorMessage;
  String? _lastRegisteredFcmToken;
  static const String _fcmOwnerEmailKey = 'fcm_token_owner_email';
  static const Set<String> _trustedExternalHosts = {
    'studyshare.me',
    'www.studyshare.me',
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
  };

  bool _isTrustedNotificationUri(Uri uri) {
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return _trustedExternalHosts.contains(host) ||
        host.endsWith('.studyshare.me');
  }

  ThemeMode get _bootThemeMode {
    final savedTheme = _prefs?.getString('theme_mode');
    if (savedTheme == 'light') return ThemeMode.light;
    return ThemeMode.dark;
  }

  @override
  void initState() {
    super.initState();
    initApp();
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  void _bindAuthAwareFcmSync() {
    _authStateSubscription?.cancel();
    _authStateSubscription = _authService.authStateChanges.listen((user) async {
      if (user == null) {
        await _handleSignedOutFcmState();
        return;
      }
      final normalizedEmail = user.email?.trim().toLowerCase();
      if (normalizedEmail == null || normalizedEmail.isEmpty) {
        debugPrint('Skipping FCM sync: signed-in user has no email.');
        return;
      }
      await _syncStoredFcmToken(currentEmail: normalizedEmail);
    });
  }

  Future<void> _syncStoredFcmToken({String? currentEmail}) async {
    final token = _pushService.fcmToken ?? await _pushService.getSavedToken();
    if (token == null || token.isEmpty) return;
    await _ensureFcmTokenOwnership(token, currentEmail: currentEmail);
  }

  Future<void> _handleSignedOutFcmState() async {
    final prefs = await SharedPreferences.getInstance();
    final hadRegisteredOwner =
        (prefs.getString(_fcmOwnerEmailKey)?.trim().isNotEmpty ?? false);

    if (kIsWeb) {
      _lastRegisteredFcmToken = null;
      await prefs.remove(_fcmOwnerEmailKey);
      return;
    }

    final token = _pushService.fcmToken ?? await _pushService.getSavedToken();
    if (hadRegisteredOwner && token != null && token.isNotEmpty) {
      await _unregisterFcmToken(token, reason: 'logout');
    }

    _lastRegisteredFcmToken = null;
    await prefs.remove(_fcmOwnerEmailKey);
  }

  Future<void> _ensureFcmTokenOwnership(
    String token, {
    String? currentEmail,
  }) async {
    final normalizedEmail = (currentEmail ?? _authService.currentUser?.email)
        ?.trim()
        .toLowerCase();
    if (normalizedEmail == null || normalizedEmail.isEmpty) {
      debugPrint('Skipping FCM registration: no authenticated email.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastOwner = prefs.getString(_fcmOwnerEmailKey)?.trim().toLowerCase();
    if (lastOwner != null &&
        lastOwner.isNotEmpty &&
        lastOwner != normalizedEmail) {
      await _unregisterFcmToken(token, reason: 'account_switch');
      _lastRegisteredFcmToken = null;
    }

    await _registerFcmTokenIfAuthenticated(token);
    await prefs.setString(_fcmOwnerEmailKey, normalizedEmail);
  }

  Future<void> _unregisterFcmToken(
    String token, {
    required String reason,
  }) async {
    try {
      await _backendApi.deleteFcmToken(token);
      debugPrint('FCM token unregistered from backend ($reason).');
    } catch (e) {
      debugPrint('Failed to unregister FCM token ($reason): $e');
    }
  }

  Future<void> _registerFcmTokenIfAuthenticated(String token) async {
    if (kIsWeb || token.isEmpty) return;
    if (_lastRegisteredFcmToken == token) return;

    if (_authService.currentUser == null) {
      debugPrint('Skipping FCM token registration: no authenticated user yet.');
      return;
    }

    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      await _backendApi.registerFcmToken(token: token, platform: platform);
      _lastRegisteredFcmToken = token;
      final email = _authService.currentUser?.email?.trim().toLowerCase();
      if (email != null && email.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_fcmOwnerEmailKey, email);
      }
      debugPrint('FCM token registered with backend');
    } catch (e) {
      debugPrint('Failed to register FCM token: $e');
    }
  }

  Future<bool> _bootstrapTheme() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _themeProvider ??= ThemeProvider(_prefs);
      return true;
    } catch (e) {
      debugPrint('SharedPreferences bootstrap error: $e');
      return false;
    }
  }

  Future<void> initApp() async {
    if (!mounted) return;
    setState(() {
      _appState = AppState.loading;
      _initializationErrorMessage = null;
    });

    try {
      late bool bootstrapped;
      late List<ConnectivityResult> connectivityResult;

      try {
        final results = await Future.wait([
          _bootstrapTheme(),
          Connectivity().checkConnectivity(),
        ]);
        bootstrapped = results[0] as bool;
        connectivityResult = results[1] as List<ConnectivityResult>;
      } catch (e) {
        debugPrint('Bootstrap/Connectivity parallel check failed: $e');
        if (mounted) setState(() => _appState = AppState.initializationError);
        return;
      }

      if (!bootstrapped) {
        if (mounted) setState(() => _appState = AppState.initializationError);
        return;
      }

      // Trigger rebuild to apply theme from preferences to loading screen
      if (mounted) setState(() {});

      if (connectivityResult.contains(ConnectivityResult.none)) {
        if (mounted) setState(() => _appState = AppState.noConnection);
        return;
      }

      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        if (mounted) setState(() => _appState = AppState.permissionError);
        return;
      }

      // Initialize Heavy Services in parallel AFTER the splash screen has rendered
      await Future.wait([
        // 1. Supabase (required)
        // required — app cannot function without this, errors are rethrown
        () async {
          try {
            await Supabase.initialize(
              url: AppConfig.supabaseUrl,
              anonKey: AppConfig.supabaseAnonKey,
            );
            debugPrint('Supabase initialized successfully');
          } catch (e) {
            debugPrint('Supabase initialization error: $e');
            rethrow;
          }
        }(),
        // 2. Firebase
        // optional — degrade gracefully, errors logged only
        () async {
          try {
            await Firebase.initializeApp(
              options: kIsWeb ? DefaultFirebaseOptions.currentPlatform : null,
            );
            _firebaseInitialized = true;
            debugPrint('Firebase initialized successfully');
          } catch (e) {
            debugPrint('Firebase initialization error: $e');
            _initializationErrorMessage =
                'Firebase initialization failed. '
                'Please verify Firebase config and restart.';
          }
        }(),
        // 3. Hive
        // required — app cannot function without this, errors are rethrown
        () async {
          try {
            await Hive.initFlutter();
          } catch (e) {
            debugPrint('Hive initialization error: $e');
            rethrow; // Hive is required for app functionality
          }
        }(),
        // 4. DownloadService
        // optional — degrade gracefully, errors logged only
        () async {
          try {
            await DownloadService().init();
          } catch (e) {
            debugPrint('DownloadService initialization error: $e');
          }
        }(),
        // 5. HomeWidgetService
        () async {
          try {
            await HomeWidgetService.instance.initialize();
          } catch (e) {
            debugPrint('HomeWidgetService initialization error: $e');
          }
        }(),
      ]);

      if (!_firebaseInitialized) {
        _initializationErrorMessage ??=
            'Firebase could not be initialized. '
            'Please verify Firebase setup and try again.';
        if (mounted) setState(() => _appState = AppState.initializationError);
        return;
      }

      await _continueStartup();
    } catch (e, st) {
      debugPrint('FATAL initApp error: $e\n$st');
      _initializationErrorMessage = e.toString();
      if (mounted) {
        setState(() => _appState = AppState.initializationError);
      }
    }
  }

  Future<void> _continueStartup() async {
    // Bind auth-aware FCM sync now that Supabase is ready
    if (_firebaseInitialized) {
      _bindAuthAwareFcmSync();
    }

    // Initialize Push Notifications (after Firebase is ready)
    if (!kIsWeb && _firebaseInitialized) {
      try {
        // Set up background message handler
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );

        await _pushService.initialize(
          onTokenRefresh: (token) async {
            await _ensureFcmTokenOwnership(token);
          },
          onMessageReceived: (message) {
            debugPrint('Foreground message: ${message.notification?.title}');
          },
          onNotificationTap: (message) async {
            // Handle navigation based on message data
            debugPrint('Notification tapped: ${message.data}');

            try {
              // Safe extraction
              final dynamic actionUrlRaw = message.data['actionUrl'];
              final String? actionUrl = actionUrlRaw?.toString();

              if (actionUrl != null && actionUrl.isNotEmpty) {
                if (actionUrl.startsWith('/')) {
                  // Internal navigation using global navigator key
                  debugPrint('Internal navigation to $actionUrl requested');
                  final navigatorState = appNavigatorKey.currentState;
                  if (navigatorState == null) {
                    debugPrint(
                      'Navigator not mounted. Skipping deep link now: '
                      '$actionUrl',
                    );
                    queueDeepLink(actionUrl);
                  } else {
                    await navigatorState.pushNamed(actionUrl);
                  }
                } else {
                  // External navigation
                  final uri = Uri.parse(actionUrl);
                  if (!_isTrustedNotificationUri(uri)) {
                    debugPrint(
                      'Blocked untrusted notification URL: ${uri.toString()}',
                    );
                    // Show user feedback for blocked URL
                    final currentContext = appNavigatorKey.currentContext;
                    if (currentContext != null) {
                      final l10n = AppLocalizations.of(currentContext);
                      ScaffoldMessenger.of(currentContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n?.blockedUntrustedUrl ?? 'Blocked untrusted URL',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                    return;
                  }
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    debugPrint('Could not launch deep link: $actionUrl');
                  }
                }
              }
            } catch (e) {
              debugPrint('Error handling notification tap: $e');
            }
          },
        );
        await _syncStoredFcmToken();
        debugPrint('Push notifications initialized');
      } catch (e) {
        debugPrint('Push notification initialization error: $e');
        // Don't fail startup for push notification errors
      }
    }

    if (mounted) {
      assert(
        _themeProvider != null,
        'ThemeProvider should be set by _bootstrapTheme',
      );
      setState(() => _appState = AppState.ready);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_appState == AppState.noConnection) {
      return NoConnectionScreen(onRetry: initApp);
    }

    if (_appState == AppState.permissionError) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.settings_suggest_rounded,
                    size: 64,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Permissions Required',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'StudyShare needs access to storage/media to function correctly. Please grant permissions in settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => openAppSettings(),
                    child: const Text('Open Settings'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: initApp, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_appState == AppState.initializationError) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to initialize app',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _initializationErrorMessage ??
                      'An unexpected error occurred. Please restart the app.',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: initApp, child: const Text('Retry')),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    SystemNavigator.pop();
                  },
                  child: const Text('Exit App'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_appState == AppState.loading ||
        _prefs == null ||
        _themeProvider == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(null),
        darkTheme: AppTheme.darkTheme(null),
        themeMode: _bootThemeMode,
        home: const Scaffold(
          body: AppSplashAnimation(
            title: 'StudyShare',
            subtitle: 'Connect. Learn. Share.',
            loadingLabel: 'Starting StudyShare...',
          ),
        ),
      );
    }

    // AppState.ready
    return ProviderScope(
      child: StudyShareApp(prefs: _prefs!, themeProvider: _themeProvider!),
    );
  }
}

class StudyShareApp extends StatelessWidget {
  final SharedPreferences prefs;
  final ThemeProvider themeProvider;

  const StudyShareApp({
    super.key,
    required this.prefs,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeProvider,
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final lightTheme = AppTheme.lightTheme(lightDynamic);
            final darkTheme = AppTheme.darkTheme(darkDynamic);

            return MaterialApp(
              title: AppConfig.appName,
              debugShowCheckedModeBanner: false,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              navigatorKey: appNavigatorKey,
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: themeProvider.themeMode,
              themeAnimationDuration: Duration.zero,
              // curve kept for future non-zero duration changes
              themeAnimationCurve: Curves.easeInOut,
              home: AppRouter(prefs: prefs, themeProvider: themeProvider),
              onGenerateRoute: (settings) {
                if (settings.name != null &&
                    settings.name!.startsWith('/notices')) {
                  final uri = Uri.parse(settings.name!);
                  final noticeId = uri.queryParameters['id'];
                  if (noticeId != null) {
                    final collegeId = _getCollegeIdFromPrefs(prefs);

                    if (collegeId != null && collegeId.isNotEmpty) {
                      return MaterialPageRoute(
                        builder: (_) => NoticeDeepLinkLoader(
                          noticeId: noticeId,
                          collegeId: collegeId,
                        ),
                      );
                    } else {
                      // Edge case fallback:
                      // Show error and navigate to college selection if no college
                      debugPrint(
                        'Failed to route deep-link: no collegeId found.',
                      );
                      return MaterialPageRoute(
                        builder: (context) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (context.mounted) {
                              final l10n = AppLocalizations.of(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n?.selectCollegeBeforeDeepLink ??
                                        'Please select a college before '
                                            'opening deep links.',
                                  ),
                                ),
                              );
                            }
                          });
                          return AppRouter(
                            prefs: prefs,
                            themeProvider: themeProvider,
                          );
                        },
                      );
                    }
                  }
                }
                return null;
              },
              builder: (context, child) {
                if (!_deepLinkProcessingScheduled) {
                  _deepLinkProcessingScheduled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    processPendingDeepLinks();
                  });
                }
                return RepaintBoundary(
                  key: appBoundaryKey,
                  child: GlobalTimerOverlay(
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class AppRouter extends StatefulWidget {
  final SharedPreferences prefs;
  final ThemeProvider themeProvider;

  const AppRouter({
    super.key,
    required this.prefs,
    required this.themeProvider,
  });

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  final AuthService _authService = AuthService();
  Future<_AuthGateResult>? _authGateFuture;
  String? _authGateCacheKey;
  bool _forcedSignOutInFlight = false;
  String? _pendingLoginErrorMessage;

  bool get _hasSeenOnboarding =>
      widget.prefs.getBool('hasSeenOnboarding') ?? false;

  Map<String, dynamic>? get _selectedCollegeData {
    final String? jsonString = widget.prefs.getString('selectedCollege');
    if (jsonString != null) {
      try {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error decoding selected college: $e');
      }
    }
    return null;
  }

  // Support reading from new JSON key with fallback to legacy separate keys
  String? get _selectedCollegeId => _getCollegeIdFromPrefs(widget.prefs);
  String? get _selectedCollegeName =>
      _selectedCollegeData?['name'] ??
      widget.prefs.getString('selectedCollegeName');
  String? get _selectedCollegeDomain =>
      _selectedCollegeData?['domain'] ??
      widget.prefs.getString('selectedCollegeDomain');

  void _onOnboardingComplete() async {
    await widget.prefs.setBool('hasSeenOnboarding', true);
    setState(() {});
  }

  void _onCollegeSelected(String id, String name, String domain) async {
    // Stash legacy keys before removal
    final legacyId = widget.prefs.getString('selectedCollegeId');
    final legacyName = widget.prefs.getString('selectedCollegeName');
    final legacyDomain = widget.prefs.getString('selectedCollegeDomain');

    try {
      final jsonString = jsonEncode({'id': id, 'name': name, 'domain': domain});
      await widget.prefs.setString('selectedCollege', jsonString);
      // Clean up old keys if they exist
      await Future.wait([
        widget.prefs.remove('selectedCollegeId'),
        widget.prefs.remove('selectedCollegeName'),
        widget.prefs.remove('selectedCollegeDomain'),
      ]);
    } catch (e) {
      debugPrint('Error saving college selection: $e');
      // Rollback: remove broken new key and restore legacy if needed
      await widget.prefs.remove('selectedCollege');
      if (legacyId != null) {
        await widget.prefs.setString('selectedCollegeId', legacyId);
      }
      if (legacyName != null) {
        await widget.prefs.setString('selectedCollegeName', legacyName);
      }
      if (legacyDomain != null) {
        await widget.prefs.setString('selectedCollegeDomain', legacyDomain);
      }
    }
    setState(() {});
  }

  void _onLogout() async {
    await _authService.signOut();
    setState(() {});
  }

  void _onChangeCollege() async {
    // Stash legacy keys before potential removal (though here we are explicitly clearing)
    // No need to restore on cancellation since this is a user action to clear.
    await widget.prefs.remove('selectedCollege');
    // Ensure legacy keys are also cleared just in case
    await widget.prefs.remove('selectedCollegeId');
    await widget.prefs.remove('selectedCollegeName');
    await widget.prefs.remove('selectedCollegeDomain');
    setState(() {});
  }

  void _resetAuthGateCache() {
    _authGateFuture = null;
    _authGateCacheKey = null;
    _forcedSignOutInFlight = false;
  }

  Future<_AuthGateResult> _checkCurrentSessionAccess(String collegeId) async {
    final email = _authService.userEmail?.trim();
    if (email == null || email.isEmpty) {
      return const _AuthGateResult.denied(
        'Unable to verify account access. Please sign in again.',
      );
    }

    try {
      final banResult = await _authService.checkBanStatus(email, collegeId);
      if (banResult?['banCheckSkipped'] == true) {
        debugPrint(
          'Ban check skipped for $email in college $collegeId; allowing access in limited verification mode.',
        );
        return const _AuthGateResult.allowed();
      }
      if (banResult?['isBanned'] == true) {
        final reason =
            (banResult?['reason'] ??
                    'Your account has been restricted by an administrator.')
                .toString();
        return _AuthGateResult.banned(reason);
      }
      return const _AuthGateResult.allowed();
    } catch (e) {
      debugPrint('Auth gate ban check failed: $e');
      return const _AuthGateResult.denied(
        'Unable to verify account access. Please try again later.',
      );
    }
  }

  Future<_AuthGateResult> _getAuthGateFuture(String collegeId) {
    final sessionKey =
        '${_authService.currentUser?.uid ?? 'unknown'}|$collegeId';
    if (_authGateFuture != null && _authGateCacheKey == sessionKey) {
      return _authGateFuture!;
    }

    _authGateCacheKey = sessionKey;
    _authGateFuture = _checkCurrentSessionAccess(collegeId);
    return _authGateFuture!;
  }

  Future<void> _forceSignOutWithReason(String message) async {
    if (_forcedSignOutInFlight) return;
    _forcedSignOutInFlight = true;
    _pendingLoginErrorMessage = message;

    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('Forced sign-out failed: $e');
    }

    if (!mounted) return;
    setState(() => _resetAuthGateCache());
  }

  @override
  Widget build(BuildContext context) {
    SupabaseService().attachContext(context);
    // First time: Show onboarding
    if (!_hasSeenOnboarding) {
      return OnboardingScreen(onComplete: _onOnboardingComplete);
    }

    // No college selected: Show college selection
    if (_selectedCollegeId == null) {
      return CollegeSelectionScreen(onCollegeSelected: _onCollegeSelected);
    }

    // Use StreamBuilder to reactively listen to auth changes
    return StreamBuilder(
      stream: _authService.authStateChanges,
      initialData: _authService.currentUser,
      builder: (context, snapshot) {
        // With initialData, we don't need to check waiting state for the first frame flicker

        final user = snapshot.data;

        if (user == null) {
          _resetAuthGateCache();

          // Double check college data exists before showing login
          if (_selectedCollegeId == null ||
              _selectedCollegeName == null ||
              _selectedCollegeDomain == null) {
            return CollegeSelectionScreen(
              onCollegeSelected: _onCollegeSelected,
            );
          }

          final initialErrorMessage = _pendingLoginErrorMessage;
          _pendingLoginErrorMessage = null;
          return LoginScreen(
            collegeName: _selectedCollegeName!,
            collegeDomain: _selectedCollegeDomain!,
            collegeId: _selectedCollegeId!,
            onChangeCollege: _onChangeCollege,
            initialErrorMessage: initialErrorMessage,
          );
        }

        // Ensure we have college info before showing home
        if (_selectedCollegeId == null || _selectedCollegeDomain == null) {
          // This case is rare but if user is logged in but prefs are cleared
          return CollegeSelectionScreen(onCollegeSelected: _onCollegeSelected);
        }

        return FutureBuilder<_AuthGateResult>(
          future: _getAuthGateFuture(_selectedCollegeId!),
          builder: (context, gateSnapshot) {
            if (gateSnapshot.connectionState == ConnectionState.waiting ||
                gateSnapshot.connectionState == ConnectionState.active) {
              return const SplashScreen();
            }

            final gateResult = gateSnapshot.data;
            if (gateSnapshot.hasError ||
                gateResult == null ||
                (!gateResult.allowed && !gateResult.isBanned)) {
              final denialReason =
                  gateResult?.denialMessage ??
                  'Unable to verify account access. Please try again later.';
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _forceSignOutWithReason(denialReason);
              });
              return const SplashScreen();
            }

            if (gateResult.isBanned) {
              return BannedUserScreen(
                reason: gateResult.denialMessage ?? 'Account suspended.',
                onSignOut: () {
                  _forceSignOutWithReason('You have signed out.');
                },
              );
            }

            return HomeScreen(
              collegeId: _selectedCollegeId!,
              collegeName: _selectedCollegeName ?? '',
              collegeDomain: _selectedCollegeDomain!,
              onLogout: _onLogout,
              onChangeCollege: _onChangeCollege,
              themeProvider: widget.themeProvider,
            );
          },
        );
      },
    );
  }
}

class _AuthGateResult {
  final bool allowed;
  final bool isBanned;
  final String? denialMessage;

  const _AuthGateResult._({
    required this.allowed,
    this.isBanned = false,
    this.denialMessage,
  });

  const _AuthGateResult.allowed() : this._(allowed: true);

  const _AuthGateResult.banned(String message)
    : this._(allowed: false, isBanned: true, denialMessage: message);

  const _AuthGateResult.denied(String message)
    : this._(allowed: false, isBanned: false, denialMessage: message);
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AppSplashAnimation(
        title: 'StudyShare',
        subtitle: 'Connect. Learn. Share.',
        loadingLabel: 'Loading StudyShare...',
      ),
    );
  }
}

class NoConnectionScreen extends StatefulWidget {
  final VoidCallback onRetry;

  const NoConnectionScreen({super.key, required this.onRetry});

  @override
  State<NoConnectionScreen> createState() => _NoConnectionScreenState();
}

class _NoConnectionScreenState extends State<NoConnectionScreen> {
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    setState(() => _isRetrying = true);
    try {
      final result = await Connectivity().checkConnectivity();
      if (!result.contains(ConnectivityResult.none)) {
        // Connected! Call the retry callback which should restart the app flow
        if (mounted) setState(() => _isRetrying = false);
        widget.onRetry();
      } else {
        if (mounted) {
          setState(() => _isRetrying = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Still no connection. Please try again.'),
            ),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Connection check failed: $e\n$stack');
      if (mounted) {
        setState(() => _isRetrying = false);
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.connectionCheckFailed ??
                  'Connection check failed. Please try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'No Internet Connection',
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please check your internet and try again',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isRetrying ? null : _handleRetry,
                icon: _isRetrying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isRetrying ? 'Checking...' : 'Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoticeDeepLinkLoader extends StatefulWidget {
  final String noticeId;
  final String collegeId;

  const NoticeDeepLinkLoader({
    super.key,
    required this.noticeId,
    required this.collegeId,
  });

  @override
  State<NoticeDeepLinkLoader> createState() => _NoticeDeepLinkLoaderState();
}

class _NoticeDeepLinkLoaderState extends State<NoticeDeepLinkLoader> {
  @override
  void initState() {
    super.initState();
    _loadNotice();
  }

  Future<void> _loadNotice() async {
    try {
      final response = await Supabase.instance.client
          .from('notices')
          .select()
          .eq('id', widget.noticeId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (response != null && mounted) {
        DepartmentAccount account;
        final deptId = response['department']?.toString();

        if (deptId != null) {
          try {
            final deptResponse = await Supabase.instance.client
                .from('departments')
                .select()
                .eq('id', deptId)
                .maybeSingle()
                .timeout(const Duration(seconds: 5));

            if (deptResponse != null) {
              account = DepartmentAccount.fromJson(deptResponse);
            } else {
              account = DepartmentAccount.unknown(deptId: deptId);
            }
          } catch (e) {
            debugPrint('Failed to fetch department for deep link: $e');
            account = DepartmentAccount.unknown(deptId: deptId);
          }
        } else {
          account = DepartmentAccount.unknown();
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => NoticeDetailScreen(
                notice: response,
                account: account,
                collegeId: widget.collegeId,
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notice not found'),
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacementNamed(context, '/');
          }
        }
      }
    } catch (e, stack) {
      debugPrint('NoticeDeepLinkLoader error: $e\n$stack');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.noticeLoadFailed ??
                  'Unable to open that notice right now. Please try again.',
            ),
            duration: const Duration(milliseconds: 1200),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
