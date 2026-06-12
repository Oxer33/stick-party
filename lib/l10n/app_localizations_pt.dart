// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get sectionGameplay => 'Jogabilidade';

  @override
  String get cpuDifficulty => 'Dificuldade da CPU';

  @override
  String get difficultyEasy => 'Fácil';

  @override
  String get difficultyMedium => 'Média';

  @override
  String get difficultyHard => 'Difícil';

  @override
  String get screenShake => 'Tremor de tela';

  @override
  String get sectionLanguage => 'Idioma';

  @override
  String get languageSystem => 'Padrão do sistema';

  @override
  String get sectionPurchases => 'Compras';

  @override
  String get restorePurchases => 'Restaurar compras';

  @override
  String get restorePurchasesDesc => 'Reaplique seus desbloqueios únicos';

  @override
  String get purchasesRestored => 'Compras restauradas.';

  @override
  String get sectionData => 'Dados';

  @override
  String get resetProgress => 'Redefinir progresso';

  @override
  String get resetProgressDesc => 'Apague moedas, desbloqueios e estatísticas';

  @override
  String get resetConfirmTitle => 'Redefinir o progresso?';

  @override
  String get resetConfirmBody =>
      'Isso apaga permanentemente suas moedas, cosméticos e estatísticas. Não é possível desfazer.';

  @override
  String get actionCancel => 'Cancelar';

  @override
  String get actionReset => 'Redefinir';

  @override
  String get progressReset => 'Progresso redefinido.';

  @override
  String get aboutBody =>
      'Classificação livre. Funciona totalmente offline. Sem contas, sem rastreamento. As compras no aplicativo são apenas cosméticas e nunca afetam a jogabilidade — sem caixas de recompensa, sem pagar para vencer, sem padrões obscuros.';
}
