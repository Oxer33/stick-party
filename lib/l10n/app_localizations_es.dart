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

  @override
  String get homeTagline => 'JUEGOS PARA 2 • 3 • 4 JUGADORES';

  @override
  String get navSettings => 'AJUSTES';

  @override
  String get quickPlay => 'JUGAR YA';

  @override
  String get actionCup => 'COPA';

  @override
  String get actionCupHint => 'Torneo';

  @override
  String get actionShop => 'TIENDA';

  @override
  String get actionShopHint => 'Aspectos y temas';

  @override
  String get actionDaily => 'DIARIO';

  @override
  String get actionDailyHintReady => 'Recompensa lista';

  @override
  String get actionDailyHintDefault => 'Misiones';

  @override
  String get actionStats => 'ESTADÍSTICAS';

  @override
  String get actionStatsHint => 'Tus récords';

  @override
  String get moreGames => 'MÁS JUEGOS';

  @override
  String gamesCount(int count) {
    return '$count JUEGOS';
  }

  @override
  String get pickAGame => 'ELIGE UN JUEGO';

  @override
  String get noGamesForPlayerCount =>
      'No hay juegos para este número de jugadores.';

  @override
  String get game_sumo_smash => 'Choque de Sumos';

  @override
  String get game_bumper_balls => 'Bolas Locas';

  @override
  String get game_one_touch_soccer => 'Fútbol de un Toque';

  @override
  String get game_tank_duel => 'Duelo de Tanques';

  @override
  String get game_archer_pop => 'Arquero Certero';

  @override
  String get game_chicken_jump => 'Salto de Pollo';

  @override
  String get game_falling_dodge => 'Esquiva Caídas';

  @override
  String get game_tap_sprint => 'Carrera a Toques';

  @override
  String get game_tug_of_war => 'Tira y Afloja';

  @override
  String get game_button_masher => 'Aporrea Botones';

  @override
  String get game_reaction_duel => 'Duelo de Reflejos';

  @override
  String get game_snake_arena => 'Arena de Serpientes';

  @override
  String get game_paint_splash => 'Salpicón de Pintura';

  @override
  String get game_catch_the_star => 'Atrapa la Estrella';

  @override
  String get game_color_memory => 'Memoria de Colores';

  @override
  String get hint_tap => 'TOCA';

  @override
  String get hint_hold => 'MANTÉN';

  @override
  String get hint_mash => 'APORREA';

  @override
  String get hint_move => 'MUEVE';

  @override
  String get hint_drag => 'ARRASTRA';
}
