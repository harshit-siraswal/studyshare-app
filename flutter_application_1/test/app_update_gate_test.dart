import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/services/app_update_service.dart';
import 'package:flutter_application_1/widgets/app_update_gate.dart';

PackageInfo _packageInfo() {
  return PackageInfo(
    appName: 'StudyShare',
    packageName: 'me.studyshare.android',
    version: '1.0.31',
    buildNumber: '2037',
    buildSignature: '',
    installerStore: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a persistent banner for available Android updates', (
    tester,
  ) async {
    final service = AppUpdateService(
      releaseInfoProvider: () async => {
        'version': '1.0.32',
        'buildNumber': 2038,
        'apkUrl': 'https://studyshare.in/downloads/studyshare-android.apk',
        'releaseNotes': ['Update banner support'],
      },
      packageInfoProvider: () async => _packageInfo(),
      isAndroidProvider: () => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdateGate(
          service: service,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Update available: v1.0.32'), findsOneWidget);
    expect(find.text('New version 1.0.32 available'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Update available: v1.0.32'), findsNothing);
    expect(find.text('New version 1.0.32 available'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });
}
