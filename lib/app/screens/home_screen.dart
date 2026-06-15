/// Home / main menu — the party showcase. A drifting mesh + confetti backdrop,
/// a frosted top bar (coins, streak, settings cog), a hero block with the big
/// gradient "STICK PARTY" logo and a lineup of animated procedural stickman
/// mascots, a prominent QUICK PLAY button, a grid of illustrated action cards
/// (CUP / SHOP / DAILY / STATS), a horizontal showcase of all 15 minigames, and
/// a house-ad "more games" teaser at the bottom (the cross-promo funnel).
///
/// Navigation, providers and the cross-promo flow are unchanged from the
/// original; only the presentation is richer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/rng.dart';
import '../../l10n/app_localizations.dart';
import '../../meta/daily.dart';
import '../../meta/progress_store.dart';
import '../../meta/streak.dart';
import '../../services/analytics_service.dart';
import '../../services/cross_promo_service.dart';
import '../providers.dart';
import '../router.dart';
import '../widgets/games_showcase.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/home_confetti.dart';
import '../widgets/home_mascots.dart';
import '../widgets/mesh_background.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

/// Big logo type size.
const double _kTitleSize = 60;

/// Height of the prominent primary action button.
const double _kPrimaryHeight = 84;

/// Leading glyph-badge size inside a secondary action card.
const double _kActionGlyphSize = 50;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Progress progress = ref.watch(progressProvider);
    final bool dailyAvailable = _dailyAvailable(ref);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MeshGradientBackground(
        child: Stack(
          children: <Widget>[
            // Drifting confetti sits above the mesh, below the menu content.
            const Positioned.fill(child: HomeConfetti()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GlassTokens.pagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: GlassTokens.gapSmall),
                    _TopBar(coins: progress.coins, streak: progress.streak)
                        .animate()
                        .fadeIn(duration: GlassTokens.entrance)
                        .slideY(begin: -0.3, end: 0, curve: Curves.easeOutCubic),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(
                          top: GlassTokens.gap,
                          bottom: GlassTokens.gap,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            // Hero + QUICK PLAY are bundled so pressing play can
                            // make the mascots cheer. They are the first beats of
                            // the orchestrated entrance cascade (hero → quick
                            // play → grid → showcase → teaser).
                            const _HeroBlock(),
                            const SizedBox(height: GlassTokens.gapSmall),
                            _ActionGrid(dailyAvailable: dailyAvailable),
                            const SizedBox(height: GlassTokens.gap + 4),
                            _Showcase()
                                .animate()
                                .fadeIn(
                                  delay: 460.ms,
                                  duration: GlassTokens.entrance,
                                )
                                .slideY(
                                  begin: 0.2,
                                  end: 0,
                                  curve: Curves.easeOutCubic,
                                ),
                            const SizedBox(height: GlassTokens.gap),
                            const _HouseAdTeaser()
                                .animate()
                                .fadeIn(
                                  delay: 560.ms,
                                  duration: GlassTokens.entrance,
                                )
                                .slideY(
                                  begin: 0.4,
                                  end: 0,
                                  curve: Curves.easeOutCubic,
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// True when the login bonus has not yet been claimed for today's calendar
  /// day. Read-only check (claiming happens on the daily screen).
  bool _dailyAvailable(WidgetRef ref) {
    final DailyClaimStore store = ref.read(dailyClaimStoreProvider);
    final String today = DailyService.isoForDate(DateTime.now());
    return store.lastClaimDayIso != today;
  }
}

/// The frosted top bar: coins, streak (conditional) and a settings cog.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.coins, required this.streak});

  final int coins;
  final StreakState streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        CoinBadge(coins: coins),
        const SizedBox(width: GlassTokens.gapSmall),
        StreakBadge(streak: streak),
        const Spacer(),
        GlassChip(
          icon: Icons.settings,
          label: AppLocalizations.of(context).navSettings,
          accent: GlassColors.cyan,
          onTap: () => context.push(AppRoutes.settings),
        ),
      ],
    );
  }
}

/// The hero: the two-word gradient logo + subtitle, with the animated mascot
/// lineup as the centerpiece beneath it. The logo reads like an arcade marquee —
/// a continuous light bar sweeps across the letters and a soft colored bloom
/// drifts behind them.
class _Hero extends StatelessWidget {
  const _Hero({this.cheerSignal});

