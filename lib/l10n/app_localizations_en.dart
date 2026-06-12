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
}
