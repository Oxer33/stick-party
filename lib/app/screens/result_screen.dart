/// Result screen for a single quick-play round: a PODIUM SPECTACLE that pays off
/// the match. Placement blocks (gold/silver/bronze) rise + stagger in, the
/// winner's procedural stickman cheers on top of the 1st-place block, a confetti
/// burst fires on reveal, and every score ticks up from zero.
///
/// One [Ticker] drives the whole show — the reveal timeline (block rise + score
/// count-up + confetti), and the live winner [StickFigure]'s `victory()` loop.
/// The stage is a single [CustomPaint] under a [RepaintBoundary]; the painter's
/// Paint/Path objects are static and reused (the stickman painter is pure), so
/// the animation stays cheap. Navigation/logic + the public route args are
/// unchanged.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/player_manager.dart';
import '../router.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import 'premium_card.dart';

class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.args});

  final ResultArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerManager players = args.players;
    final List<int> ranking = args.result.ranking;

    // Resolve the ranking into the (up to 4) finishers we can draw, best→worst,
    // pairing each with its slot + final score. Missing slots are skipped.
    final List<_Finisher> finishers = <_Finisher>[];
    for (int i = 0; i < ranking.length && finishers.length < 4; i++) {
      final PlayerSlot? slot = _slotById(players, ranking[i]);
      if (slot == null) continue;
      finishers.add(
        _Finisher(
          place: finishers.length + 1,
          slot: slot,
          score: (args.result.finalScores[ranking[i]] ?? 0).round(),
        ),
      );
    }

    final _Finisher? winner = finishers.isEmpty ? null : finishers.first;

    return GlassScaffold(
      title: 'RESULTS',
      showBack: false,
      scroll: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (winner != null) ...<Widget>[
            _WinnerHeadline(
              winner: winner,
              coinsEarned: args.coinsEarned,
              superlative: _superlative(finishers),
            ),
            const SizedBox(height: GlassTokens.gapSmall),
          ],
          // The animated stage fills the available space between the headline
          // and the actions.
          Expanded(
            child: finishers.isEmpty
                ? const SizedBox.shrink()
                : _PodiumSpectacle(finishers: finishers),
          ),
          const SizedBox(height: GlassTokens.gap),
          _Actions(gameId: args.gameId, players: players),
        ],
      ),
    );
  }

  PlayerSlot? _slotById(PlayerManager players, int id) {
    for (final PlayerSlot s in players.slots) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// A cheap one-line superlative derived from the final scores. Returns null
  /// when nothing fun applies (keeps the headline uncluttered for plain rounds).
  static String? _superlative(List<_Finisher> finishers) {
    if (finishers.isEmpty) return null;
    final int top = finishers.first.score;

    if (finishers.length == 1) {
      return top > 0 ? 'SOLO RUN!' : null;
    }

    final int second = finishers[1].score;

    // Everyone but the winner scored nothing → a total wipeout.
    final bool sweep = finishers.skip(1).every((_Finisher f) => f.score <= 0);
    if (top > 0 && sweep) return 'CLEAN SWEEP!';

    // Winner scored, nobody else came within one point → photo finish.
    if (top > 0 && (top - second).abs() <= 1) return 'PHOTO FINISH!';

    // Dominant margin (more than double the runner-up).
    if (second > 0 && top >= second * 2) return 'DOMINANT!';

    // A shut-out where the winner alone scored.
    if (top > 0 && second <= 0) return 'FLAWLESS!';

    return null;
  }
}

/// One resolved finisher: 1-based [place], its [slot] and final [score].
@immutable
class _Finisher {
  const _Finisher({
    required this.place,
    required this.slot,
    required this.score,
  });

  final int place;
  final PlayerSlot slot;
  final int score;

  Color get color => Color(slot.colorArgb);
}

// ─────────────────────────────────────────────────────────────────────────────
// Headline: WINNER + name + coins + an optional superlative.
// ─────────────────────────────────────────────────────────────────────────────

