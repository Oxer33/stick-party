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
  String get noGamesToShow => '지금 보여줄 게임이 없습니다.';

  @override
  String get fromTheStudio => '스튜디오 제공';

  @override
  String get actionGet => '받기';

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

  @override
  String get howto_sumo_smash => '탭으로 돌진하고 꾹 눌러 버텨요. 라이벌을 링 밖으로 밀어내세요!';

  @override
  String get howto_bumper_balls => '뒤로 드래그해 조준하고 놓아서 발사해요. 핀에 튕겨 라이벌을 날려버리세요!';

  @override
  String get howto_one_touch_soccer =>
      '드래그로 달리고, 탭으로 공을 잡고, 탭으로 슛해요. 골을 가장 많이 넣으세요!';

  @override
  String get howto_tank_duel =>
      '드래그로 조준하고 꾹 눌러 포물선을 모은 뒤 놓아서 발사해요. 적 탱크를 맞히세요!';

  @override
  String get howto_archer_pop =>
      '뒤로 드래그해 조준하고 힘을 모은 뒤 놓아서 쏘세요. 움직이는 과녁을 터뜨리세요!';

  @override
  String get howto_chicken_jump => '탭으로 폴짝 뛰고, 꾹 누르면 위험한 이단 점프예요. 최대한 높이 오르세요!';

  @override
  String get howto_falling_dodge => '좌우를 탭해 떨어지는 블록을 피해요. 아슬아슬하게 피할수록 점수가 높아요!';

  @override
  String get howto_tap_sprint =>
      '일정한 리듬으로 탭해 달리고, 꾹 눌렀다 놓아 허들을 넘으세요. 1등으로 들어오세요!';

  @override
  String get howto_tug_of_war =>
      '박자에 맞춰 탭해 당겨요. 힘이 가득 차면 강력한 파워 당기기가 터져요. 줄다리기에서 이기세요!';

  @override
  String get howto_button_masher => '도는 막대 사이 틈에서 탭해 한 칸씩 올라가요. 꼭대기에 닿으세요!';

  @override
  String get howto_reaction_duel => '기다렸다가 초록불이 되는 순간 탭하세요. 페이크에 속지 마세요!';

  @override
  String get howto_snake_arena =>
      '좌우를 탭해 방향을 틀어요. 먹어서 자라고, 라이벌의 길을 막고, 끝까지 살아남으세요!';

  @override
  String get howto_paint_splash =>
      '빈 칸과 라이벌 칸을 연속으로 탭해 물감을 튀겨요. 가장 넓은 영역을 차지하세요!';

  @override
  String get howto_catch_the_star => '드래그로 바구니를 움직여요. 별은 받고 폭탄은 피하세요!';

  @override
  String get howto_color_memory => '색깔 순서를 보고 그대로 탭해 따라 하세요. 끝까지 기억하는 사람이 이겨요!';

  @override
  String get howto_tap_to_start => '탭하여 시작';

  @override
  String get cupSetupTitle => '컵 설정';

  @override
  String get playersTitle => '플레이어';

  @override
  String playersAddUpTo(int max) {
    return '최대 $max명까지 추가';
  }

  @override
  String get seatHuman => '사람';

  @override
  String get seatCpu => 'CPU';

  @override
  String get modeLabel => '모드';

  @override
  String get modeFreeForAll => '각자도생';

  @override
  String get modeDuel1v1 => '1대1';

  @override
  String get modeTeam2v2 => '2대2';

  @override
  String get modeTeam3v3 => '3대3';

  @override
  String get actionStart => '시작';

  @override
  String get startCup => '컵 시작';

  @override
  String get shopStickSkins => '스킨';

  @override
  String get shopMapThemes => '맵 테마';

  @override
  String get shopStore => '스토어';

  @override
  String get shopStickSkinEyebrow => '스킨';

  @override
  String get shopMapThemeEyebrow => '맵 테마';

  @override
  String get shopCoinPack => '코인 팩';

  @override
  String get shopUnlockEyebrow => '잠금 해제';

  @override
  String get shopFreeAlwaysYours => '무료 • 영원히 내 것';

  @override
  String get shopEquipped => '장착됨';

  @override
  String get shopOwned => '보유 중';

  @override
  String shopPriceCoins(int count) {
    return '코인 $count개';
  }

  @override
  String get shopTopUpCoins => '코인 충전';

  @override
  String get shopOneTimeUnlock => '일회성 잠금 해제';

  @override
  String get shopBuy => '구매';

  @override
  String get shopUse => '사용';

  @override
  String shopUnlocked(String name) {
    return '$name 잠금 해제!';
  }

  @override
  String get shopNotEnoughCoins => '코인이 부족합니다.';

  @override
  String shopPurchased(String title) {
    return '$title 구매 완료.';
  }

  @override
  String shopPurchaseFailed(String error) {
    return '구매 실패: $error';
  }

  @override
  String get shopEthicsNote =>
      '구매 항목은 외형 전용이며 게임플레이에 전혀 영향을 주지 않습니다. 표시된 가격은 실제 금액이며 앱 스토어가 정합니다.';

  @override
  String get loginBonus => '로그인 보너스';

  @override
  String get todaysMissions => '오늘의 미션';

  @override
  String claimedCoins(int count) {
    return '+$count 코인을 받았습니다!';
  }

  @override
  String get rewardClaimed => '보상을 받았습니다!';

  @override
  String dayN(int day) {
    return '$day일째';
  }

  @override
  String coinsAmount(int count) {
    return '+$count 코인';
  }

  @override
  String cosmeticReward(int count) {
    return '외형 보상 $count개';
  }

  @override
  String get comeBackTomorrow => '내일 다시 오세요';

  @override
  String get tapClaimToCollect => '받기를 눌러 획득하세요';

  @override
  String get claim => '받기';

  @override
  String get claimed => '받음';

  @override
  String missionPlayRounds(int count) {
    return '$count 라운드 플레이';
  }

  @override
  String missionWinRounds(int count) {
    return '$count 라운드 승리';
  }

  @override
  String get missionWinCup => '컵 대회 우승';

  @override
  String get missionTryNewGame => '새 게임 해보기';

  @override
  String missionPlayWithPlayers(int count) {
    return '$count명과 플레이';
  }

  @override
  String cupGameProgress(int current, int total) {
    return '게임 $current/$total';
  }

  @override
  String cupStandingsTitle(int current, int total) {
    return '순위 • $current/$total';
  }

  @override
  String cupNextGameButton(int current, int total) {
    return '다음 게임 ($current/$total)';
  }

  @override
  String cupPoints(int count) {
    return '$count점';
  }

  @override
  String get cupChampionTitle => '챔피언';

  @override
  String get cupChampionBanner => '컵 챔피언';

  @override
  String get cupRematch => '재대결';

  @override
  String get cupHome => '홈';

  @override
  String get cupNextGame => '다음 게임';

  @override
  String cupRoundOf(int current, int total) {
    return '$total 라운드 중 $current';
  }

  @override
  String get resultsTitle => '결과';

  @override
  String get resultWinner => '승자';

  @override
  String get resultNext => '다음';

  @override
  String get resultMenu => '메뉴';

  @override
  String get resultSuperlativeSoloRun => '단독 질주!';

  @override
  String get resultSuperlativeCleanSweep => '완승!';

  @override
  String get resultSuperlativePhotoFinish => '사진 판정!';

  @override
  String get resultSuperlativeDominant => '압도적!';

  @override
  String get resultSuperlativeFlawless => '완벽!';

  @override
  String get statsCareer => '커리어';

  @override
  String get statCoins => '코인';

  @override
  String get statRoundsPlayed => '플레이한 라운드';

  @override
  String get statCupsWon => '획득한 컵';

  @override
  String get statKnockouts => '녹아웃';

  @override
  String get statsBestScores => '최고 점수';

  @override
  String statsAchievements(int unlocked, int total) {
    return '업적  $unlocked/$total';
  }

  @override
  String get statBestScore => '최고 점수';
}
