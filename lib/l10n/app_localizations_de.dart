// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get sectionGameplay => 'Gameplay';

  @override
  String get cpuDifficulty => 'CPU-Schwierigkeit';

  @override
  String get difficultyEasy => 'Einfach';

  @override
  String get difficultyMedium => 'Mittel';

  @override
  String get difficultyHard => 'Schwer';

  @override
  String get screenShake => 'Bildschirmwackeln';

  @override
  String get sectionLanguage => 'Sprache';

  @override
  String get languageSystem => 'Systemstandard';

  @override
  String get sectionPurchases => 'Käufe';

  @override
  String get restorePurchases => 'Käufe wiederherstellen';

  @override
  String get restorePurchasesDesc =>
      'Deine einmaligen Freischaltungen erneut anwenden';

  @override
  String get purchasesRestored => 'Käufe wiederhergestellt.';

  @override
  String get sectionData => 'Daten';

  @override
  String get resetProgress => 'Fortschritt zurücksetzen';

  @override
  String get resetProgressDesc =>
      'Münzen, Freischaltungen und Statistiken löschen';

  @override
  String get resetConfirmTitle => 'Fortschritt zurücksetzen?';

  @override
  String get resetConfirmBody =>
      'Dies löscht deine Münzen, kosmetischen Gegenstände und Statistiken dauerhaft. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get actionCancel => 'Abbrechen';

  @override
  String get actionReset => 'Zurücksetzen';

  @override
  String get progressReset => 'Fortschritt zurückgesetzt.';

  @override
  String get aboutBody =>
      'Freigegeben ohne Altersbeschränkung. Läuft vollständig offline. Keine Konten, kein Tracking. In-App-Käufe sind rein kosmetisch und beeinflussen niemals das Gameplay — keine Beutekisten, kein Pay-to-Win, keine manipulativen Tricks.';
}
