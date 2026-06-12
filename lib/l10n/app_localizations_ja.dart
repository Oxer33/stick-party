// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get settingsTitle => '設定';

  @override
  String get sectionGameplay => 'ゲームプレイ';

  @override
  String get cpuDifficulty => 'CPUの難易度';

  @override
  String get difficultyEasy => 'かんたん';

  @override
  String get difficultyMedium => 'ふつう';

  @override
  String get difficultyHard => 'むずかしい';

  @override
  String get screenShake => '画面の揺れ';

  @override
  String get sectionLanguage => '言語';

  @override
  String get languageSystem => 'システムのデフォルト';

  @override
  String get sectionPurchases => '購入';

  @override
  String get restorePurchases => '購入を復元';

  @override
  String get restorePurchasesDesc => '一度きりのアンロックを再適用します';

  @override
  String get purchasesRestored => '購入を復元しました。';

  @override
  String get sectionData => 'データ';

  @override
  String get resetProgress => '進行状況をリセット';

  @override
  String get resetProgressDesc => 'コイン・アンロック・統計を消去します';

  @override
  String get resetConfirmTitle => '進行状況をリセットしますか？';

  @override
  String get resetConfirmBody => 'コイン、装飾アイテム、統計が完全に消去されます。この操作は元に戻せません。';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get actionReset => 'リセット';

  @override
  String get progressReset => '進行状況をリセットしました。';

  @override
  String get aboutBody =>
      '全年齢対象。完全オフラインでプレイできます。アカウント不要、追跡なし。アプリ内課金は見た目だけのもので、ゲームプレイには一切影響しません — ルートボックスなし、ペイ・トゥ・ウィンなし、ダークパターンなし。';

  @override
  String get homeTagline => '2 • 3 • 4 人プレイ';

  @override
  String get navSettings => '設定';

  @override
  String get quickPlay => 'クイックプレイ';

  @override
  String get actionCup => 'カップ戦';

  @override
  String get actionCupHint => 'トーナメント';

  @override
  String get actionShop => 'ショップ';

  @override
  String get actionShopHint => 'スキンとテーマ';

  @override
  String get actionDaily => 'デイリー';

  @override
  String get actionDailyHintReady => '報酬を受け取れます';

  @override
  String get actionDailyHintDefault => 'ミッション';

  @override
  String get actionStats => '成績';

  @override
  String get actionStatsHint => 'あなたの記録';

  @override
  String get moreGames => 'もっとゲーム';

  @override
  String gamesCount(int count) {
    return '$count ゲーム';
  }

  @override
  String get pickAGame => 'ゲームを選ぶ';

  @override
  String get noGamesForPlayerCount => 'この人数で遊べるゲームはありません。';

  @override
  String get game_sumo_smash => 'すもう大相撲';

  @override
  String get game_bumper_balls => 'バンパーボール';

  @override
  String get game_one_touch_soccer => 'ワンタッチサッカー';

  @override
  String get game_tank_duel => '戦車バトル';

  @override
  String get game_archer_pop => 'アーチャーポップ';

  @override
  String get game_chicken_jump => 'チキンジャンプ';

  @override
  String get game_falling_dodge => '落下よけ';

  @override
  String get game_tap_sprint => 'タップダッシュ';

  @override
  String get game_tug_of_war => '綱引き';

  @override
  String get game_button_masher => '連打バトル';

  @override
  String get game_reaction_duel => '反射神経バトル';

  @override
  String get game_snake_arena => 'スネークアリーナ';

  @override
  String get game_paint_splash => 'ペイントスプラッシュ';

  @override
  String get game_catch_the_star => 'スターをキャッチ';

  @override
  String get game_color_memory => 'カラーメモリー';

  @override
  String get hint_tap => 'タップ';

  @override
  String get hint_hold => '長押し';

  @override
  String get hint_mash => '連打';

  @override
  String get hint_move => '移動';

  @override
  String get hint_drag => 'ドラッグ';
}
