import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'l10n/app_localizations.dart';
import 'config/app_config.dart';
import 'config/theme.dart';
import 'config/firebase_options.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/college_selection_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/auth_service.dart';
import 'services/download_service.dart';
import 'services/push_notification_service.dart';
import 'services/backend_api_service.dart';
import 'providers/theme_provider.dart';
import 'widgets/global_timer_overlay.dart';
import 'widgets/branded_loader.dart';
import 'utils/app_navigator.dart';
import 'services/supabase_service.dart';

/// Request necessary app permissions
/// Returns true if all critical permissions are granted or not required
Future<bool> _requestPermissions() async {
  if (kIsWeb) return true; // Skip on web

  if (Platform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    Map<Permission, PermissionStatus> statuses = {};

    if (sdkInt >= 33) {
      // Android 13+: Request granular media permissions
      statuses = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();
    } else {
      // Android 12 and below: Request storage permission
      statuses = await [Permission.storage].request();
    }

    // Check results
    bool allGranted = true;
    bool permanentlyDenied = false;

    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
      }
      if (status.isPermanentlyDenied) {
        permanentlyDenied = true;
      }
    });

    return allGranted;
  }

  return true; // iOS or other platforms, handled by plist or similar
}

// Top-level navigator key for global access

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Validate configuration and log any warnings
  // Validate configuration
  final configResult = AppConfig.validate();

  if (!configResult.isValid) {
    for (final error in configResult.errors) {
      // Use debugPrint for logged output (print may be stripped or swallowed)
      debugPrint('CRITICAL CONFIG ERROR: $error');
    }
    throw Exception(
      'App Configuration Failed: ${configResult.errors.join(", ")}',
    );
  }

  for (final warning in configResult.warnings) {
    debugPrint('Configuration Warning: $warning');
  }

  try {
    await Hive.initFlutter();
  } catch (e) {
    debugPrint('Hive initialization error: $e');
    rethrow; // Hive is required for app functionality
  }

  try {
    await DownloadService().init();
  } catch (e) {
    debugPrint('DownloadService initialization error: $e');
    // Non-critical: log and continue, downloads will fail gracefully
  }

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
  // Expose key if needed via static accessor, but top-level is fine too
  static GlobalKey<NavigatorState> get navKey => appNavigatorKey;

  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  AppState _appState = AppState.loading;
  SharedPreferences? _prefs;
  ThemeProvider? _themeProvider;

  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    if (!mounted) return;
    setState(() => _appState = AppState.loading);

    // Check internet connectivity
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        if (mounted) setState(() => _appState = AppState.noConnection);
        return;
      }
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
    }

    await _continueStartup();
  }

  Future<void> _continueStartup() async {
    // Request permissions (Android only)
    bool permissionsGranted = true;
    try {
      permissionsGranted = await _requestPermissions();
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }

    if (!permissionsGranted && !kIsWeb) {
      if (mounted) setState(() => _appState = AppState.permissionError);
      return;
    }

    // Initialize Firebase
    try {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        await Firebase.initializeApp();
      }
      debugPrint('Firebase initialized successfully');
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
    }

    // Initialize Supabase (required)
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      debugPrint('Supabase initialized successfully');
    } catch (e) {
      debugPrint('Supabase initialization error: $e');
      if (mounted) {
        setState(() {
          _appState = AppState.initializationError;
        });
      }
      return;
    }
    // Get shared preferences
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SharedPreferences error: $e');
      if (mounted) {
        setState(() {
          _appState = AppState.initializationError;
        });
      }
      return;
    }

    // Initialize Push Notifications (after Firebase is ready)
    if (!kIsWeb) {
      try {
        // Set up background message handler
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );

        final pushService = PushNotificationService();
        final backendApi = BackendApiService();

        await pushService.initialize(
          onTokenRefresh: (token) async {
            // Register token with backend
            try {
              final platform = Platform.isIOS ? 'ios' : 'android';
              await backendApi.registerFcmToken(
                token: token,
                platform: platform,
              );
              debugPrint('FCM token registered with backend');
            } catch (e) {
              debugPrint('Failed to register FCM token: $e');
            }
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
                  await appNavigatorKey.currentState?.pushNamed(actionUrl);
                } else {
                  // External navigation
                  final uri = Uri.parse(actionUrl);
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
        debugPrint('Push notifications initialized');
      } catch (e) {
        debugPrint('Push notification initialization error: $e');
        // Don't fail startup for push notification errors
      }
    }

    if (mounted) {
      // Only initialize ThemeProvider after _prefs is successfully loaded
      _themeProvider = ThemeProvider(_prefs);
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
                    'MyStudySpace needs access to storage/media to function correctly. Please grant permissions in settings.',
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
                const Text(
                  'An unexpected error occurred. Please restart the app.',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
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
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: AppSplashAnimation(
            title: 'MyStudySpace',
            subtitle: 'Connect. Learn. Share.',
            loadingLabel: 'Starting MyStudySpace...',
          ),
        ),
      );
    }

    // AppState.ready
    return ProviderScope(
      child: StudySpaceApp(prefs: _prefs!, themeProvider: _themeProvider!),
    );
  }
}

class StudySpaceApp extends StatelessWidget {
  final SharedPreferences prefs;
  final ThemeProvider themeProvider;

  const StudySpaceApp({
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
            return MaterialApp(
              title: AppConfig.appName,
              debugShowCheckedModeBanner: false,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
              navigatorKey: appNavigatorKey,
              theme: AppTheme.lightTheme(lightDynamic),
              darkTheme: AppTheme.darkTheme(darkDynamic),
              themeMode: themeProvider.themeMode,
              home: AppRouter(prefs: prefs, themeProvider: themeProvider),
              builder: (context, child) =>
                  GlobalTimerOverlay(child: child ?? const SizedBox.shrink()),
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
  bool _isLoading = true;

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
  String? get _selectedCollegeId =>
      _selectedCollegeData?['id'] ??
      widget.prefs.getString('selectedCollegeId');
  String? get _selectedCollegeName =>
      _selectedCollegeData?['name'] ??
      widget.prefs.getString('selectedCollegeName');
  String? get _selectedCollegeDomain =>
      _selectedCollegeData?['domain'] ??
      widget.prefs.getString('selectedCollegeDomain');

  @override
  void initState() {
    super.initState();
    _showSplash();
  }

  Future<void> _showSplash() async {
    // Small delay for splash effect
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _isLoading = false);
  }

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

  @override
  Widget build(BuildContext context) {
    SupabaseService().attachContext(context);
    if (_isLoading) {
      return const SplashScreen();
    }

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
          // Double check college data exists before showing login
          if (_selectedCollegeId == null ||
              _selectedCollegeName == null ||
              _selectedCollegeDomain == null) {
            return CollegeSelectionScreen(
              onCollegeSelected: _onCollegeSelected,
            );
          }

          return LoginScreen(
            collegeName: _selectedCollegeName!,
            collegeDomain: _selectedCollegeDomain!,
            collegeId: _selectedCollegeId!,
            onChangeCollege: _onChangeCollege,
          );
        }

        // Ensure we have college info before showing home
        if (_selectedCollegeId == null || _selectedCollegeDomain == null) {
          // This case is rare but if user is logged in but prefs are cleared
          return CollegeSelectionScreen(onCollegeSelected: _onCollegeSelected);
        }

        // Logged in: Show home
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
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AppSplashAnimation(
        title: 'MyStudySpace',
        subtitle: 'Connect. Learn. Share.',
        loadingLabel: 'Preparing your study space...',
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
    } catch (e) {
      if (mounted) {
        setState(() => _isRetrying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connection check failed: $e')));
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
