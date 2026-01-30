import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'config/app_config.dart';
import 'config/theme.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/college_selection_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/auth_service.dart';
import 'services/download_service.dart';
import 'providers/theme_provider.dart';

/// Request necessary app permissions
Future<void> _requestPermissions() async {
  if (kIsWeb) return; // Skip on web
  
  // Request storage permissions for file access
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }
  
  // Request photos permission for gallery access (Android 13+)
  if (await Permission.photos.isDenied) {
    await Permission.photos.request();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await DownloadService().init();
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Check internet connectivity
  try {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
        runApp(
            MaterialApp(
            home: Scaffold(
                body: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    const Icon(Icons.wifi_off, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('No Internet Connection', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),
                    const Text('Please check your internet and try again'),
                    ],
                ),
                ),
            ),
            ),
        );
        return;
    }
  } catch (e) {
    debugPrint('Connectivity check failed: $e');
  }
  
  // Request permissions (Android only)
  try {
    await _requestPermissions();
  } catch (e) {
    debugPrint('Permission request failed: $e');
  }
  
  // Initialize Firebase
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyDt_mnuBryHcssBjRSdnPlh9VIC58LKL9Q",
          appId: "1:28032445048:web:025624ffdb03cfd54b1b8d",
          messagingSenderId: "28032445048",
          projectId: "studyspace-kiet",
          storageBucket: "studyspace-kiet.appspot.com",
          authDomain: "studyspace-kiet.firebaseapp.com",
        ),
      );
    } else {
      // For Android/iOS, use google-services.json / GoogleService-Info.plist
      await Firebase.initializeApp();
    }
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }
  
  // Initialize Supabase (required)
  bool supabaseInitialized = false;
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    supabaseInitialized = true;
    debugPrint('Supabase initialized successfully');
  } catch (e) {
    debugPrint('Supabase initialization error: $e');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Failed to initialize app', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text('Error: $e', style: TextStyle(color: Colors.grey[600], fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Simple restart mechanism isn't standard in pure Flutter,
                    // but we can ask user to restart.
                    // For Android we can use SystemNavigator.pop() to exit.
                    SystemNavigator.pop();
                  },
                  child: const Text('Exit App'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return;
  }
  
  if (!supabaseInitialized) return;
  
  // Get shared preferences with error handling
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('SharedPreferences error: $e');
  }
  
  final themeProvider = ThemeProvider(prefs);
  
  runApp(
    ProviderScope(
      child: prefs != null 
          ? StudySpaceApp(prefs: prefs, themeProvider: themeProvider)
          : MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('App initialization failed', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('Please restart the app', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
}

class StudySpaceApp extends StatelessWidget {
  final SharedPreferences prefs;
  final ThemeProvider themeProvider;
  
  const StudySpaceApp({super.key, required this.prefs, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeProvider,
      builder: (context, _) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          home: AppRouter(prefs: prefs, themeProvider: themeProvider),
        );
      },
    );
  }
}

class AppRouter extends StatefulWidget {
  final SharedPreferences prefs;
  final ThemeProvider themeProvider;
  
  const AppRouter({super.key, required this.prefs, required this.themeProvider});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  
  bool get _hasSeenOnboarding => widget.prefs.getBool('hasSeenOnboarding') ?? false;
  String? get _selectedCollegeId => widget.prefs.getString('selectedCollegeId');
  String? get _selectedCollegeName => widget.prefs.getString('selectedCollegeName');
  String? get _selectedCollegeDomain => widget.prefs.getString('selectedCollegeDomain');

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    // Small delay for splash effect
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _isLoading = false);
  }

  void _onOnboardingComplete() async {
    await widget.prefs.setBool('hasSeenOnboarding', true);
    setState(() {});
  }

  void _onCollegeSelected(String id, String name, String domain) async {
    await widget.prefs.setString('selectedCollegeId', id);
    await widget.prefs.setString('selectedCollegeName', name);
    await widget.prefs.setString('selectedCollegeDomain', domain);
    setState(() {});
  }

  void _onLogout() async {
    await _authService.signOut();
    setState(() {});
  }

  void _onChangeCollege() async {
    await widget.prefs.remove('selectedCollegeId');
    await widget.prefs.remove('selectedCollegeName');
    await widget.prefs.remove('selectedCollegeDomain');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
      builder: (context, snapshot) {
        // While checking auth state, show loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        
        final user = snapshot.data;
        
        if (user == null) {
          // Double check college data exists before showing login
          if (_selectedCollegeId == null || _selectedCollegeName == null || _selectedCollegeDomain == null) {
            return CollegeSelectionScreen(onCollegeSelected: _onCollegeSelected);
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
          collegeId: _selectedCollegeDomain!, // Use domain for Supabase queries (data uses 'kiet.edu' not UUID)
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo with Notion-style animation
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.school_rounded,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppConfig.appName,
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.textLight : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Academic Companion',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
