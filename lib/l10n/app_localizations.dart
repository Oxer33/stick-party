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

  /// Subtitle under the STICK PARTY logo on the home screen. The dot separators and digits should stay as-is.
  ///
  /// In en, this message translates to:
  /// **'2 • 3 • 4 PLAYER GAMES'**
  String get homeTagline;

  /// Label of the settings chip in the home top bar. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get navSettings;

  /// The big primary call-to-action button on the home screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'QUICK PLAY'**
  String get quickPlay;

  /// Label of the Cup / tournament action card on the home screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'CUP'**
  String get actionCup;

  /// Supporting line under the CUP action card.
  ///
  /// In en, this message translates to:
  /// **'Tournament'**
  String get actionCupHint;

  /// Label of the Shop action card on the home screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'SHOP'**
  String get actionShop;

  /// Supporting line under the SHOP action card.
  ///
  /// In en, this message translates to:
  /// **'Skins & themes'**
  String get actionShopHint;

  /// Label of the Daily action card on the home screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'DAILY'**
  String get actionDaily;

  /// Supporting line under the DAILY card when a daily reward is ready to claim.
  ///
  /// In en, this message translates to:
  /// **'Reward ready'**
  String get actionDailyHintReady;

  /// Supporting line under the DAILY card when no daily reward is pending.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get actionDailyHintDefault;

  /// Label of the Stats action card on the home screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'STATS'**
  String get actionStats;

  /// Supporting line under the STATS action card.
  ///
  /// In en, this message translates to:
  /// **'Your records'**
  String get actionStatsHint;

  /// Eyebrow label on the cross-promo 'more games' teaser card. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'MORE GAMES'**
  String get moreGames;

  /// Header over the horizontal games catalog strip, e.g. '15 GAMES'. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'{count} GAMES'**
  String gamesCount(int count);

  /// Title of the game-select screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'PICK A GAME'**
  String get pickAGame;

  /// Empty-state message on the game-select screen when no game supports the chosen player count.
  ///
  /// In en, this message translates to:
  /// **'No games for this player count.'**
  String get noGamesForPlayerCount;

  /// Name of the Sumo Smash minigame: players shove each other out of a ring.
  ///
  /// In en, this message translates to:
  /// **'Sumo Smash'**
  String get game_sumo_smash;

  /// Name of the Bumper Balls minigame: players bump rivals off an arena.
  ///
  /// In en, this message translates to:
  /// **'Bumper Balls'**
  String get game_bumper_balls;

  /// Name of the One-Touch Soccer minigame: fast tap-to-kick football duel.
  ///
  /// In en, this message translates to:
  /// **'One-Touch Soccer'**
  String get game_one_touch_soccer;

  /// Name of the Tank Duel minigame: players shoot each other with tanks.
  ///
  /// In en, this message translates to:
  /// **'Tank Duel'**
  String get game_tank_duel;

  /// Name of the Archer Pop minigame: aim and pop targets with arrows.
  ///
  /// In en, this message translates to:
  /// **'Archer Pop'**
  String get game_archer_pop;

  /// Name of the Chicken Jump minigame: jump up a tower of rungs as high as possible.
  ///
  /// In en, this message translates to:
  /// **'Chicken Jump'**
  String get game_chicken_jump;

  /// Name of the Falling Dodge minigame: dodge falling objects to survive.
  ///
  /// In en, this message translates to:
  /// **'Falling Dodge'**
  String get game_falling_dodge;

  /// Name of the Tap Sprint minigame: tap rapidly to sprint to the finish.
  ///
  /// In en, this message translates to:
  /// **'Tap Sprint'**
  String get game_tap_sprint;

  /// Name of the Tug of War minigame: two sides pull a rope.
  ///
  /// In en, this message translates to:
  /// **'Tug of War'**
  String get game_tug_of_war;

  /// Name of the Button Masher minigame: mash a button as fast as possible.
  ///
  /// In en, this message translates to:
  /// **'Button Masher'**
  String get game_button_masher;

  /// Name of the Reaction Duel minigame: tap the instant the signal appears.
  ///
  /// In en, this message translates to:
  /// **'Reaction Duel'**
  String get game_reaction_duel;

  /// Name of the Snake Arena minigame: grow a snake and outlast rivals.
  ///
  /// In en, this message translates to:
  /// **'Snake Arena'**
  String get game_snake_arena;

  /// Name of the Paint Splash minigame: cover the most area with paint.
  ///
  /// In en, this message translates to:
  /// **'Paint Splash'**
  String get game_paint_splash;

  /// Name of the Catch the Star minigame: grab the star before rivals do.
  ///
  /// In en, this message translates to:
  /// **'Catch the Star'**
  String get game_catch_the_star;

  /// Name of the Color Memory minigame: repeat the growing color sequence.
  ///
  /// In en, this message translates to:
  /// **'Color Memory'**
  String get game_color_memory;

  /// Input-hint chip meaning the player taps the screen. Shown in all caps; keep very short.
  ///
  /// In en, this message translates to:
  /// **'TAP'**
  String get hint_tap;

  /// Input-hint chip meaning the player presses and holds. Shown in all caps; keep very short.
  ///
  /// In en, this message translates to:
  /// **'HOLD'**
  String get hint_hold;

  /// Input-hint chip meaning the player taps as fast as possible (mashing). Shown in all caps; keep very short.
  ///
  /// In en, this message translates to:
  /// **'MASH'**
  String get hint_mash;

  /// Input-hint chip meaning the player moves / steers. Shown in all caps; keep very short.
  ///
  /// In en, this message translates to:
  /// **'MOVE'**
  String get hint_move;

  /// Input-hint chip meaning the player drags a finger. Shown in all caps; keep very short.
  ///
  /// In en, this message translates to:
  /// **'DRAG'**
  String get hint_drag;
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
