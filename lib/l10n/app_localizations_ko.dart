// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get settingsTitle => '설정';

  @override
  String get sectionGameplay => '게임플레이';

  @override
  String get cpuDifficulty => 'CPU 난이도';

  @override
  String get difficultyEasy => '쉬움';

  @override
  String get difficultyMedium => '보통';

  @override
  String get difficultyHard => '어려움';

  @override
  String get screenShake => '화면 흔들림';

  @override
  String get sectionLanguage => '언어';

  @override
  String get languageSystem => '시스템 기본값';

  @override
  String get sectionPurchases => '구매';

  @override
  String get restorePurchases => '구매 복원';

  @override
  String get restorePurchasesDesc => '일회성 잠금 해제를 다시 적용합니다';

  @override
  String get purchasesRestored => '구매가 복원되었습니다.';

  @override
  String get sectionData => '데이터';

  @override
  String get resetProgress => '진행 상황 초기화';

  @override
  String get resetProgressDesc => '코인, 잠금 해제, 통계를 삭제합니다';

  @override
  String get resetConfirmTitle => '진행 상황을 초기화할까요?';

  @override
  String get resetConfirmBody =>
      '코인, 꾸미기 아이템, 통계가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.';

  @override
  String get actionCancel => '취소';

  @override
  String get actionReset => '초기화';

  @override
  String get progressReset => '진행 상황이 초기화되었습니다.';

  @override
  String get aboutBody =>
      '전체 이용가. 완전히 오프라인으로 플레이됩니다. 계정 없음, 추적 없음. 인앱 구매는 외형용일 뿐이며 게임플레이에 전혀 영향을 주지 않습니다 — 랜덤 박스 없음, 페이투윈 없음, 다크 패턴 없음.';

  @override
  String get homeTagline => '2 • 3 • 4인용 게임';

  @override
  String get navSettings => '설정';

  @override
  String get quickPlay => '바로 플레이';

  @override
  String get actionCup => '컵 대회';

  @override
  String get actionCupHint => '토너먼트';

  @override
  String get actionShop => '상점';

  @override
  String get actionShopHint => '스킨과 테마';

  @override
  String get actionDaily => '데일리';

  @override
  String get actionDailyHintReady => '보상 받기 가능';

  @override
  String get actionDailyHintDefault => '미션';

  @override
  String get actionStats => '통계';

  @override
  String get actionStatsHint => '나의 기록';

  @override
  String get moreGames => '게임 더 보기';

  @override
  String gamesCount(int count) {
    return '게임 $count개';
  }

  @override
  String get pickAGame => '게임 선택';

  @override
  String get noGamesForPlayerCount => '이 인원수로 플레이할 수 있는 게임이 없습니다.';

  @override
  String get game_sumo_smash => '스모 대결';

  @override
  String get game_bumper_balls => '범퍼 볼';

  @override
  String get game_one_touch_soccer => '원터치 축구';

  @override
  String get game_tank_duel => '탱크 결투';

  @override
  String get game_archer_pop => '명궁 팡팡';

  @override
  String get game_chicken_jump => '치킨 점프';

  @override
  String get game_falling_dodge => '낙하물 피하기';

  @override
  String get game_tap_sprint => '탭 스프린트';

  @override
  String get game_tug_of_war => '줄다리기';

  @override
  String get game_button_masher => '버튼 연타';

  @override
  String get game_reaction_duel => '반응 속도 대결';

  @override
  String get game_snake_arena => '스네이크 아레나';

  @override
  String get game_paint_splash => '페인트 스플래시';

  @override
  String get game_catch_the_star => '별 잡기';

  @override
  String get game_color_memory => '색깔 기억';

  @override
  String get hint_tap => '탭';

  @override
  String get hint_hold => '꾹 누르기';

  @override
  String get hint_mash => '연타';

  @override
  String get hint_move => '이동';

  @override
  String get hint_drag => '드래그';
}
