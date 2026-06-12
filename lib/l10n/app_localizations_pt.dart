// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get sectionGameplay => 'Jogabilidade';

  @override
  String get cpuDifficulty => 'Dificuldade da CPU';

  @override
  String get difficultyEasy => 'Fácil';

  @override
  String get difficultyMedium => 'Média';

  @override
  String get difficultyHard => 'Difícil';

  @override
  String get screenShake => 'Tremor de tela';

  @override
  String get sectionLanguage => 'Idioma';

  @override
  String get languageSystem => 'Padrão do sistema';

  @override
  String get sectionPurchases => 'Compras';

  @override
  String get restorePurchases => 'Restaurar compras';

  @override
  String get restorePurchasesDesc => 'Reaplique seus desbloqueios únicos';

  @override
  String get purchasesRestored => 'Compras restauradas.';

  @override
  String get sectionData => 'Dados';

  @override
  String get resetProgress => 'Redefinir progresso';

  @override
  String get resetProgressDesc => 'Apague moedas, desbloqueios e estatísticas';

  @override
  String get resetConfirmTitle => 'Redefinir o progresso?';

  @override
  String get resetConfirmBody =>
      'Isso apaga permanentemente suas moedas, cosméticos e estatísticas. Não é possível desfazer.';

  @override
  String get actionCancel => 'Cancelar';

  @override
  String get actionReset => 'Redefinir';

  @override
  String get progressReset => 'Progresso redefinido.';

  @override
  String get aboutBody =>
      'Classificação livre. Funciona totalmente offline. Sem contas, sem rastreamento. As compras no aplicativo são apenas cosméticas e nunca afetam a jogabilidade — sem caixas de recompensa, sem pagar para vencer, sem padrões obscuros.';

  @override
  String get homeTagline => 'JOGOS PARA 2 • 3 • 4 JOGADORES';

  @override
  String get navSettings => 'AJUSTES';

  @override
  String get quickPlay => 'JOGAR JÁ';

  @override
  String get actionCup => 'COPA';

  @override
  String get actionCupHint => 'Torneio';

  @override
  String get actionShop => 'LOJA';

  @override
  String get actionShopHint => 'Skins e temas';

  @override
  String get actionDaily => 'DIÁRIO';

  @override
  String get actionDailyHintReady => 'Recompensa pronta';

  @override
  String get actionDailyHintDefault => 'Missões';

  @override
  String get actionStats => 'ESTATÍSTICAS';

  @override
  String get actionStatsHint => 'Seus recordes';

  @override
  String get moreGames => 'MAIS JOGOS';

  @override
  String gamesCount(int count) {
    return '$count JOGOS';
  }

  @override
  String get pickAGame => 'ESCOLHA UM JOGO';

  @override
  String get noGamesForPlayerCount =>
      'Nenhum jogo para este número de jogadores.';

  @override
  String get game_sumo_smash => 'Choque de Sumô';

  @override
  String get game_bumper_balls => 'Bolas Malucas';

  @override
  String get game_one_touch_soccer => 'Futebol de Um Toque';

  @override
  String get game_tank_duel => 'Duelo de Tanques';

  @override
  String get game_archer_pop => 'Arqueiro Certeiro';

  @override
  String get game_chicken_jump => 'Pulo da Galinha';

  @override
  String get game_falling_dodge => 'Desvie da Queda';

  @override
  String get game_tap_sprint => 'Corrida de Toques';

  @override
  String get game_tug_of_war => 'Cabo de Guerra';

  @override
  String get game_button_masher => 'Esmaga Botões';

  @override
  String get game_reaction_duel => 'Duelo de Reflexos';

  @override
  String get game_snake_arena => 'Arena das Cobras';

  @override
  String get game_paint_splash => 'Respingo de Tinta';

  @override
  String get game_catch_the_star => 'Pegue a Estrela';

  @override
  String get game_color_memory => 'Memória de Cores';

  @override
  String get hint_tap => 'TOQUE';

  @override
  String get hint_hold => 'SEGURE';

  @override
  String get hint_mash => 'ESMAGUE';

  @override
  String get hint_move => 'MOVA';

  @override
  String get hint_drag => 'ARRASTE';
}