/// The celebratory headline above the podium: the winner's name in their color,
/// the coins earned this round, and (when derivable) a punchy superlative — on a
/// strongly-tinted premium panel that pops in.
class _WinnerHeadline extends StatelessWidget {
  const _WinnerHeadline({
    required this.winner,
    required this.coinsEarned,
    required this.superlative,
  });

  final _Finisher winner;
  final int coinsEarned;
  final String? superlative;

  @override
  Widget build(BuildContext context) {
    final Color color = winner.color;
    return PremiumPanel(
      accent: color,
      highlight: true,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.emoji_events, color: GlassColors.amber, size: 22),
              const SizedBox(width: 8),
              Text(
                'WINNER',
                style: GlassText.overline.copyWith(letterSpacing: 4),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            winner.slot.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GlassText.display.copyWith(fontSize: 30, color: color),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (superlative != null) ...<Widget>[
                AccentTag(
                  label: superlative!,
                  accent: GlassColors.cyan,
                  icon: Icons.bolt,
                ),
                const SizedBox(width: GlassTokens.gapSmall),
              ],
              if (coinsEarned > 0)
                AccentTag(
                  label: '+$coinsEarned',
                  accent: GlassColors.amber,
                  icon: Icons.monetization_on,
                ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1, 1),
          curve: Curves.easeOutBack,
          duration: 500.ms,
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions row (rematch / next / home) — existing navigation, unchanged.
// ─────────────────────────────────────────────────────────────────────────────

/// The bold REMATCH primary button (re-runs the same game + roster) plus a
/// secondary NEXT and a tertiary MENU link. Wired to the existing routes.
class _Actions extends StatelessWidget {
  const _Actions({required this.gameId, required this.players});

  final String gameId;
  final PlayerManager players;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: GlassButton(
                label: 'REMATCH',
                icon: Icons.refresh,
                primary: true,
                accent: GlassColors.magenta,
                onTap: () => context.pushReplacement(
                  AppRoutes.play,
                  extra: PlayArgs(gameId: gameId, players: players),
                ),
              ),
            ),
            const SizedBox(width: GlassTokens.gapSmall),
            Expanded(
              child: GlassButton(
                label: 'NEXT',
                icon: Icons.grid_view_rounded,
                onTap: () => context.go(AppRoutes.select),
              ),
            ),
          ],
        ),
        const SizedBox(height: GlassTokens.gapSmall),
        TextButton(
          onPressed: () => context.go(AppRoutes.home),
          child: const Text('MENU'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The animated stage: rising podium blocks + live winner cheer + confetti +
// score count-up — all driven by a single Ticker.
// ─────────────────────────────────────────────────────────────────────────────

/// Reveal timeline tuning (no magic numbers inline).
class _Show {
  _Show._();

  /// Seconds before the first block starts rising.
  static const double lead = 0.15;

  /// Seconds each block takes to rise into place.
  static const double riseDur = 0.55;

  /// Stagger between successive places (3rd → 2nd → 1st so the winner lands
  /// last and biggest).
  static const double stagger = 0.18;

  /// Seconds the score numbers spend ticking up once their block has landed.
  static const double countDur = 0.7;

  /// Confetti burst lifetime in seconds.
  static const double confettiLife = 2.2;

  /// Confetti particle count (kept modest so the burst stays cheap).
  static const int confettiCount = 64;

  /// Figure scale relative to the base hero proportions.
  static const double figureScale = 1.15;
}

/// The animated podium. Stateful so it can own a [Ticker]; the winner's live
/// [StickFigure] is updated each tick and re-triggers its `victory()` cheer when
/// the clip finishes, so the screen keeps celebrating (unlike the frozen arena).
class _PodiumSpectacle extends StatefulWidget {
  const _PodiumSpectacle({required this.finishers});

  /// Best→worst, already resolved (1..4 entries).
  final List<_Finisher> finishers;

  @override
  State<_PodiumSpectacle> createState() => _PodiumSpectacleState();
}

class _PodiumSpectacleState extends State<_PodiumSpectacle>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  late final StickFigure _winnerFigure;
  late final List<_Confetto> _confetti;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _winnerFigure = _buildWinnerFigure(widget.finishers.first.color);
    _confetti = _buildConfetti(widget.finishers.first.color);
    _ticker = createTicker(_onTick)..start();
  }

  /// A vivid, player-colored neon figure that starts mid-cheer.
  StickFigure _buildWinnerFigure(Color color) {
    final StickFigure fig = StickFigure(
      proportions: StickProportions.hero.scaled(_Show.figureScale),
      style: StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        coreColor: _brighten(color, 0.7),
        rimAlpha: 0.3,
        shadowAlpha: 0.0,
        gradientBottom: 0.55,
        smearAlpha: 0.2,
      ),
      facing: 1,
    )..setLoco(LocoState.idle);
    fig.victory();
    return fig;
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t) ?? c;

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    final double clampedDt = dt.clamp(0.0, 0.05);

