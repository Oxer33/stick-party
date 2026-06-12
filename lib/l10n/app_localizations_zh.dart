// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get settingsTitle => '设置';

  @override
  String get sectionGameplay => '玩法';

  @override
  String get cpuDifficulty => '电脑难度';

  @override
  String get difficultyEasy => '简单';

  @override
  String get difficultyMedium => '中等';

  @override
  String get difficultyHard => '困难';

  @override
  String get screenShake => '屏幕震动';

  @override
  String get sectionLanguage => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get sectionPurchases => '购买';

  @override
  String get restorePurchases => '恢复购买';

  @override
  String get restorePurchasesDesc => '重新应用你的一次性解锁';

  @override
  String get purchasesRestored => '已恢复购买。';

  @override
  String get sectionData => '数据';

  @override
  String get resetProgress => '重置进度';

  @override
  String get resetProgressDesc => '清除金币、解锁内容和统计数据';

  @override
  String get resetConfirmTitle => '要重置进度吗？';

  @override
  String get resetConfirmBody => '这将永久清除你的金币、装饰物和统计数据。此操作无法撤销。';

  @override
  String get actionCancel => '取消';

  @override
  String get actionReset => '重置';

  @override
  String get progressReset => '进度已重置。';

  @override
  String get aboutBody =>
      '适合所有人。完全离线运行。无需账户，不做追踪。应用内购买仅为装饰，绝不影响玩法——没有抽奖宝箱，没有付费取胜，没有诱导设计。';

  @override
  String get homeTagline => '2 • 3 • 4 人游戏';

  @override
  String get navSettings => '设置';

  @override
  String get quickPlay => '快速开始';

  @override
  String get actionCup => '杯赛';

  @override
  String get actionCupHint => '锦标赛';

  @override
  String get actionShop => '商店';

  @override
  String get actionShopHint => '皮肤与主题';

  @override
  String get actionDaily => '每日';

  @override
  String get actionDailyHintReady => '奖励可领取';

  @override
  String get actionDailyHintDefault => '任务';

  @override
  String get actionStats => '统计';

  @override
  String get actionStatsHint => '你的纪录';

  @override
  String get moreGames => '更多游戏';

  @override
  String get noGamesToShow => '暂时没有可显示的游戏。';

  @override
  String get fromTheStudio => '工作室出品';

  @override
  String get actionGet => '获取';

  @override
  String gamesCount(int count) {
    return '$count 个游戏';
  }

  @override
  String get pickAGame => '选择游戏';

  @override
  String get noGamesForPlayerCount => '没有适合此人数的游戏。';

  @override
  String get game_sumo_smash => '相扑对决';

  @override
  String get game_bumper_balls => '碰碰球';

  @override
  String get game_one_touch_soccer => '一触足球';

  @override
  String get game_tank_duel => '坦克对战';

  @override
  String get game_archer_pop => '神射手';

  @override
  String get game_chicken_jump => '小鸡跳跳';

  @override
  String get game_falling_dodge => '落物闪避';

  @override
  String get game_tap_sprint => '点击冲刺';

  @override
  String get game_tug_of_war => '拔河';

  @override
  String get game_button_masher => '狂按按钮';

  @override
  String get game_reaction_duel => '反应对决';

  @override
  String get game_snake_arena => '贪吃蛇竞技场';

  @override
  String get game_paint_splash => '泼漆大战';

  @override
  String get game_catch_the_star => '接住星星';

  @override
  String get game_color_memory => '颜色记忆';

  @override
  String get hint_tap => '点击';

  @override
  String get hint_hold => '长按';

  @override
  String get hint_mash => '狂按';

  @override
  String get hint_move => '移动';

  @override
  String get hint_drag => '拖动';

  @override
  String get cupSetupTitle => '锦标赛设置';

  @override
  String get playersTitle => '玩家';

  @override
  String playersAddUpTo(int max) {
    return '最多添加 $max 名';
  }

  @override
  String get seatHuman => '真人';

  @override
  String get seatCpu => '电脑';

  @override
  String get modeLabel => '模式';

  @override
  String get modeFreeForAll => '自由混战';

  @override
  String get modeDuel1v1 => '1 对 1';

  @override
  String get modeTeam2v2 => '2 对 2';

  @override
  String get modeTeam3v3 => '3 对 3';

  @override
  String get actionStart => '开始';

  @override
  String get startCup => '开始锦标赛';

  @override
  String get shopStickSkins => '角色皮肤';

  @override
  String get shopMapThemes => '地图主题';

  @override
  String get shopStore => '商城';

  @override
  String get shopStickSkinEyebrow => '角色皮肤';

  @override
  String get shopMapThemeEyebrow => '地图主题';

  @override
  String get shopCoinPack => '金币包';

  @override
  String get shopUnlockEyebrow => '解锁';

  @override
  String get shopFreeAlwaysYours => '免费 • 永久拥有';

  @override
  String get shopEquipped => '已装备';

  @override
  String get shopOwned => '已拥有';

  @override
  String shopPriceCoins(int count) {
    return '$count 金币';
  }

  @override
  String get shopTopUpCoins => '补充金币';

  @override
  String get shopOneTimeUnlock => '一次性解锁';

  @override
  String get shopBuy => '购买';

  @override
  String get shopUse => '使用';

  @override
  String shopUnlocked(String name) {
    return '已解锁$name！';
  }

  @override
  String get shopNotEnoughCoins => '金币不足。';

  @override
  String shopPurchased(String title) {
    return '已购买$title。';
  }

  @override
  String shopPurchaseFailed(String error) {
    return '购买失败：$error';
  }

  @override
  String get shopEthicsNote => '所有购买仅为外观，绝不影响游戏玩法。所示价格真实有效，由应用商店设定。';

  @override
  String get loginBonus => '登录奖励';

  @override
  String get todaysMissions => '今日任务';

  @override
  String claimedCoins(int count) {
    return '已领取 +$count 金币！';
  }

  @override
  String get rewardClaimed => '已领取奖励！';

  @override
  String dayN(int day) {
    return '第 $day 天';
  }

  @override
  String coinsAmount(int count) {
    return '+$count 金币';
  }

  @override
  String cosmeticReward(int count) {
    return '$count 个外观奖励';
  }

  @override
  String get comeBackTomorrow => '明天再来';

  @override
  String get tapClaimToCollect => '点击领取以获得';

  @override
  String get claim => '领取';

  @override
  String get claimed => '已领取';

  @override
  String missionPlayRounds(int count) {
    return '进行 $count 局';
  }

  @override
  String missionWinRounds(int count) {
    return '赢得 $count 局';
  }

  @override
  String get missionWinCup => '赢得一座杯赛';

  @override
  String get missionTryNewGame => '尝试新游戏';

  @override
  String missionPlayWithPlayers(int count) {
    return '与 $count 名玩家同玩';
  }

  @override
  String cupGameProgress(int current, int total) {
    return '第 $current/$total 局';
  }

  @override
  String cupStandingsTitle(int current, int total) {
    return '排名 • $current/$total';
  }

  @override
  String cupNextGameButton(int current, int total) {
    return '下一局（$current/$total）';
  }

  @override
  String cupPoints(int count) {
    return '$count 分';
  }

  @override
  String get cupChampionTitle => '冠军';

  @override
  String get cupChampionBanner => '杯赛冠军';

  @override
  String get cupRematch => '再战';

  @override
  String get cupHome => '主页';

  @override
  String get cupNextGame => '下一局';

  @override
  String cupRoundOf(int current, int total) {
    return '第 $current/$total 轮';
  }

  @override
  String get resultsTitle => '结果';

  @override
  String get resultWinner => '获胜者';

  @override
  String get resultNext => '下一个';

  @override
  String get resultMenu => '菜单';

  @override
  String get resultSuperlativeSoloRun => '单人通关！';

  @override
  String get resultSuperlativeCleanSweep => '完胜！';

  @override
  String get resultSuperlativePhotoFinish => '险胜！';

  @override
  String get resultSuperlativeDominant => '碾压！';

  @override
  String get resultSuperlativeFlawless => '完美！';

  @override
  String get statsCareer => '生涯';

  @override
  String get statCoins => '金币';

  @override
  String get statRoundsPlayed => '已玩局数';

  @override
  String get statCupsWon => '夺杯数';

  @override
  String get statKnockouts => '击倒数';

  @override
  String get statsBestScores => '最高分';

  @override
  String statsAchievements(int unlocked, int total) {
    return '成就  $unlocked/$total';
  }

  @override
  String get statBestScore => '最高分';
}
