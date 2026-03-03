import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/providers/theme_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final themeProvider = ThemeProvider(prefs);

    await tester.pumpWidget(
      ProviderScope(
        child: StudyShareApp(prefs: prefs, themeProvider: themeProvider),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StudyShareApp), findsOneWidget);
  });
}