    _winnerFigure.update(clampedDt);
    // Keep the winner celebrating: relaunch the cheer whenever it finishes.
    if (!_winnerFigure.actionPlaying) _winnerFigure.victory();

    _clock.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PodiumPainter(
          clock: _clock,
          finishers: widget.finishers,
          winnerFigure: _winnerFigure,
          confetti: _confetti,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// One confetti particle of the reveal burst. Immutable; the painter advances it
/// analytically from the shared clock (no per-frame allocation).
@immutable
class _Confetto {
  const _Confetto({
    required this.color,
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.shape,
    required this.originX,
  });

  final Color color;

  /// Launch direction (radians; -pi/2 = straight up).
  final double angle;

  /// Initial speed (fraction of stage height per second).
  final double speed;

  /// Size in logical px.
  final double size;

  /// Spin speed (turns per second).
  final double spin;

  /// 0 = bar, 1 = diamond, 2 = dot.
  final int shape;

  /// Horizontal launch origin jitter (fraction of width, centred on the winner).
  final double originX;
}

/// Builds the confetti burst once: a fan of particles launched up-and-out from
/// the top of the winner's block, tinted from the winner's color + the accent
/// palette. Seeded so the layout is stable for the widget's lifetime.
List<_Confetto> _buildConfetti(Color winnerColor) {
  final math.Random rng = math.Random(0x5713);
  final List<Color> palette = <Color>[
    winnerColor,
    GlassColors.amber,
    GlassColors.cyan,
    GlassColors.magenta,
    GlassColors.violet,
  ];
  final List<_Confetto> out = <_Confetto>[];
  for (int i = 0; i < _Show.confettiCount; i++) {
    // Launch in a ~140° upward fan.
    final double spread = (rng.nextDouble() - 0.5) * (math.pi * 0.78);
    out.add(
      _Confetto(
        color: palette[i % palette.length],
        angle: -math.pi / 2 + spread,
        speed: 0.55 + rng.nextDouble() * 0.85,
        size: 5.0 + rng.nextDouble() * 7.0,
        spin: (rng.nextBool() ? 1 : -1) * (1.0 + rng.nextDouble() * 3.0),
        shape: i % 3,
        originX: 0.5 + (rng.nextDouble() - 0.5) * 0.12,
      ),
    );
  }
  return out;
}

/// Paints the podium reveal: gold/silver/bronze blocks that rise + stagger in,
/// each carrying its place medal, the player's color edge + name + counting
/// score, the live winner stickman cheering on the 1st block, and a confetti
/// burst over the top. Cheap: reuses Paint objects; the stickman painter is pure.
class _PodiumPainter extends CustomPainter {
  _PodiumPainter({
    required this.clock,
    required this.finishers,
    required this.winnerFigure,
    required this.confetti,
  }) : super(repaint: clock);

  final ValueListenable<double> clock;
  final List<_Finisher> finishers;
  final StickFigure winnerFigure;
  final List<_Confetto> confetti;

  // Reused paints (no per-frame allocation).
  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final Paint _glow = Paint()..isAntiAlias = true;

  // Relative block heights by place (1st tallest).
  static const Map<int, double> _heightFactor = <int, double>{
    1: 1.0,
    2: 0.74,
    3: 0.56,
    4: 0.44,
  };

  // Visual order across the floor: 2nd, 1st, 3rd, 4th (classic podium layout).
  static const List<int> _floorOrder = <int>[2, 1, 3, 4];

  // Tints per place (gold / silver / bronze / slate).
  static const Color _gold = Color(0xFFFFD24A);
  static const Color _silver = Color(0xFFCBD5E1);
  static const Color _bronze = Color(0xFFD08A4E);
  static const Color _slate = Color(0xFF8A93B8);

  static Color _tintFor(int place) {
    switch (place) {
      case 1:
        return _gold;
      case 2:
        return _silver;
      case 3:
        return _bronze;
      default:
        return _slate;
    }
  }

  static const Map<int, String> _medals = <int, String>{
    1: '🥇',
    2: '🥈',
    3: '🥉',
    4: '4',
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (finishers.isEmpty || size.width <= 0 || size.height <= 0) return;
    final double t = clock.value;

    // Place → finisher lookup (some places may be absent if slots were missing).
    final Map<int, _Finisher> byPlace = <int, _Finisher>{
      for (final _Finisher f in finishers) f.place: f,
    };

    // Layout: blocks share a baseline near the bottom; reserve headroom on top
    // for the winner figure + confetti.
    final double baseY = size.height * 0.96;
    final double maxBlockH = size.height * 0.46;
    const double topGap = 6.0;

    // Columns: evenly split the width across the visible floor slots.
    final List<int> floor =
        _floorOrder.where(byPlace.containsKey).toList(growable: false);
    final int columns = floor.length;
    if (columns == 0) return;
    final double colW = size.width / columns;
    final double blockW = colW * 0.82;

    // Winner geometry, captured while drawing, so the figure + confetti align to
    // the 1st-place block.
    double? winnerTopY;
    double? winnerCx;

    for (int i = 0; i < columns; i++) {
      final int place = floor[i];
      final _Finisher f = byPlace[place]!;
      final double cx = colW * (i + 0.5);

      // Per-place reveal progress with stagger (3rd/4th in first, winner last).
      final double delay = _Show.lead + (4 - place) * _Show.stagger;
      final double rp = _easeOutCubic(
        ((t - delay) / _Show.riseDur).clamp(0.0, 1.0),
      );
      if (rp <= 0.0) continue;

      final double fullH = maxBlockH * (_heightFactor[place] ?? 0.44);
      final double h = fullH * rp;
      final double topY = baseY - h;
      final Color tint = _tintFor(place);
      final Color playerColor = f.color;

      _drawBlock(
        canvas,
        cx: cx,
        topY: topY,
        baseY: baseY,
        width: blockW,
        tint: tint,
        playerColor: playerColor,
        reveal: rp,
      );

      // Score count-up begins once the block has essentially landed.
      final double countStart = delay + _Show.riseDur * 0.6;
      final double cp = ((t - countStart) / _Show.countDur).clamp(0.0, 1.0);
      final int shown = (f.score * _easeOutCubic(cp)).round();

      _drawBlockLabels(
        canvas,
        cx: cx,
        topY: topY,
        baseY: baseY,
        width: blockW,
        place: place,
        name: f.slot.name,
        playerColor: playerColor,
        score: shown,
        reveal: rp,
      );

      if (place == 1) {
        winnerTopY = topY;
        winnerCx = cx;
      }
    }

    // Winner stickman cheering on top of the 1st-place block — only once that
    // block has mostly risen (so it doesn't float in empty space early).
    if (winnerTopY != null && winnerCx != null) {
      final double winnerDelay = _Show.lead + (4 - 1) * _Show.stagger;
      final double wp = ((t - (winnerDelay + _Show.riseDur * 0.5)) / 0.35)
          .clamp(0.0, 1.0);
      if (wp > 0.0) {
        canvas.save();
        canvas.clipRect(Offset.zero & size);
        // A small celebratory hop layered on the victory pose.
        final double hop = -math.sin(t * 3.0).abs() * 6.0 * wp;
        final Offset root = Offset(winnerCx, winnerTopY - topGap + hop);
        // Soft ground glow under the winner for grounding + extra pop.
        _drawWinnerGlow(canvas, winnerCx, winnerTopY - topGap, blockW, wp);
        winnerFigure.render(canvas, root);
        canvas.restore();
      }

      // Confetti burst, anchored to the top of the winner block.
      _drawConfetti(
          canvas, size, winnerCx, winnerTopY - topGap, t, winnerDelay);
    }
  }

  // ── Blocks ─────────────────────────────────────────────────────────────────

  void _drawBlock(
    Canvas canvas, {
    required double cx,
    required double topY,
    required double baseY,
    required double width,
    required Color tint,
    required Color playerColor,
    required double reveal,
  }) {
    final double half = width / 2;
    final Rect rect = Rect.fromLTRB(cx - half, topY, cx + half, baseY);
    final RRect rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
    );

    // Soft outer glow in the medal tint — stronger as it lands.
    _glow
      ..shader = null
      ..color = tint.withValues(alpha: 0.28 * reveal)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(rrect, _glow);
    _glow.maskFilter = null;

    // Body: a vertical gradient from the medal tint into the player color, so
    // each block reads as both "gold/silver/bronze" and "this player".
    _fill.shader = ui.Gradient.linear(
      Offset(cx, topY),
      Offset(cx, baseY),
      <Color>[
        Color.lerp(tint, Colors.white, 0.25)!.withValues(alpha: 0.95),
        tint.withValues(alpha: 0.85),
        Color.lerp(playerColor, tint, 0.4)!.withValues(alpha: 0.9),
      ],
      <double>[0.0, 0.35, 1.0],
    );
    canvas.drawRRect(rrect, _fill);
    _fill.shader = null;

    // Top face highlight (a thin lighter cap = a lit 3D top).
    final Rect cap = Rect.fromLTWH(cx - half, topY, width, 6);
    _fill.color = Colors.white.withValues(alpha: 0.35 * reveal);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        cap,
        topLeft: const Radius.circular(12),
        topRight: const Radius.circular(12),
      ),
      _fill,
    );

