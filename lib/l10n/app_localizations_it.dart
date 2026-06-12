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
}
