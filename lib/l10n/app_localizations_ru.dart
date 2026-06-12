// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get sectionGameplay => 'Игровой процесс';

  @override
  String get cpuDifficulty => 'Сложность ИИ';

  @override
  String get difficultyEasy => 'Лёгкая';

  @override
  String get difficultyMedium => 'Средняя';

  @override
  String get difficultyHard => 'Сложная';

  @override
  String get screenShake => 'Тряска экрана';

  @override
  String get sectionLanguage => 'Язык';

  @override
  String get languageSystem => 'Системный по умолчанию';

  @override
  String get sectionPurchases => 'Покупки';

  @override
  String get restorePurchases => 'Восстановить покупки';

  @override
  String get restorePurchasesDesc =>
      'Заново применить ваши разовые разблокировки';

  @override
  String get purchasesRestored => 'Покупки восстановлены.';

  @override
  String get sectionData => 'Данные';

  @override
  String get resetProgress => 'Сбросить прогресс';

  @override
  String get resetProgressDesc => 'Удалить монеты, разблокировки и статистику';

  @override
  String get resetConfirmTitle => 'Сбросить прогресс?';

  @override
  String get resetConfirmBody =>
      'Это безвозвратно удалит ваши монеты, косметические предметы и статистику. Это действие нельзя отменить.';

  @override
  String get actionCancel => 'Отмена';

  @override
  String get actionReset => 'Сбросить';

  @override
  String get progressReset => 'Прогресс сброшен.';

  @override
  String get aboutBody =>
      'Для всех возрастов. Работает полностью офлайн. Без аккаунтов и отслеживания. Внутриигровые покупки носят только косметический характер и никогда не влияют на игровой процесс — без лутбоксов, без pay-to-win, без тёмных паттернов.';
}
