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

  /// Title of the players setup screen when configuring a cup / tournament. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'CUP SETUP'**
  String get cupSetupTitle;

  /// Header of the seat-count panel on the players setup screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'PLAYERS'**
  String get playersTitle;

  /// Helper line under the PLAYERS header telling the user the maximum number of seats.
  ///
  /// In en, this message translates to:
  /// **'Add up to {max}'**
  String playersAddUpTo(int max);

  /// Label for a seat controlled by a human player. Shown in all caps; keep short.
  ///
  /// In en, this message translates to:
  /// **'HUMAN'**
  String get seatHuman;

  /// Label for a seat controlled by the computer (bot). Shown in all caps; keep short.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get seatCpu;

  /// Header over the match-mode selector on the players setup screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'MODE'**
  String get modeLabel;

  /// Match-mode option: everyone competes against everyone. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'FREE FOR ALL'**
  String get modeFreeForAll;

  /// Match-mode option: a one-versus-one duel. Keep the digits and 'v' spacing as-is.
  ///
  /// In en, this message translates to:
  /// **'1 v 1'**
  String get modeDuel1v1;

  /// Match-mode option: two-versus-two teams. Keep the digits and 'v' spacing as-is.
  ///
  /// In en, this message translates to:
  /// **'2 v 2'**
  String get modeTeam2v2;

  /// Match-mode option: three-versus-three teams. Keep the digits and 'v' spacing as-is.
  ///
  /// In en, this message translates to:
  /// **'3 v 3'**
  String get modeTeam3v3;

  /// Primary button that starts a quick-play match from the setup screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'START'**
  String get actionStart;

  /// Primary button that starts a cup / tournament from the setup screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'START CUP'**
  String get startCup;

  /// Section header in the shop for stickman character skins. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'STICK SKINS'**
  String get shopStickSkins;

  /// Section header in the shop for arena / map themes. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'MAP THEMES'**
  String get shopMapThemes;

  /// Section header in the shop for the real-money in-app purchase catalog. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'STORE'**
  String get shopStore;

  /// Small eyebrow label above a single stick-skin item in the shop. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'STICK SKIN'**
  String get shopStickSkinEyebrow;

  /// Small eyebrow label above a single map-theme item in the shop. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'MAP THEME'**
  String get shopMapThemeEyebrow;

  /// Eyebrow label for a consumable in-app purchase that grants coins. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'COIN PACK'**
  String get shopCoinPack;

  /// Eyebrow label for a non-consumable one-time in-app purchase. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'UNLOCK'**
  String get shopUnlockEyebrow;

  /// Status line for a cosmetic that is free and permanently owned. Keep the • separator.
  ///
  /// In en, this message translates to:
  /// **'Free • always yours'**
  String get shopFreeAlwaysYours;

  /// Status line for the cosmetic skin currently selected / equipped.
  ///
  /// In en, this message translates to:
  /// **'Equipped'**
  String get shopEquipped;

  /// Status line for a cosmetic the player owns but has not equipped.
  ///
  /// In en, this message translates to:
  /// **'Owned'**
  String get shopOwned;

  /// Price of a cosmetic shown as a number of coins, e.g. '500 coins'.
  ///
  /// In en, this message translates to:
  /// **'{count} coins'**
  String shopPriceCoins(int count);

  /// Supporting line for a coin-pack in-app purchase.
  ///
  /// In en, this message translates to:
  /// **'Top up your coins'**
  String get shopTopUpCoins;

  /// Supporting line for a non-consumable one-time in-app purchase.
  ///
  /// In en, this message translates to:
  /// **'One-time unlock'**
  String get shopOneTimeUnlock;

  /// Button to buy a cosmetic with coins. Shown in all caps; keep short.
  ///
  /// In en, this message translates to:
  /// **'BUY'**
  String get shopBuy;

  /// Button to equip an owned cosmetic skin. Shown in all caps; keep short.
  ///
  /// In en, this message translates to:
  /// **'USE'**
  String get shopUse;

  /// Snackbar confirming a cosmetic was bought, e.g. 'Unlocked Lava Skin!'.
  ///
  /// In en, this message translates to:
  /// **'Unlocked {name}!'**
  String shopUnlocked(String name);

  /// Snackbar shown when the player cannot afford a cosmetic.
  ///
  /// In en, this message translates to:
  /// **'Not enough coins.'**
  String get shopNotEnoughCoins;

  /// Snackbar confirming a real-money in-app purchase succeeded, e.g. 'Purchased Coin Pack.'.
  ///
  /// In en, this message translates to:
  /// **'Purchased {title}.'**
  String shopPurchased(String title);

  /// Snackbar shown when a real-money in-app purchase fails, with the error reason.
  ///
  /// In en, this message translates to:
  /// **'Purchase failed: {error}'**
  String shopPurchaseFailed(String error);

  /// Reassurance note at the bottom of the shop that purchases are cosmetic-only and prices are honest.
  ///
  /// In en, this message translates to:
  /// **'Purchases are cosmetic only and never affect gameplay. Prices shown are real and set by the app store.'**
  String get shopEthicsNote;

  /// Section header for the once-per-day login bonus on the Daily screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'LOGIN BONUS'**
  String get loginBonus;

  /// Section header for the list of daily missions on the Daily screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'TODAY\'S MISSIONS'**
  String get todaysMissions;

  /// Snackbar shown after claiming the daily login bonus that pays coins, e.g. 'Claimed +50 coins!'.
  ///
  /// In en, this message translates to:
  /// **'Claimed +{count} coins!'**
  String claimedCoins(int count);

  /// Snackbar shown after claiming a daily reward that does not pay coins.
  ///
  /// In en, this message translates to:
  /// **'Reward claimed!'**
  String get rewardClaimed;

  /// Label for which day of the login-bonus cycle the player is on, e.g. 'DAY 3'. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'DAY {day}'**
  String dayN(int day);

  /// A coin reward amount shown with a leading plus sign, e.g. '+50 coins'.
  ///
  /// In en, this message translates to:
  /// **'+{count} coins'**
  String coinsAmount(int count);

  /// Describes a daily login reward that grants a cosmetic token instead of coins, e.g. '1 cosmetic reward'.
  ///
  /// In en, this message translates to:
  /// **'{count} cosmetic reward'**
  String cosmeticReward(int count);

  /// Supporting line on the login-bonus card after the player has already claimed today's bonus.
  ///
  /// In en, this message translates to:
  /// **'Come back tomorrow'**
  String get comeBackTomorrow;

  /// Supporting line on the login-bonus card prompting the player to claim today's bonus.
  ///
  /// In en, this message translates to:
  /// **'Tap claim to collect'**
  String get tapClaimToCollect;

  /// Button to claim the daily login bonus. Shown in all caps; keep short.
  ///
  /// In en, this message translates to:
  /// **'CLAIM'**
  String get claim;

  /// Disabled button state after the daily login bonus has been claimed. Shown in all caps; keep short.
  ///
  /// In en, this message translates to:
  /// **'CLAIMED'**
  String get claimed;

  /// Daily mission objective to play a number of rounds, e.g. 'Play 5 rounds'.
  ///
  /// In en, this message translates to:
  /// **'Play {count} rounds'**
  String missionPlayRounds(int count);

  /// Daily mission objective to win a number of rounds, e.g. 'Win 3 rounds'.
  ///
  /// In en, this message translates to:
  /// **'Win {count} rounds'**
  String missionWinRounds(int count);

  /// Daily mission objective to win a cup / tournament.
  ///
  /// In en, this message translates to:
  /// **'Win a cup'**
  String get missionWinCup;

  /// Daily mission objective to play a mini-game the player has not played before.
  ///
  /// In en, this message translates to:
  /// **'Try a new game'**
  String get missionTryNewGame;

  /// Daily mission objective to play a match with a number of players, e.g. 'Play with 4 players'.
  ///
  /// In en, this message translates to:
  /// **'Play with {count} players'**
  String missionPlayWithPlayers(int count);

  /// Cup progress chip during a game showing the current game number out of the total, e.g. 'GAME 2/5'. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'GAME {current}/{total}'**
  String cupGameProgress(int current, int total);

  /// Title of the cup standings screen between games, e.g. 'STANDINGS • 2/5'. Shown in all caps; keep the • separator.
  ///
  /// In en, this message translates to:
  /// **'STANDINGS • {current}/{total}'**
  String cupStandingsTitle(int current, int total);

  /// Button on the cup standings that advances to the next game, e.g. 'NEXT GAME (3/5)'. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'NEXT GAME ({current}/{total})'**
  String cupNextGameButton(int current, int total);

  /// A player's cup score shown as points, e.g. '12 pts'. Keep the abbreviation short.
  ///
  /// In en, this message translates to:
  /// **'{count} pts'**
  String cupPoints(int count);

  /// Title of the cup results / podium screen shown at the end of a tournament. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'CHAMPION'**
  String get cupChampionTitle;

  /// Eyebrow label above the winner's name on the champion podium banner. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'CUP CHAMPION'**
  String get cupChampionBanner;

  /// Button to start a new cup with the same players. Shown in all caps; keep short.
  ///
  /// In en, this message translates to:
  /// **'REMATCH'**
  String get cupRematch;

  /// Button to return to the home screen from the cup results. Shown in all caps; keep short.
  ///
  /// In en, this message translates to:
  /// **'HOME'**
  String get cupHome;

  /// Eyebrow label on the upcoming-game card in the cup standings. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'NEXT GAME'**
  String get cupNextGame;

  /// Round position on the cup next-game card, e.g. 'Round 3 of 5'.
  ///
  /// In en, this message translates to:
  /// **'Round {current} of {total}'**
  String cupRoundOf(int current, int total);

  /// Section header for lifetime career counters on the Stats screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'CAREER'**
  String get statsCareer;

  /// Caption for the coins counter tile on the Stats screen.
  ///
  /// In en, this message translates to:
  /// **'Coins'**
  String get statCoins;

  /// Caption for the rounds-played counter tile on the Stats screen.
  ///
  /// In en, this message translates to:
  /// **'Rounds played'**
  String get statRoundsPlayed;

  /// Caption for the cups-won counter tile on the Stats screen.
  ///
  /// In en, this message translates to:
  /// **'Cups won'**
  String get statCupsWon;

  /// Caption for the knockouts counter tile on the Stats screen.
  ///
  /// In en, this message translates to:
  /// **'Knockouts'**
  String get statKnockouts;

  /// Section header for the per-game best scores list on the Stats screen. Shown in all caps.
  ///
  /// In en, this message translates to:
  /// **'BEST SCORES'**
  String get statsBestScores;

  /// Section header for the achievements list showing how many are unlocked, e.g. 'ACHIEVEMENTS  4/12'. Shown in all caps; keep the double space.
  ///
  /// In en, this message translates to:
  /// **'ACHIEVEMENTS  {unlocked}/{total}'**
  String statsAchievements(int unlocked, int total);

  /// Supporting line under a per-game record tile on the Stats screen indicating the value is the player's best score.
  ///
  /// In en, this message translates to:
  /// **'Best score'**
  String get statBestScore;
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
