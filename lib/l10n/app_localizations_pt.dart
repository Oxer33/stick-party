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
  String get noGamesToShow => 'Nenhum jogo para mostrar agora.';

  @override
  String get fromTheStudio => 'DO ESTÚDIO';

  @override
  String get actionGet => 'OBTER';

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

  @override
  String get howto_sumo_smash =>
      'Toque para investir, segure para se firmar. Empurre os rivais para fora do ringue!';

  @override
  String get howto_bumper_balls =>
      'Arraste para trás para mirar e solte para lançar. Ricocheteie nos pinos e derrube os rivais!';

  @override
  String get howto_one_touch_soccer =>
      'Arraste para correr, toque para dominar a bola e toque para chutar. Marque mais gols que todos!';

  @override
  String get howto_tank_duel =>
      'Arraste para mirar, segure para carregar o arco e solte para atirar. Acerte o tanque inimigo!';

  @override
  String get howto_archer_pop =>
      'Arraste para trás para mirar e carregar, solte para atirar. Estoure os alvos em movimento!';

  @override
  String get howto_chicken_jump =>
      'Toque para pular, segure para um pulo duplo arriscado. Suba o mais alto que conseguir!';

  @override
  String get howto_falling_dodge =>
      'Toque à esquerda ou à direita para desviar dos blocos que caem. Desviar no limite vale mais pontos!';

  @override
  String get howto_tap_sprint =>
      'Toque num ritmo constante para correr, segure e solte para saltar os obstáculos. Termine em primeiro!';

  @override
  String get howto_tug_of_war =>
      'Toque no ritmo para puxar; com tensão máxima vem o PUXÃO PODEROSO. Vença o cabo de guerra!';

  @override
  String get howto_button_masher =>
      'Toque para subir um degrau, no vão entre as barras que giram. Chegue ao topo!';

  @override
  String get howto_reaction_duel =>
      'Espere e toque no instante em que ficar VERDE. Não caia nas fintas!';

  @override
  String get howto_snake_arena =>
      'Toque à esquerda ou à direita para virar. Coma para crescer, corte os rivais e sobreviva por mais tempo!';

  @override
  String get howto_paint_splash =>
      'Toque em sequência nas células livres e nas dos rivais para respingar. Cubra a maior área!';

  @override
  String get howto_catch_the_star =>
      'Arraste para mover sua cesta. Pegue as estrelas e desvie das bombas!';

  @override
  String get howto_color_memory =>
      'Observe a ordem das cores e depois toque de volta. Quem lembrar até o fim vence!';

  @override
  String get howto_tap_to_start => 'Toque para começar';

  @override
  String get cupSetupTitle => 'CONFIG. DA COPA';

  @override
  String get playersTitle => 'JOGADORES';

  @override
  String playersAddUpTo(int max) {
    return 'Adicione até $max';
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
  String get actionStart => 'COMEÇAR';

  @override
  String get startCup => 'COMEÇAR COPA';

  @override
  String get shopStickSkins => 'VISUAIS';

  @override
  String get shopMapThemes => 'TEMAS DE MAPA';

  @override
  String get shopStore => 'LOJA';

  @override
  String get shopStickSkinEyebrow => 'VISUAL';

  @override
  String get shopMapThemeEyebrow => 'TEMA DE MAPA';

  @override
  String get shopCoinPack => 'PACOTE DE MOEDAS';

  @override
  String get shopUnlockEyebrow => 'DESBLOQUEIO';

  @override
  String get shopFreeAlwaysYours => 'Grátis • sempre seu';

  @override
  String get shopEquipped => 'Equipado';

  @override
  String get shopOwned => 'Adquirido';

  @override
  String shopPriceCoins(int count) {
    return '$count moedas';
  }

  @override
  String get shopTopUpCoins => 'Recarregue suas moedas';

  @override
  String get shopOneTimeUnlock => 'Desbloqueio único';

  @override
  String get shopBuy => 'COMPRAR';

  @override
  String get shopUse => 'USAR';

  @override
  String shopUnlocked(String name) {
    return '$name desbloqueado!';
  }

  @override
  String get shopNotEnoughCoins => 'Moedas insuficientes.';

  @override
  String shopPurchased(String title) {
    return '$title comprado.';
  }

  @override
  String shopPurchaseFailed(String error) {
    return 'Falha na compra: $error';
  }

  @override
  String get shopEthicsNote =>
      'As compras são apenas cosméticas e nunca afetam a jogabilidade. Os preços exibidos são reais e definidos pela loja de aplicativos.';

  @override
  String get loginBonus => 'BÔNUS DIÁRIO';

  @override
  String get todaysMissions => 'MISSÕES DE HOJE';

  @override
  String claimedCoins(int count) {
    return '+$count moedas resgatadas!';
  }

  @override
  String get rewardClaimed => 'Recompensa resgatada!';

  @override
  String dayN(int day) {
    return 'DIA $day';
  }

  @override
  String coinsAmount(int count) {
    return '+$count moedas';
  }

  @override
  String cosmeticReward(int count) {
    return '$count recompensa cosmética';
  }

  @override
  String get comeBackTomorrow => 'Volte amanhã';

  @override
  String get tapClaimToCollect => 'Toque em resgatar para coletar';

  @override
  String get claim => 'RESGATAR';

  @override
  String get claimed => 'RESGATADO';

  @override
  String missionPlayRounds(int count) {
    return 'Jogue $count rodadas';
  }

  @override
  String missionWinRounds(int count) {
    return 'Vença $count rodadas';
  }

  @override
  String get missionWinCup => 'Vença uma copa';

  @override
  String get missionTryNewGame => 'Experimente um jogo novo';

  @override
  String missionPlayWithPlayers(int count) {
    return 'Jogue com $count jogadores';
  }

  @override
  String cupGameProgress(int current, int total) {
    return 'JOGO $current/$total';
  }

  @override
  String cupStandingsTitle(int current, int total) {
    return 'CLASSIFICAÇÃO • $current/$total';
  }

  @override
  String cupNextGameButton(int current, int total) {
    return 'PRÓXIMO JOGO ($current/$total)';
  }

  @override
  String cupPoints(int count) {
    return '$count pts';
  }

  @override
  String get cupChampionTitle => 'CAMPEÃO';

  @override
  String get cupChampionBanner => 'CAMPEÃO DA COPA';

  @override
  String get cupRematch => 'REVANCHE';

  @override
  String get cupHome => 'INÍCIO';

  @override
  String get cupNextGame => 'PRÓXIMO JOGO';

  @override
  String cupRoundOf(int current, int total) {
    return 'Rodada $current de $total';
  }

  @override
  String get resultsTitle => 'RESULTADOS';

  @override
  String get resultWinner => 'VENCEDOR';

  @override
  String get resultNext => 'PRÓXIMO';

  @override
  String get resultMenu => 'MENU';

  @override
  String get resultSuperlativeSoloRun => 'CORRIDA SOLO!';

  @override
  String get resultSuperlativeCleanSweep => 'VARRIDA TOTAL!';

  @override
  String get resultSuperlativePhotoFinish => 'FOTO FINISH!';

  @override
  String get resultSuperlativeDominant => 'DOMINANTE!';

  @override
  String get resultSuperlativeFlawless => 'IMPECÁVEL!';

  @override
  String get statsCareer => 'CARREIRA';

  @override
  String get statCoins => 'Moedas';

  @override
  String get statRoundsPlayed => 'Rodadas jogadas';

  @override
  String get statCupsWon => 'Copas vencidas';

  @override
  String get statKnockouts => 'Nocautes';

  @override
  String get statsBestScores => 'MELHORES PONTUAÇÕES';

  @override
  String statsAchievements(int unlocked, int total) {
    return 'CONQUISTAS  $unlocked/$total';
  }

  @override
  String get statBestScore => 'Melhor pontuação';
}
