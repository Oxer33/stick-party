// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get sectionGameplay => 'Gioco';

  @override
  String get cpuDifficulty => 'Difficoltà della CPU';

  @override
  String get difficultyEasy => 'Facile';

  @override
  String get difficultyMedium => 'Media';

  @override
  String get difficultyHard => 'Difficile';

  @override
  String get screenShake => 'Vibrazione schermo';

  @override
  String get sectionLanguage => 'Lingua';

  @override
  String get languageSystem => 'Predefinita di sistema';

  @override
  String get sectionPurchases => 'Acquisti';

  @override
  String get restorePurchases => 'Ripristina acquisti';

  @override
  String get restorePurchasesDesc => 'Riapplica i tuoi sblocchi una tantum';

  @override
  String get purchasesRestored => 'Acquisti ripristinati.';

  @override
  String get sectionData => 'Dati';

  @override
  String get resetProgress => 'Azzera progressi';

  @override
  String get resetProgressDesc => 'Cancella monete, sblocchi e statistiche';

  @override
  String get resetConfirmTitle => 'Azzerare i progressi?';

  @override
  String get resetConfirmBody =>
      'Questa operazione cancella in modo permanente le tue monete, gli oggetti estetici e le statistiche. Non può essere annullata.';

  @override
  String get actionCancel => 'Annulla';

  @override
  String get actionReset => 'Azzera';

  @override
  String get progressReset => 'Progressi azzerati.';

  @override
  String get aboutBody =>
      'Adatto a tutti. Funziona completamente offline. Nessun account, nessun tracciamento. Gli acquisti in-app sono solo estetici e non influiscono mai sul gioco — niente loot box, niente pay-to-win, niente meccaniche ingannevoli.';

  @override
  String get homeTagline => 'GIOCHI PER 2 • 3 • 4 GIOCATORI';

  @override
  String get navSettings => 'IMPOSTAZIONI';

  @override
  String get quickPlay => 'GIOCA SUBITO';

  @override
  String get actionCup => 'COPPA';

  @override
  String get actionCupHint => 'Torneo';

  @override
  String get actionShop => 'NEGOZIO';

  @override
  String get actionShopHint => 'Skin e temi';

  @override
  String get actionDaily => 'GIORNALIERO';

  @override
  String get actionDailyHintReady => 'Premio pronto';

  @override
  String get actionDailyHintDefault => 'Missioni';

  @override
  String get actionStats => 'STATISTICHE';

  @override
  String get actionStatsHint => 'I tuoi record';

  @override
  String get moreGames => 'ALTRI GIOCHI';

  @override
  String get noGamesToShow => 'Nessun gioco da mostrare al momento.';

  @override
  String get fromTheStudio => 'DALLO STUDIO';

  @override
  String get actionGet => 'SCARICA';

  @override
  String gamesCount(int count) {
    return '$count GIOCHI';
  }

  @override
  String get pickAGame => 'SCEGLI UN GIOCO';

  @override
  String get noGamesForPlayerCount =>
      'Nessun gioco per questo numero di giocatori.';

  @override
  String get game_sumo_smash => 'Scontro di Sumo';

  @override
  String get game_bumper_balls => 'Palle Impazzite';

  @override
  String get game_one_touch_soccer => 'Calcio al Volo';

  @override
  String get game_tank_duel => 'Duello tra Carri';

  @override
  String get game_archer_pop => 'Arciere Provetto';

  @override
  String get game_chicken_jump => 'Salto del Pollo';

  @override
  String get game_falling_dodge => 'Schiva la Caduta';

  @override
  String get game_tap_sprint => 'Sprint a Tocchi';

  @override
  String get game_tug_of_war => 'Tiro alla Fune';

  @override
  String get game_button_masher => 'Pesta il Tasto';

  @override
  String get game_reaction_duel => 'Duello di Riflessi';

  @override
  String get game_snake_arena => 'Arena dei Serpenti';

  @override
  String get game_paint_splash => 'Schizzo di Vernice';

  @override
  String get game_catch_the_star => 'Prendi la Stella';

  @override
  String get game_color_memory => 'Memoria dei Colori';

  @override
  String get hint_tap => 'TOCCA';

  @override
  String get hint_hold => 'TIENI';

  @override
  String get hint_mash => 'PESTA';

  @override
  String get hint_move => 'MUOVI';

  @override
  String get hint_drag => 'TRASCINA';

  @override
  String get cupSetupTitle => 'CONFIG. COPPA';

  @override
  String get playersTitle => 'GIOCATORI';

  @override
  String playersAddUpTo(int max) {
    return 'Aggiungi fino a $max';
  }

  @override
  String get seatHuman => 'UMANO';

  @override
  String get seatCpu => 'CPU';

  @override
  String get modeLabel => 'MODALITÀ';

  @override
  String get modeFreeForAll => 'TUTTI CONTRO TUTTI';

  @override
  String get modeDuel1v1 => '1 vs 1';

  @override
  String get modeTeam2v2 => '2 vs 2';

  @override
  String get modeTeam3v3 => '3 vs 3';

  @override
  String get actionStart => 'INIZIA';

  @override
  String get startCup => 'INIZIA COPPA';

  @override
  String get shopStickSkins => 'ASPETTI';

  @override
  String get shopMapThemes => 'TEMI MAPPA';

  @override
  String get shopStore => 'STORE';

  @override
  String get shopStickSkinEyebrow => 'ASPETTO';

  @override
  String get shopMapThemeEyebrow => 'TEMA MAPPA';

  @override
  String get shopCoinPack => 'PACCHETTO MONETE';

  @override
  String get shopUnlockEyebrow => 'SBLOCCO';

  @override
  String get shopFreeAlwaysYours => 'Gratis • sempre tuo';

  @override
  String get shopEquipped => 'Equipaggiato';

  @override
  String get shopOwned => 'Posseduto';

  @override
  String shopPriceCoins(int count) {
    return '$count monete';
  }

  @override
  String get shopTopUpCoins => 'Ricarica le tue monete';

  @override
  String get shopOneTimeUnlock => 'Sblocco una tantum';

  @override
  String get shopBuy => 'ACQUISTA';

  @override
  String get shopUse => 'USA';

  @override
  String shopUnlocked(String name) {
    return '$name sbloccato!';
  }

  @override
  String get shopNotEnoughCoins => 'Monete insufficienti.';

  @override
  String shopPurchased(String title) {
    return '$title acquistato.';
  }

  @override
  String shopPurchaseFailed(String error) {
    return 'Acquisto non riuscito: $error';
  }

  @override
  String get shopEthicsNote =>
      'Gli acquisti sono solo estetici e non influenzano mai il gioco. I prezzi mostrati sono reali e stabiliti dallo store delle app.';

  @override
  String get loginBonus => 'BONUS GIORNALIERO';

  @override
  String get todaysMissions => 'MISSIONI DI OGGI';

  @override
  String claimedCoins(int count) {
    return '+$count monete riscosse!';
  }

  @override
  String get rewardClaimed => 'Ricompensa riscossa!';

  @override
  String dayN(int day) {
    return 'GIORNO $day';
  }

  @override
  String coinsAmount(int count) {
    return '+$count monete';
  }

  @override
  String cosmeticReward(int count) {
    return '$count ricompensa estetica';
  }

  @override
  String get comeBackTomorrow => 'Torna domani';

  @override
  String get tapClaimToCollect => 'Tocca riscuoti per ottenerla';

  @override
  String get claim => 'RISCUOTI';

  @override
  String get claimed => 'RISCOSSO';

  @override
  String missionPlayRounds(int count) {
    return 'Gioca $count round';
  }

  @override
  String missionWinRounds(int count) {
    return 'Vinci $count round';
  }

  @override
  String get missionWinCup => 'Vinci una coppa';

  @override
  String get missionTryNewGame => 'Prova un nuovo gioco';

  @override
  String missionPlayWithPlayers(int count) {
    return 'Gioca con $count giocatori';
  }

  @override
  String cupGameProgress(int current, int total) {
    return 'GIOCO $current/$total';
  }

  @override
  String cupStandingsTitle(int current, int total) {
    return 'CLASSIFICA • $current/$total';
  }

  @override
  String cupNextGameButton(int current, int total) {
    return 'GIOCO SUCCESSIVO ($current/$total)';
  }

  @override
  String cupPoints(int count) {
    return '$count pti';
  }

  @override
  String get cupChampionTitle => 'CAMPIONE';

  @override
  String get cupChampionBanner => 'CAMPIONE DELLA COPPA';

  @override
  String get cupRematch => 'RIVINCITA';

  @override
  String get cupHome => 'HOME';

  @override
  String get cupNextGame => 'GIOCO SUCCESSIVO';

  @override
  String cupRoundOf(int current, int total) {
    return 'Round $current di $total';
  }

  @override
  String get resultsTitle => 'RISULTATI';

  @override
  String get resultWinner => 'VINCITORE';

  @override
  String get resultNext => 'AVANTI';

  @override
  String get resultMenu => 'MENU';

  @override
  String get resultSuperlativeSoloRun => 'ASSOLO!';

  @override
  String get resultSuperlativeCleanSweep => 'EN BIANCO!';

  @override
  String get resultSuperlativePhotoFinish => 'AL FOTOFINISH!';

  @override
  String get resultSuperlativeDominant => 'DOMINIO!';

  @override
  String get resultSuperlativeFlawless => 'IMPECCABILE!';

  @override
  String get statsCareer => 'CARRIERA';

  @override
  String get statCoins => 'Monete';

  @override
  String get statRoundsPlayed => 'Round giocati';

  @override
  String get statCupsWon => 'Coppe vinte';

  @override
  String get statKnockouts => 'Eliminazioni';

  @override
  String get statsBestScores => 'PUNTEGGI MIGLIORI';

  @override
  String statsAchievements(int unlocked, int total) {
    return 'OBIETTIVI  $unlocked/$total';
  }

  @override
  String get statBestScore => 'Punteggio migliore';
}
