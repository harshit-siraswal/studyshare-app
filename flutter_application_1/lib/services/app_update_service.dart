import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api_service.dart';

typedef ReleaseInfoProvider = Future<Map<String, dynamic>> Function();
typedef PackageInfoProvider = Future<PackageInfo> Function();
typedef PreferencesProvider = Future<SharedPreferences> Function();
typedef PlatformProvider = bool Function();

class AndroidReleaseInfo {
  const AndroidReleaseInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseDate,
    required this.mandatory,
    required this.releaseNotes,
  });

  final String version;
  final int buildNumber;
  final String apkUrl;
  final String releaseDate;
  final bool mandatory;
  final List<String> releaseNotes;

  String get releaseKey => '$version+$buildNumber';

  static AndroidReleaseInfo? fromJson(Map<String, dynamic> json) {
    final version = (json['version'] ?? json['latestVersion'])
        ?.toString()
        .trim();
    final apkUrl = (json['apkUrl'] ?? json['apk_url'])?.toString().trim();
    final buildNumber = _parseBuildNumber(
      json['buildNumber'] ?? json['build_number'],
    );

    if (version == null ||
        version.isEmpty ||
        apkUrl == null ||
        apkUrl.isEmpty ||
        buildNumber <= 0) {
      return null;
    }

    return AndroidReleaseInfo(
      version: version,
      buildNumber: buildNumber,
      apkUrl: apkUrl,
      releaseDate:
          (json['releaseDate'] ?? json['release_date'])?.toString().trim() ??
          '',
      mandatory: json['mandatory'] == true || json['required'] == true,
      releaseNotes: _parseReleaseNotes(json['releaseNotes']),
    );
  }

  static int _parseBuildNumber(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  static List<String> _parseReleaseNotes(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'\r?\n|\|'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class AppUpdateService {
  AppUpdateService({
    BackendApiService? backendApi,
    http.Client? httpClient,
    ReleaseInfoProvider? releaseInfoProvider,
    PackageInfoProvider? packageInfoProvider,
    PreferencesProvider? preferencesProvider,
    PlatformProvider? isAndroidProvider,
  }) : _backendApi =
           backendApi ??
           (releaseInfoProvider == null ? BackendApiService() : null),
       _httpClient = httpClient ?? http.Client(),
       _releaseInfoProvider = releaseInfoProvider,
       _packageInfoProvider = packageInfoProvider ?? PackageInfo.fromPlatform,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance,
       _isAndroidProvider =
           isAndroidProvider ?? (() => !kIsWeb && Platform.isAndroid);

  static const String _dismissedReleaseKey = 'dismissed_android_release_key';
  static const Duration _fallbackTimeout = Duration(seconds: 8);
  static const String _fallbackReleaseUrl = String.fromEnvironment(
    'APP_UPDATE_FALLBACK_URL',
    defaultValue: 'https://studyshare.in/android-release.json',
  );

  final BackendApiService? _backendApi;
  final http.Client _httpClient;
  final ReleaseInfoProvider? _releaseInfoProvider;
  final PackageInfoProvider _packageInfoProvider;
  final PreferencesProvider _preferencesProvider;
  final PlatformProvider _isAndroidProvider;

  Future<AndroidReleaseInfo?> checkForUpdate({
    bool includeDismissed = false,
  }) async {
    if (!_isAndroidProvider()) return null;

    final packageInfo = await _packageInfoProvider();
    final currentBuild = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
    final release = await _fetchReleaseInfo();
    if (release == null) return null;
    if (!_isTrustedApkUrl(release.apkUrl)) return null;
    if (!_isNewerRelease(
      currentVersion: packageInfo.version,
      currentBuild: currentBuild,
      release: release,
    )) {
      return null;
    }

    if (!includeDismissed) {
      final prefs = await _preferencesProvider();
      if (prefs.getString(_dismissedReleaseKey) == release.releaseKey) {
        return null;
      }
    }

    return release;
  }

  Future<void> dismissRelease(AndroidReleaseInfo release) async {
    final prefs = await _preferencesProvider();
    await prefs.setString(_dismissedReleaseKey, release.releaseKey);
  }

  Future<bool> isReleaseDismissed(AndroidReleaseInfo release) async {
    final prefs = await _preferencesProvider();
    return prefs.getString(_dismissedReleaseKey) == release.releaseKey;
  }

  Future<AndroidReleaseInfo?> _fetchReleaseInfo() async {
    try {
      final provider = _releaseInfoProvider;
      final data = provider == null
          ? await _backendApi!.getAndroidReleaseInfo()
          : await provider();
      final release = AndroidReleaseInfo.fromJson(data);
      if (release != null) return release;
    } catch (error) {
      debugPrint('Android update API check failed: $error');
    }

    try {
      final uri = Uri.parse(_fallbackReleaseUrl);
      final response = await _httpClient.get(uri).timeout(_fallbackTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return AndroidReleaseInfo.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('Android update fallback check failed: $error');
      return null;
    }
  }

  bool _isNewerRelease({
    required String currentVersion,
    required int currentBuild,
    required AndroidReleaseInfo release,
  }) {
    if (release.buildNumber > currentBuild) return true;
    if (release.buildNumber < currentBuild) return false;
    return compareVersions(release.version, currentVersion) > 0;
  }

  bool _isTrustedApkUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      final host = uri.host.toLowerCase();
      return uri.scheme == 'https' &&
          (host == 'studyshare.in' || host.endsWith('.studyshare.in')) &&
          uri.path.toLowerCase().endsWith('.apk');
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static int compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var index = 0; index < maxLength; index += 1) {
      final leftValue = index < leftParts.length ? leftParts[index] : 0;
      final rightValue = index < rightParts.length ? rightParts[index] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }

    return 0;
  }

  static List<int> _versionParts(String version) {
    final normalized = version.split('+').first.split('-').first;
    return normalized
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList(growable: false);
  }
}