  /// Forwarded to the mascot lineup so the crew can cheer on QUICK PLAY.
  final Listenable? cheerSignal;

  @override
  Widget build(BuildContext context) {
    final TextStyle titleStyle = GlassText.display.copyWith(
      fontSize: _kTitleSize,
    );
    // Kept as two separate words ("STICK" / "PARTY") so the smoke test can find
    // each independently, while still reading as the "STICK PARTY" logo. Each
    // word carries a travelling sheen bar; the bloom behind gives marquee depth.
    final Widget title = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _MarqueeWord(
          text: 'STICK',
          style: titleStyle,
          gradient: const LinearGradient(
            colors: <Color>[GlassColors.violet, GlassColors.magenta],
          ),
        ),
        _MarqueeWord(
          text: 'PARTY',
          style: titleStyle,
          gradient: const LinearGradient(
            colors: <Color>[GlassColors.magenta, GlassColors.cyan],
          ),
          // Offset the second word's sweep so the light reads as one continuous
          // bar travelling down the whole logo rather than two in lockstep.
          phase: 0.5,
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context).homeTagline,
          textAlign: TextAlign.center,
          style: GlassText.overline.copyWith(letterSpacing: 4),
        ),
      ],
    );

    return Column(
      children: <Widget>[
        // Bloom sits behind the type; the title floats above it in the stack.
        Stack(
          alignment: Alignment.center,
          children: <Widget>[
            const Positioned.fill(child: _TitleBloom()),
            title
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(
                  begin: const Offset(0.92, 0.92),
                  end: const Offset(1, 1),
                ),
          ],
        ),
        const SizedBox(height: 6),
        HomeMascots(cheerSignal: cheerSignal)
            .animate()
            .fadeIn(delay: 120.ms, duration: 700.ms)
            .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
      ],
    );
  }
}

/// Bundles the hero (logo + mascots) with the QUICK PLAY button and owns a tiny
/// [ChangeNotifier]: tapping play pings it, and the mascot lineup reacts with a
/// celebratory hop. Navigation is unchanged — the cheer fires alongside the push.
class _HeroBlock extends StatefulWidget {
  const _HeroBlock();

  @override
  State<_HeroBlock> createState() => _HeroBlockState();
}

class _HeroBlockState extends State<_HeroBlock> {
  final _CheerSignal _cheer = _CheerSignal();

  @override
  void dispose() {
    _cheer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Hero(cheerSignal: _cheer)
            .animate()
            .fadeIn(duration: GlassTokens.entrance)
            .slideY(begin: -0.08, end: 0, curve: Curves.easeOutCubic),
        const SizedBox(height: GlassTokens.gap),
        _PrimaryPlayButton(onPlayPressed: _cheer.ping)
            .animate()
            .fadeIn(delay: 200.ms, duration: GlassTokens.entrance)
            .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic),
      ],
    );
  }
}

/// A trivial broadcast signal: [ping] notifies listeners (the mascots) with no
/// payload. Wraps [ChangeNotifier] only to expose a public notify method.
class _CheerSignal extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// One word of the logo: gradient-filled type with a continuous light bar that
/// travels across the glyphs (the "marquee sheen"). Built as a masked moving
/// highlight so it reads as a sweeping bar rather than the all-over twinkle of a
/// plain shimmer. Cheap: a single repeating controller drives a [LinearGradient]
/// shader; no per-frame blur.
class _MarqueeWord extends StatelessWidget {
  const _MarqueeWord({
    required this.text,
    required this.style,
    required this.gradient,
    this.phase = 0.0,
  });

  final String text;
  final TextStyle style;
  final LinearGradient gradient;

  /// 0..1 offset into the sweep cycle, so stacked words feel like one bar.
  final double phase;

