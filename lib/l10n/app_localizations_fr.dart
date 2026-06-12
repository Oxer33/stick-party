// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get sectionGameplay => 'Jeu';

  @override
  String get cpuDifficulty => 'Difficulté de l\'IA';

  @override
  String get difficultyEasy => 'Facile';

  @override
  String get difficultyMedium => 'Moyenne';

  @override
  String get difficultyHard => 'Difficile';

  @override
  String get screenShake => 'Tremblement de l\'écran';

  @override
  String get sectionLanguage => 'Langue';

  @override
  String get languageSystem => 'Paramètre du système';

  @override
  String get sectionPurchases => 'Achats';

  @override
  String get restorePurchases => 'Restaurer les achats';

  @override
  String get restorePurchasesDesc => 'Réappliquez vos déblocages uniques';

  @override
  String get purchasesRestored => 'Achats restaurés.';

  @override
  String get sectionData => 'Données';

  @override
  String get resetProgress => 'Réinitialiser la progression';

  @override
  String get resetProgressDesc =>
      'Effacer les pièces, déblocages et statistiques';

  @override
  String get resetConfirmTitle => 'Réinitialiser la progression ?';

  @override
  String get resetConfirmBody =>
      'Cela efface définitivement vos pièces, vos cosmétiques et vos statistiques. Cette action est irréversible.';

  @override
  String get actionCancel => 'Annuler';

  @override
  String get actionReset => 'Réinitialiser';

  @override
  String get progressReset => 'Progression réinitialisée.';

  @override
  String get aboutBody =>
      'Tout public. Fonctionne entièrement hors ligne. Aucun compte, aucun suivi. Les achats intégrés sont uniquement cosmétiques et n\'affectent jamais le jeu — pas de coffres à butin, pas de pay-to-win, pas de pièges marketing.';

  @override
  String get homeTagline => 'JEUX À 2 • 3 • 4 JOUEURS';

  @override
  String get navSettings => 'RÉGLAGES';

  @override
  String get quickPlay => 'PARTIE RAPIDE';

  @override
  String get actionCup => 'COUPE';

  @override
  String get actionCupHint => 'Tournoi';

  @override
  String get actionShop => 'BOUTIQUE';

  @override
  String get actionShopHint => 'Skins et thèmes';

  @override
  String get actionDaily => 'QUOTIDIEN';

  @override
  String get actionDailyHintReady => 'Récompense prête';

  @override
  String get actionDailyHintDefault => 'Missions';

  @override
  String get actionStats => 'STATS';

  @override
  String get actionStatsHint => 'Vos records';

  @override
  String get moreGames => 'PLUS DE JEUX';

  @override
  String gamesCount(int count) {
    return '$count JEUX';
  }

  @override
  String get pickAGame => 'CHOISIS UN JEU';

  @override
  String get noGamesForPlayerCount => 'Aucun jeu pour ce nombre de joueurs.';

  @override
  String get game_sumo_smash => 'Choc de Sumos';

  @override
  String get game_bumper_balls => 'Balles Tamponneuses';

  @override
  String get game_one_touch_soccer => 'Foot en un Toucher';

  @override
  String get game_tank_duel => 'Duel de Tanks';

  @override
  String get game_archer_pop => 'Tir à l\'Arc';

  @override
  String get game_chicken_jump => 'Saut de Poulet';

  @override
  String get game_falling_dodge => 'Esquive de Chute';

  @override
  String get game_tap_sprint => 'Sprint Tactile';

  @override
  String get game_tug_of_war => 'Tir à la Corde';

  @override
  String get game_button_masher => 'Pilonne le Bouton';

  @override
  String get game_reaction_duel => 'Duel de Réflexes';

  @override
  String get game_snake_arena => 'Arène des Serpents';

  @override
  String get game_paint_splash => 'Éclaboussure de Peinture';

  @override
  String get game_catch_the_star => 'Attrape l\'Étoile';

  @override
  String get game_color_memory => 'Mémoire des Couleurs';

  @override
  String get hint_tap => 'TAPE';

  @override
  String get hint_hold => 'MAINTIENS';

  @override
  String get hint_mash => 'PILONNE';

  @override
  String get hint_move => 'BOUGE';

  @override
  String get hint_drag => 'GLISSE';
}
