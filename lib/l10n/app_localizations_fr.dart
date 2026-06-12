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
}
