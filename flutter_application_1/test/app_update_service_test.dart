import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/services/app_update_service.dart';

PackageInfo _packageInfo({
  String version = '1.0.30',
  String buildNumber = '2036',
}) {
  return PackageInfo(
    appName: 'StudyShare',
    packageName: 'me.studyshare.android',
    version: version,
    buildNumber: buildNumber,
    buildSignature: '',
    installerStore: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('compares semantic versions numerically', () {
    expect(AppUpdateService.compareVersions('1.0.31', '1.0.30'), 1);
    expect(AppUpdateService.compareVersions('1.0.9', '1.0.30'), -1);
    expect(AppUpdateService.compareVersions('1.0.30+2036', '1.0.30'), 0);
  });

  test('returns release when remote build is newer', () async {
    final service = AppUpdateService(
      releaseInfoProvider: () async => {
        'version': '1.0.31',
        'buildNumber': 2037,
        'apkUrl': 'https://studyshare.in/downloads/studyshare-android.apk',
      },
      packageInfoProvider: () async => _packageInfo(),
      isAndroidProvider: () => true,
    );

    final release = await service.checkForUpdate();

    expect(release, isNotNull);
    expect(release!.version, '1.0.31');
    expect(release.buildNumber, 2037);
  });

  test(
    'suppresses releases dismissed for the same version and build',
    () async {
      final service = AppUpdateService(
        releaseInfoProvider: () async => {
          'version': '1.0.31',
          'buildNumber': 2037,
          'apkUrl': 'https://studyshare.in/downloads/studyshare-android.apk',
        },
        packageInfoProvider: () async => _packageInfo(),
        isAndroidProvider: () => true,
      );

      final release = await service.checkForUpdate();
      expect(release, isNotNull);

      await service.dismissRelease(release!);
      expect(await service.isReleaseDismissed(release), isTrue);
      expect(await service.checkForUpdate(), isNull);
      expect(await service.checkForUpdate(includeDismissed: true), isNotNull);
    },
  );

  test('rejects untrusted APK hosts', () async {
    final service = AppUpdateService(
      releaseInfoProvider: () async => {
        'version': '1.0.31',
        'buildNumber': 2037,
        'apkUrl': 'https://example.com/downloads/studyshare-android.apk',
      },
      packageInfoProvider: () async => _packageInfo(),
      isAndroidProvider: () => true,
    );

    expect(await service.checkForUpdate(), isNull);
  });
}
