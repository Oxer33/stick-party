import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('ru'),
    Locale('zh'),
  ];

  /// Title of the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Header for the gameplay settings section.
  ///
  /// In en, this message translates to:
  /// **'Gameplay'**
  String get sectionGameplay;

  /// Label for the CPU (bot) difficulty selector.
  ///
  /// In en, this message translates to:
  /// **'CPU Difficulty'**
  String get cpuDifficulty;

  /// Easy CPU difficulty option.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasy;

  /// Medium CPU difficulty option.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get difficultyMedium;

  /// Hard CPU difficulty option.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get difficultyHard;

  /// Label for the screen shake intensity slider.
  ///
  /// In en, this message translates to:
  /// **'Screen Shake'**
  String get screenShake;

  /// Header for the language selection section.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get sectionLanguage;

  /// Option that follows the device's system language.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// Header for the purchases settings section.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get sectionPurchases;

  /// Label for the restore purchases action.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchases'**
  String get restorePurchases;

  /// Supporting text under the restore purchases action.
  ///
  /// In en, this message translates to:
  /// **'Re-apply your one-time unlocks'**
  String get restorePurchasesDesc;

  /// Snackbar shown after purchases are restored.
  ///
  /// In en, this message translates to:
  /// **'Purchases restored.'**
  String get purchasesRestored;

  /// Header for the data / reset settings section.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get sectionData;

  /// Label for the reset progress action.
  ///
  /// In en, this message translates to:
  /// **'Reset Progress'**
  String get resetProgress;

  /// Supporting text under the reset progress action.
  ///
  /// In en, this message translates to:
  /// **'Erase coins, unlocks and stats'**
  String get resetProgressDesc;

  /// Title of the reset progress confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Reset progress?'**
  String get resetConfirmTitle;

  /// Body of the reset progress confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'This permanently erases your coins, cosmetics and stats. This cannot be undone.'**
  String get resetConfirmBody;

  /// Generic cancel button label.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// Confirm button label for the reset action.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get actionReset;

  /// Snackbar shown after progress is reset.
  ///
  /// In en, this message translates to:
  /// **'Progress reset.'**
  String get progressReset;

  /// About / legal blurb shown at the bottom of Settings.
  ///
  /// In en, this message translates to:
  /// **'Rated Everyone. Plays fully offline. No accounts, no tracking. In-app purchases are cosmetic only and never affect gameplay — no loot boxes, no pay-to-win, no dark patterns.'**
  String get aboutBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'pt',
    'ru',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
