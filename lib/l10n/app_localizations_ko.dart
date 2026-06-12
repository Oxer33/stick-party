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
}
