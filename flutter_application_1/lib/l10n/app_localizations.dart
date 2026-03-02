import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppLocalizations {
  static const List<String> supportedLanguageCodes = <String>['en'];
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get success => Intl.message('Success!', name: 'success');

  String get selectCollegeBeforeDeepLink => Intl.message(
    'Please select a college before opening deep links.',
    name: 'selectCollegeBeforeDeepLink',
  );

  String get connectionCheckFailed => Intl.message(
    'Connection check failed. Please try again.',
    name: 'connectionCheckFailed',
  );

  String get noticeLoadFailed => Intl.message(
    'Unable to open that notice right now. Please try again.',
    name: 'noticeLoadFailed',
  );
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLanguageCodes.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    Intl.defaultLocale = locale.toString();
    return AppLocalizations();
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
