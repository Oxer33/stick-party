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
}
