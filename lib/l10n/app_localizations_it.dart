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
}