  @override
  Widget build(BuildContext context) {
    final Widget base = gradientText(
      text,
      style: style,
      textAlign: TextAlign.center,
      gradient: gradient,
    );
    return base
        .animate(onPlay: (AnimationController c) => c.repeat())
        .custom(
          duration: 2600.ms,
          builder: (BuildContext context, double value, Widget child) {
            // Travel a narrow bright band from left to right across the word.
            final double t = (value + phase) % 1.0;
            final double center = -0.35 + t * 1.7;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (Rect bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Colors.transparent,
                  GlassColors.frost.withValues(alpha: 0.0),
                  GlassColors.frost.withValues(alpha: 0.85),
                  GlassColors.frost.withValues(alpha: 0.0),
                  Colors.transparent,
                ],
                stops: <double>[
                  (center - 0.22).clamp(0.0, 1.0),
                  (center - 0.10).clamp(0.0, 1.0),
                  center.clamp(0.0, 1.0),
                  (center + 0.10).clamp(0.0, 1.0),
                  (center + 0.22).clamp(0.0, 1.0),
                ],
              ).createShader(bounds),
              child: child,
            );
          },
        );
  }
}

/// A soft, slowly breathing colored bloom that sits behind the logo for marquee
/// depth — three stacked radial glows in the brand accents that pulse together.
/// Visual-only and pointer-transparent; one repeating controller scales them.
class _TitleBloom extends StatelessWidget {
  const _TitleBloom();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 320,
          height: 150,
          child:
              Stack(
                alignment: Alignment.center,
                children: const <Widget>[
                  _BloomBlob(
                    color: GlassColors.violet,
                    size: 230,
                    dx: -70,
                    alpha: 0.30,
                  ),
                  _BloomBlob(
                    color: GlassColors.magenta,
                    size: 200,
                    dx: 0,
                    alpha: 0.26,
                  ),
                  _BloomBlob(
                    color: GlassColors.cyan,
                    size: 220,
                    dx: 70,
                    alpha: 0.24,
                  ),
                ],
              )
                  .animate(
                    onPlay: (AnimationController c) => c.repeat(reverse: true),
                  )
                  .scaleXY(begin: 0.92, end: 1.06, duration: 3200.ms)
                  .fadeIn(duration: 800.ms),
        ),
      ),
    );
  }
}

/// A single radial glow blob used by [_TitleBloom]. Painted with a radial
/// gradient (no [ImageFilter] blur) so it stays cheap on the always-on menu.
class _BloomBlob extends StatelessWidget {
  const _BloomBlob({
    required this.color,
    required this.size,
    required this.dx,
    required this.alpha,
  });

  final Color color;
  final double size;
  final double dx;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prominent QUICK PLAY call-to-action. Fires [onPlayPressed] (a cosmetic
/// cheer cue) just before routing into setup; routing itself is unchanged.
class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({this.onPlayPressed});

  /// Optional cosmetic hook invoked on tap (makes the mascots cheer).
  final VoidCallback? onPlayPressed;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: AppLocalizations.of(context).quickPlay,
      icon: Icons.play_arrow_rounded,
      primary: true,
      accent: GlassColors.violet,
      height: _kPrimaryHeight,
      onTap: () {
        onPlayPressed?.call();
        context.push(
          AppRoutes.setup,
          extra: const SetupArgs(isCup: false),
        );
      },
    );
  }
}

/// Immutable spec for one secondary action card.
class _Action {
  const _Action({
    required this.label,
    required this.hint,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.showDot = false,
  });

  final String label;

  /// Short supporting line under the label (gives each button real hierarchy).
  final String hint;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool showDot;
}

/// The 2-column grid of illustrated secondary actions: CUP / SHOP / DAILY /
/// STATS, each with its own accent color and a procedural glyph.
class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.dailyAvailable});

  final bool dailyAvailable;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<_Action> actions = <_Action>[
      _Action(
        label: l10n.actionCup,
        hint: l10n.actionCupHint,
        icon: Icons.emoji_events,
        accent: GlassColors.amber,
        onTap: () => context.push(
          AppRoutes.setup,
          extra: const SetupArgs(isCup: true),
        ),
      ),
      _Action(
        label: l10n.actionShop,
        hint: l10n.actionShopHint,
        icon: Icons.storefront,
        accent: GlassColors.magenta,
        onTap: () => context.push(AppRoutes.shop),
      ),
      _Action(
        label: l10n.actionDaily,
        hint: dailyAvailable
            ? l10n.actionDailyHintReady
            : l10n.actionDailyHintDefault,
        icon: Icons.calendar_today,
        accent: GlassColors.cyan,
        showDot: dailyAvailable,
        onTap: () => context.push(AppRoutes.daily),
      ),
      _Action(
        label: l10n.actionStats,
        hint: l10n.actionStatsHint,
        icon: Icons.bar_chart,
        accent: GlassColors.flame,
        onTap: () => context.push(AppRoutes.stats),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: GlassTokens.gapSmall,
      crossAxisSpacing: GlassTokens.gapSmall,
      childAspectRatio: 1.55,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        for (int i = 0; i < actions.length; i++)
          _ActionCard(action: actions[i])
              .animate()
              .fadeIn(
                delay: (GlassTokens.stagger * i) +
                    const Duration(milliseconds: 280),
                duration: GlassTokens.entrance,
              )
              .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic),
      ],
    );
  }
}

