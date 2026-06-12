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

  @override
  String get cupSetupTitle => 'CONFIG. DE COPA';

  @override
  String get playersTitle => 'JUGADORES';

  @override
  String playersAddUpTo(int max) {
    return 'Añade hasta $max';
  }

  @override
  String get seatHuman => 'HUMANO';

  @override
  String get seatCpu => 'CPU';

  @override
  String get modeLabel => 'MODO';

  @override
  String get modeFreeForAll => 'TODOS CONTRA TODOS';

  @override
  String get modeDuel1v1 => '1 vs 1';

  @override
  String get modeTeam2v2 => '2 vs 2';

  @override
  String get modeTeam3v3 => '3 vs 3';

  @override
  String get actionStart => 'EMPEZAR';

  @override
  String get startCup => 'EMPEZAR COPA';

  @override
  String get shopStickSkins => 'ASPECTOS';

  @override
  String get shopMapThemes => 'TEMAS DE MAPA';

  @override
  String get shopStore => 'TIENDA';

  @override
  String get shopStickSkinEyebrow => 'ASPECTO';

  @override
  String get shopMapThemeEyebrow => 'TEMA DE MAPA';

  @override
  String get shopCoinPack => 'PACK DE MONEDAS';

  @override
  String get shopUnlockEyebrow => 'DESBLOQUEO';

  @override
  String get shopFreeAlwaysYours => 'Gratis • siempre tuyo';

  @override
  String get shopEquipped => 'Equipado';

  @override
  String get shopOwned => 'En posesión';

  @override
  String shopPriceCoins(int count) {
    return '$count monedas';
  }

  @override
  String get shopTopUpCoins => 'Recarga tus monedas';

  @override
  String get shopOneTimeUnlock => 'Desbloqueo único';

  @override
  String get shopBuy => 'COMPRAR';

  @override
  String get shopUse => 'USAR';

  @override
  String shopUnlocked(String name) {
    return '¡$name desbloqueado!';
  }

  @override
  String get shopNotEnoughCoins => 'No tienes monedas suficientes.';

  @override
  String shopPurchased(String title) {
    return '$title comprado.';
  }

  @override
  String shopPurchaseFailed(String error) {
    return 'Compra fallida: $error';
  }

  @override
  String get shopEthicsNote =>
      'Las compras son solo cosméticas y nunca afectan al juego. Los precios mostrados son reales y los fija la tienda de aplicaciones.';

  @override
  String get loginBonus => 'BONO DIARIO';

  @override
  String get todaysMissions => 'MISIONES DE HOY';

  @override
  String claimedCoins(int count) {
    return '¡Reclamaste +$count monedas!';
  }

  @override
  String get rewardClaimed => '¡Recompensa reclamada!';

  @override
  String dayN(int day) {
    return 'DÍA $day';
  }

  @override
  String coinsAmount(int count) {
    return '+$count monedas';
  }

  @override
  String cosmeticReward(int count) {
    return '$count recompensa cosmética';
  }

  @override
  String get comeBackTomorrow => 'Vuelve mañana';

  @override
  String get tapClaimToCollect => 'Toca reclamar para recoger';

  @override
  String get claim => 'RECLAMAR';

  @override
  String get claimed => 'RECLAMADO';

  @override
  String missionPlayRounds(int count) {
    return 'Juega $count rondas';
  }

  @override
  String missionWinRounds(int count) {
    return 'Gana $count rondas';
  }

  @override
  String get missionWinCup => 'Gana una copa';

  @override
  String get missionTryNewGame => 'Prueba un juego nuevo';

  @override
  String missionPlayWithPlayers(int count) {
    return 'Juega con $count jugadores';
  }

  @override
  String cupGameProgress(int current, int total) {
    return 'JUEGO $current/$total';
  }

  @override
  String cupStandingsTitle(int current, int total) {
    return 'CLASIFICACIÓN • $current/$total';
  }

  @override
  String cupNextGameButton(int current, int total) {
    return 'SIGUIENTE JUEGO ($current/$total)';
  }

  @override
  String cupPoints(int count) {
    return '$count pts';
  }

  @override
  String get cupChampionTitle => 'CAMPEÓN';

  @override
  String get cupChampionBanner => 'CAMPEÓN DE LA COPA';

  @override
  String get cupRematch => 'REVANCHA';

  @override
  String get cupHome => 'INICIO';

  @override
  String get cupNextGame => 'SIGUIENTE JUEGO';

  @override
  String cupRoundOf(int current, int total) {
    return 'Ronda $current de $total';
  }

  @override
  String get statsCareer => 'CARRERA';

  @override
  String get statCoins => 'Monedas';

  @override
  String get statRoundsPlayed => 'Rondas jugadas';

  @override
  String get statCupsWon => 'Copas ganadas';

  @override
  String get statKnockouts => 'Eliminaciones';

  @override
  String get statsBestScores => 'MEJORES PUNTUACIONES';

  @override
  String statsAchievements(int unlocked, int total) {
    return 'LOGROS  $unlocked/$total';
  }

  @override
  String get statBestScore => 'Mejor puntuación';
}
