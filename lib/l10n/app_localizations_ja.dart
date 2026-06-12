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
}