/// One illustrated action card: a premium accent-edged panel (edge + glow) with
/// a procedural glyph badge, a bold label and a small supporting hint, plus an
/// optional notification dot. Tapping press-scales the whole card.
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    final _Action a = action;
    return PressableCard(
      onTap: a.onTap,
      child: PremiumPanel(
        accent: a.accent,
        highlight: a.showDot,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: <Widget>[
            _GlyphBadge(icon: a.icon, accent: a.accent),
            const SizedBox(width: 12),
            Expanded(child: _labels(a)),
            if (a.showDot) const _NotifyDot(),
          ],
        ),
      ),
    );
  }

  Widget _labels(_Action a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          a.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GlassText.label,
        ),
        const SizedBox(height: 3),
        Text(
          a.hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GlassText.body.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

/// A small rounded accent badge holding an action's icon (the "illustration").
class _GlyphBadge extends StatelessWidget {
  const _GlyphBadge({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kActionGlyphSize,
      height: _kActionGlyphSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[accent, accent.withValues(alpha: 0.55)],
        ),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.4),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }
}

/// The games-catalog strip. Tapping a tile routes into quick-play setup.
class _Showcase extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GamesShowcase(
      onTapGame: (_) => context.push(
        AppRoutes.setup,
        extra: const SetupArgs(isCup: false),
      ),
    );
  }
}

/// A small accent dot used as a "something to claim" indicator.
class _NotifyDot extends StatelessWidget {
  const _NotifyDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: GlassColors.magenta,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: GlassColors.magenta.withValues(alpha: 0.8),
            blurRadius: 8,
          ),
        ],
      ),
    ).animate(onPlay: (AnimationController c) => c.repeat(reverse: true)).fadeIn(
          duration: 800.ms,
        );
  }
}

/// A "More Games" teaser card driven by the cross-promo service. Tapping records
/// a click, opens the (stub) store, and routes to the full list.
class _HouseAdTeaser extends ConsumerStatefulWidget {
  const _HouseAdTeaser();

  @override
  ConsumerState<_HouseAdTeaser> createState() => _HouseAdTeaserState();
}

class _HouseAdTeaserState extends ConsumerState<_HouseAdTeaser> {
  HouseAd? _ad;

  @override
  void initState() {
    super.initState();
    // Pick once per mount so the teaser is stable while the menu is visible.
    final CrossPromoService promo = ref.read(crossPromoProvider);
    _ad = promo.pickWeighted(SeededRng());
    if (_ad != null) {
      promo.recordImpression(_ad!.id);
      ref
          .read(analyticsProvider)
          .logEvent(AnalyticsEvents.houseAdImpression, <String, Object?>{
        'id': _ad!.id,
        'surface': 'home_teaser',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final HouseAd? ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    final Color accent = Color(ad.iconArgb);
    return PremiumMediaTile(
      accent: accent,
      leading: ProceduralIcon(label: ad.title, colorArgb: ad.iconArgb),
      eyebrow: AppLocalizations.of(context).moreGames,
      title: ad.title,
      supporting: ad.blurb.isNotEmpty ? ad.blurb : null,
      trailing: const Icon(Icons.chevron_right, color: GlassColors.textMuted),
      onTap: () => _onTap(ad),
    );
  }

  Future<void> _onTap(HouseAd ad) async {
    final CrossPromoService promo = ref.read(crossPromoProvider);
    ref
        .read(analyticsProvider)
        .logEvent(AnalyticsEvents.houseAdClick, <String, Object?>{'id': ad.id});
    await promo.openStore(ad); // stub also records the click
    if (!mounted) return;
    context.push(AppRoutes.more);
  }
}
