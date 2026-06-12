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
}