    // Player-color edge so the block is unmistakably theirs.
    _stroke
      ..color = playerColor.withValues(alpha: 0.9)
      ..strokeWidth = 2.0;
    canvas.drawRRect(rrect, _stroke);
  }

  void _drawBlockLabels(
    Canvas canvas, {
    required double cx,
    required double topY,
    required double baseY,
    required double width,
    required int place,
    required String name,
    required Color playerColor,
    required int score,
    required double reveal,
  }) {
    final double alpha = reveal.clamp(0.0, 1.0);

    // Big medal / place number, centred on the block face.
    final double faceMid = (topY + baseY) / 2;
    _paintText(
      canvas,
      text: _medals[place] ?? '$place',
      center: Offset(cx, faceMid),
      style: TextStyle(
        fontSize: place == 1 ? 30 : 24,
        fontWeight: FontWeight.w900,
        color: Colors.white.withValues(alpha: alpha),
        shadows: <Shadow>[
          Shadow(
            color: Colors.black.withValues(alpha: 0.45 * alpha),
            blurRadius: 6,
          ),
        ],
      ),
      maxWidth: width,
    );

    // Name + score sit just above the block top.
    final double labelY = topY - 10;
    _paintText(
      canvas,
      text: name,
      center: Offset(cx, labelY - 12),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        color: GlassColors.text.withValues(alpha: alpha),
        shadows: <Shadow>[
          Shadow(
              color: Colors.black.withValues(alpha: 0.5 * alpha),
              blurRadius: 4),
        ],
      ),
      maxWidth: width + 16,
    );
    _paintText(
      canvas,
      text: '$score',
      center: Offset(cx, labelY + 4),
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
        color: Color.lerp(playerColor, Colors.white, 0.25)!
            .withValues(alpha: alpha),
        shadows: <Shadow>[
          Shadow(
              color: Colors.black.withValues(alpha: 0.5 * alpha),
              blurRadius: 4),
        ],
      ),
      maxWidth: width + 16,
    );
  }

  // ── Winner glow ──────────────────────────────────────────────────────────────

  void _drawWinnerGlow(
      Canvas canvas, double cx, double topY, double width, double p) {
    final Color tint = winnerFigure.style.outline;
    final double r = width * 0.6;
    _glow
      ..maskFilter = null
      ..shader = ui.Gradient.radial(
        Offset(cx, topY),
        r,
        <Color>[
          tint.withValues(alpha: 0.28 * p),
          tint.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(Offset(cx, topY), r, _glow);
    _glow.shader = null;
  }

  // ── Confetti ─────────────────────────────────────────────────────────────────

  void _drawConfetti(Canvas canvas, Size size, double originCx,
      double originTopY, double t, double winnerDelay) {
    // Burst fires the instant the winner block lands.
    final double burstT = winnerDelay + _Show.riseDur * 0.5;
    final double age = t - burstT;
    if (age < 0 || age > _Show.confettiLife) return;

    final double gravity = size.height * 0.9; // px/s² in stage space
    _glow.maskFilter = null;
    _glow.shader = null;
    for (final _Confetto c in confetti) {
      final double vx = math.cos(c.angle) * c.speed * size.height;
      final double vy = math.sin(c.angle) * c.speed * size.height;
      final double x =
          originCx + (c.originX - 0.5) * size.width * 0.2 + vx * age;
      final double y = originTopY + vy * age + 0.5 * gravity * age * age;
      if (y > size.height + 20) continue;

      // Fade out over the back 40% of the life.
      final double fade =
          (1.0 - ((age / _Show.confettiLife - 0.6) / 0.4)).clamp(0.0, 1.0);
      if (fade <= 0.01) continue;

      _fill.shader = null;
      _fill.color = c.color.withValues(alpha: fade);
      final double rot = c.spin * age * math.pi * 2;
      _paintConfetto(canvas, c, Offset(x, y), rot);
    }
  }

  void _paintConfetto(Canvas canvas, _Confetto c, Offset pos, double rot) {
    if (c.shape == 2) {
      canvas.drawCircle(pos, c.size * 0.45, _fill);
      return;
    }
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(c.shape == 1 ? rot + math.pi / 4 : rot);
    if (c.shape == 1) {
      // Diamond.
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: c.size * 0.7, height: c.size * 0.7),
        _fill,
      );
    } else {
      // Bar.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: c.size * 1.6, height: c.size * 0.5),
          Radius.circular(c.size * 0.25),
        ),
        _fill,
      );
    }
    canvas.restore();
  }

  // ── Text helper ────────────────────────────────────────────────────────────

  void _paintText(
    Canvas canvas, {
    required String text,
    required Offset center,
    required TextStyle style,
    required double maxWidth,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static double _easeOutCubic(double x) {
    final double inv = 1.0 - x;
    return 1.0 - inv * inv * inv;
  }

  @override
  bool shouldRepaint(covariant _PodiumPainter oldDelegate) => false;
}
