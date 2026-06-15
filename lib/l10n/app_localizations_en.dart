// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionGameplay => 'Gameplay';

  @override
  String get cpuDifficulty => 'CPU Difficulty';

  @override
  String get difficultyEasy => 'Easy';

  @override
  String get difficultyMedium => 'Medium';

  @override
  String get difficultyHard => 'Hard';

  @override
  String get screenShake => 'Screen Shake';

  @override
  String get sectionLanguage => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get sectionPurchases => 'Purchases';

  @override
  String get restorePurchases => 'Restore Purchases';

  @override
  String get restorePurchasesDesc => 'Re-apply your one-time unlocks';

  @override
  String get purchasesRestored => 'Purchases restored.';

  @override
  String get sectionData => 'Data';

  @override
  String get resetProgress => 'Reset Progress';

  @override
  String get resetProgressDesc => 'Erase coins, unlocks and stats';

  @override
  String get resetConfirmTitle => 'Reset progress?';

  @override
  String get resetConfirmBody =>
      'This permanently erases your coins, cosmetics and stats. This cannot be undone.';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionReset => 'Reset';

  @override
  String get progressReset => 'Progress reset.';

  @override
  String get aboutBody =>
      'Rated Everyone. Plays fully offline. No accounts, no tracking. In-app purchases are cosmetic only and never affect gameplay — no loot boxes, no pay-to-win, no dark patterns.';

  @override
  String get homeTagline => '2 • 3 • 4 PLAYER GAMES';

  @override
  String get navSettings => 'SETTINGS';

  @override
  String get quickPlay => 'QUICK PLAY';

  @override
  String get actionCup => 'CUP';

  @override
  String get actionCupHint => 'Tournament';

  @override
  String get actionShop => 'SHOP';

  @override
  String get actionShopHint => 'Skins & themes';

  @override
  String get actionDaily => 'DAILY';

  @override
  String get actionDailyHintReady => 'Reward ready';

  @override
  String get actionDailyHintDefault => 'Missions';

  @override
  String get actionStats => 'STATS';

  @override
  String get actionStatsHint => 'Your records';

  @override
  String get moreGames => 'MORE GAMES';

  @override
  String get noGamesToShow => 'No games to show right now.';

  @override
  String get fromTheStudio => 'FROM THE STUDIO';

  @override
  String get actionGet => 'GET';

  @override
  String gamesCount(int count) {
    return '$count GAMES';
  }

  @override
  String get pickAGame => 'PICK A GAME';

  @override
  String get noGamesForPlayerCount => 'No games for this player count.';

  @override
  String get game_sumo_smash => 'Sumo Smash';

  @override
  String get game_bumper_balls => 'Bumper Balls';

  @override
  String get game_one_touch_soccer => 'One-Touch Soccer';

  @override
  String get game_tank_duel => 'Tank Duel';

  @override
  String get game_archer_pop => 'Archer Pop';

  @override
  String get game_chicken_jump => 'Chicken Jump';

  @override
  String get game_falling_dodge => 'Falling Dodge';

  @override
  String get game_tap_sprint => 'Tap Sprint';

  @override
  String get game_tug_of_war => 'Tug of War';

  @override
  String get game_button_masher => 'Button Masher';

  @override
  String get game_reaction_duel => 'Reaction Duel';

  @override
  String get game_snake_arena => 'Snake Arena';

  @override
  String get game_paint_splash => 'Paint Splash';

  @override
  String get game_catch_the_star => 'Catch the Star';

  @override
  String get game_color_memory => 'Color Memory';

  @override
  String get hint_tap => 'TAP';

  @override
  String get hint_hold => 'HOLD';

  @override
  String get hint_mash => 'MASH';

  @override
  String get hint_move => 'MOVE';

  @override
  String get hint_drag => 'DRAG';

  @override
  String get howto_sumo_smash =>
      'Tap to lunge, hold to brace. Shove rivals out of the ring!';

  @override
  String get howto_bumper_balls =>
      'Drag back to aim, release to launch. Bank off pegs to knock rivals off!';

  @override
  String get howto_one_touch_soccer =>
      'Drag to run, tap to trap the ball, tap to shoot. Score the most goals!';

  @override
  String get howto_tank_duel =>
      'Drag to aim, hold to charge the arc, release to fire. Hit the enemy tank!';

  @override
  String get howto_archer_pop =>
      'Drag back to aim and power up, release to shoot. Pop the moving targets!';

  @override
  String get howto_chicken_jump =>
      'Tap to hop up, hold for a risky double-leap. Climb as high as you can!';

  @override
  String get howto_falling_dodge =>
      'Tap left or right to dodge the falling blocks. Late dodges score more!';

  @override
  String get howto_tap_sprint =>
      'Tap a steady rhythm to run, hold then release to vault hurdles. Finish first!';

  @override
  String get howto_tug_of_war =>
      'Tap on the beat to heave; full tension means a POWER HEAVE. Win the pull!';

  @override
  String get howto_button_masher =>
      'Tap to climb a rung, in the gap between the sweeping bars. Reach the top!';

  @override
  String get howto_reaction_duel =>
      'Wait, then tap the instant it turns GREEN. Don\'t fall for the fakes!';

  @override
  String get howto_snake_arena =>
      'Tap left or right to turn. Eat to grow, cut off rivals, survive longest!';

  @override
  String get howto_paint_splash =>
      'Tap fresh and rival cells in a chain to splat. Cover the most area!';

  @override
  String get howto_catch_the_star =>
      'Drag to move your basket. Catch the stars and dodge the bombs!';

  @override
  String get howto_color_memory =>
      'Watch the color order, then tap it back. Last one remembering wins!';

  @override
  String get howto_tap_to_start => 'Tap to start';

  @override
  String get cupSetupTitle => 'CUP SETUP';

  @override
  String get playersTitle => 'PLAYERS';

  @override
  String playersAddUpTo(int max) {
    return 'Add up to $max';
  }

  @override
  String get seatHuman => 'HUMAN';

  @override
  String get seatCpu => 'CPU';

  @override
  String get modeLabel => 'MODE';

  @override
  String get modeFreeForAll => 'FREE FOR ALL';

  @override
  String get modeDuel1v1 => '1 v 1';

  @override
  String get modeTeam2v2 => '2 v 2';

  @override
  String get modeTeam3v3 => '3 v 3';

  @override
  String get actionStart => 'START';

  @override
  String get startCup => 'START CUP';

  @override
  String get shopStickSkins => 'STICK SKINS';

  @override
  String get shopMapThemes => 'MAP THEMES';

  @override
  String get shopStore => 'STORE';

  @override
  String get shopStickSkinEyebrow => 'STICK SKIN';

  @override
  String get shopMapThemeEyebrow => 'MAP THEME';

  @override
  String get shopCoinPack => 'COIN PACK';

  @override
  String get shopUnlockEyebrow => 'UNLOCK';

  @override
  String get shopFreeAlwaysYours => 'Free • always yours';

  @override
  String get shopEquipped => 'Equipped';

  @override
  String get shopOwned => 'Owned';

  @override
  String shopPriceCoins(int count) {
    return '$count coins';
  }

  @override
  String get shopTopUpCoins => 'Top up your coins';

  @override
  String get shopOneTimeUnlock => 'One-time unlock';

  @override
  String get shopBuy => 'BUY';

  @override
  String get shopUse => 'USE';

  @override
  String shopUnlocked(String name) {
    return 'Unlocked $name!';
  }

  @override
  String get shopNotEnoughCoins => 'Not enough coins.';

  @override
  String shopPurchased(String title) {
    return 'Purchased $title.';
  }

  @override
  String shopPurchaseFailed(String error) {
    return 'Purchase failed: $error';
  }

  @override
  String get shopEthicsNote =>
      'Purchases are cosmetic only and never affect gameplay. Prices shown are real and set by the app store.';

  @override
  String get loginBonus => 'LOGIN BONUS';

  @override
  String get todaysMissions => 'TODAY\'S MISSIONS';

  @override
  String claimedCoins(int count) {
    return 'Claimed +$count coins!';
  }

  @override
  String get rewardClaimed => 'Reward claimed!';

  @override
  String dayN(int day) {
    return 'DAY $day';
  }

  @override
  String coinsAmount(int count) {
    return '+$count coins';
  }

  @override
  String cosmeticReward(int count) {
    return '$count cosmetic reward';
  }

  @override
  String get comeBackTomorrow => 'Come back tomorrow';

  @override
  String get tapClaimToCollect => 'Tap claim to collect';

  @override
  String get claim => 'CLAIM';

  @override
  String get claimed => 'CLAIMED';

  @override
  String missionPlayRounds(int count) {
    return 'Play $count rounds';
  }

  @override
  String missionWinRounds(int count) {
    return 'Win $count rounds';
  }

  @override
  String get missionWinCup => 'Win a cup';

  @override
  String get missionTryNewGame => 'Try a new game';

  @override
  String missionPlayWithPlayers(int count) {
    return 'Play with $count players';
  }

  @override
  String cupGameProgress(int current, int total) {
    return 'GAME $current/$total';
  }

  @override
  String cupStandingsTitle(int current, int total) {
    return 'STANDINGS • $current/$total';
  }

  @override
  String cupNextGameButton(int current, int total) {
    return 'NEXT GAME ($current/$total)';
  }

  @override
  String cupPoints(int count) {
    return '$count pts';
  }

  @override
  String get cupChampionTitle => 'CHAMPION';

  @override
  String get cupChampionBanner => 'CUP CHAMPION';

  @override
  String get cupRematch => 'REMATCH';

  @override
  String get cupHome => 'HOME';

  @override
  String get cupNextGame => 'NEXT GAME';

  @override
  String cupRoundOf(int current, int total) {
    return 'Round $current of $total';
  }

  @override
  String get resultsTitle => 'RESULTS';

  @override
  String get resultWinner => 'WINNER';

  @override
  String get resultNext => 'NEXT';

  @override
  String get resultMenu => 'MENU';

  @override
  String get resultSuperlativeSoloRun => 'SOLO RUN!';

  @override
  String get resultSuperlativeCleanSweep => 'CLEAN SWEEP!';

  @override
  String get resultSuperlativePhotoFinish => 'PHOTO FINISH!';

  @override
  String get resultSuperlativeDominant => 'DOMINANT!';

  @override
  String get resultSuperlativeFlawless => 'FLAWLESS!';

  @override
  String get statsCareer => 'CAREER';

  @override
  String get statCoins => 'Coins';

  @override
  String get statRoundsPlayed => 'Rounds played';

  @override
  String get statCupsWon => 'Cups won';

  @override
  String get statKnockouts => 'Knockouts';

  @override
  String get statsBestScores => 'BEST SCORES';

  @override
  String statsAchievements(int unlocked, int total) {
    return 'ACHIEVEMENTS  $unlocked/$total';
  }

  @override
  String get statBestScore => 'Best score';
}
