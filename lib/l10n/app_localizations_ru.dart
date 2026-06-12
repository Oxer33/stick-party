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

  @override
  String get homeTagline => 'ИГРЫ НА 2 • 3 • 4 ИГРОКА';

  @override
  String get navSettings => 'НАСТРОЙКИ';

  @override
  String get quickPlay => 'БЫСТРАЯ ИГРА';

  @override
  String get actionCup => 'КУБОК';

  @override
  String get actionCupHint => 'Турнир';

  @override
  String get actionShop => 'МАГАЗИН';

  @override
  String get actionShopHint => 'Скины и темы';

  @override
  String get actionDaily => 'ЕЖЕДНЕВНО';

  @override
  String get actionDailyHintReady => 'Награда готова';

  @override
  String get actionDailyHintDefault => 'Задания';

  @override
  String get actionStats => 'СТАТИСТИКА';

  @override
  String get actionStatsHint => 'Ваши рекорды';

  @override
  String get moreGames => 'ЕЩЁ ИГРЫ';

  @override
  String gamesCount(int count) {
    return '$count ИГР';
  }

  @override
  String get pickAGame => 'ВЫБЕРИ ИГРУ';

  @override
  String get noGamesForPlayerCount => 'Нет игр для такого числа игроков.';

  @override
  String get game_sumo_smash => 'Сумо-схватка';

  @override
  String get game_bumper_balls => 'Шары-толкачи';

  @override
  String get game_one_touch_soccer => 'Футбол в касание';

  @override
  String get game_tank_duel => 'Танковая дуэль';

  @override
  String get game_archer_pop => 'Меткий лучник';

  @override
  String get game_chicken_jump => 'Прыг-курица';

  @override
  String get game_falling_dodge => 'Уворот от падений';

  @override
  String get game_tap_sprint => 'Тап-спринт';

  @override
  String get game_tug_of_war => 'Перетягивание каната';

  @override
  String get game_button_masher => 'Жми на кнопку';

  @override
  String get game_reaction_duel => 'Дуэль на реакцию';

  @override
  String get game_snake_arena => 'Арена змеек';

  @override
  String get game_paint_splash => 'Брызги краски';

  @override
  String get game_catch_the_star => 'Поймай звезду';

  @override
  String get game_color_memory => 'Память цветов';

  @override
  String get hint_tap => 'ТАП';

  @override
  String get hint_hold => 'ДЕРЖИ';

  @override
  String get hint_mash => 'ЖМИ';

  @override
  String get hint_move => 'ДВИГАЙ';

  @override
  String get hint_drag => 'ТЯНИ';

  @override
  String get cupSetupTitle => 'НАСТРОЙКА КУБКА';

  @override
  String get playersTitle => 'ИГРОКИ';

  @override
  String playersAddUpTo(int max) {
    return 'Добавьте до $max';
  }

  @override
  String get seatHuman => 'ЧЕЛОВЕК';

  @override
  String get seatCpu => 'ИИ';

  @override
  String get modeLabel => 'РЕЖИМ';

  @override
  String get modeFreeForAll => 'КАЖДЫЙ ЗА СЕБЯ';

  @override
  String get modeDuel1v1 => '1 на 1';

  @override
  String get modeTeam2v2 => '2 на 2';

  @override
  String get modeTeam3v3 => '3 на 3';

  @override
  String get actionStart => 'СТАРТ';

  @override
  String get startCup => 'НАЧАТЬ КУБОК';

  @override
  String get shopStickSkins => 'СКИНЫ';

  @override
  String get shopMapThemes => 'ТЕМЫ КАРТ';

  @override
  String get shopStore => 'МАГАЗИН';

  @override
  String get shopStickSkinEyebrow => 'СКИН';

  @override
  String get shopMapThemeEyebrow => 'ТЕМА КАРТЫ';

  @override
  String get shopCoinPack => 'НАБОР МОНЕТ';

  @override
  String get shopUnlockEyebrow => 'РАЗБЛОКИРОВКА';

  @override
  String get shopFreeAlwaysYours => 'Бесплатно • навсегда ваше';

  @override
  String get shopEquipped => 'Выбрано';

  @override
  String get shopOwned => 'В наличии';

  @override
  String shopPriceCoins(int count) {
    return '$count монет';
  }

  @override
  String get shopTopUpCoins => 'Пополните монеты';

  @override
  String get shopOneTimeUnlock => 'Разовая разблокировка';

  @override
  String get shopBuy => 'КУПИТЬ';

  @override
  String get shopUse => 'ВЫБРАТЬ';

  @override
  String shopUnlocked(String name) {
    return '$name разблокировано!';
  }

  @override
  String get shopNotEnoughCoins => 'Недостаточно монет.';

  @override
  String shopPurchased(String title) {
    return '$title куплено.';
  }

  @override
  String shopPurchaseFailed(String error) {
    return 'Не удалось купить: $error';
  }

  @override
  String get shopEthicsNote =>
      'Покупки носят только косметический характер и никогда не влияют на игровой процесс. Показанные цены реальны и устанавливаются магазином приложений.';
}
