// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get sectionGameplay => 'Juego';

  @override
  String get cpuDifficulty => 'Dificultad de la CPU';

  @override
  String get difficultyEasy => 'Fácil';

  @override
  String get difficultyMedium => 'Media';

  @override
  String get difficultyHard => 'Difícil';

  @override
  String get screenShake => 'Vibración de pantalla';

  @override
  String get sectionLanguage => 'Idioma';

  @override
  String get languageSystem => 'Predeterminado del sistema';

  @override
  String get sectionPurchases => 'Compras';

  @override
  String get restorePurchases => 'Restaurar compras';

  @override
  String get restorePurchasesDesc => 'Vuelve a aplicar tus desbloqueos únicos';

  @override
  String get purchasesRestored => 'Compras restauradas.';

  @override
  String get sectionData => 'Datos';

  @override
  String get resetProgress => 'Restablecer progreso';

  @override
  String get resetProgressDesc => 'Borra monedas, desbloqueos y estadísticas';

  @override
  String get resetConfirmTitle => '¿Restablecer el progreso?';

  @override
  String get resetConfirmBody =>
      'Esto borra de forma permanente tus monedas, cosméticos y estadísticas. No se puede deshacer.';

  @override
  String get actionCancel => 'Cancelar';

  @override
  String get actionReset => 'Restablecer';

  @override
  String get progressReset => 'Progreso restablecido.';

  @override
  String get aboutBody =>
      'Para todos los públicos. Funciona totalmente sin conexión. Sin cuentas ni seguimiento. Las compras dentro de la aplicación son solo cosméticas y nunca afectan al juego: sin cajas de botín, sin pagar para ganar, sin patrones engañosos.';
}
