/// The home-menu centerpiece: a row of four animated procedural stickmen in the
/// player palette colors (red / blue / green / yellow). Rather than idling with
/// a single canned flourish, each mascot runs a little personality loop — it
/// breathes, then at random intervals picks a fresh stunt from a playlist
/// (springy JUMP with a real arc, a RUN-in-place burst, a DASH, a CAST, a
/// SPECIAL cheer, or an attack COMBO). Phases are staggered per figure, so the
/// lineup reads as a lively, rowdy party crew rather than four clones doing the
/// same wave.
///
/// No image assets — everything is the procedural [StickFigure] art.
///
/// Performance: one [Ticker] drives every figure's `update(dt)`; a single
/// [CustomPainter] renders all of them sequentially (the painter's Paint/Path
/// objects are static and reused); the whole widget sits under a
/// [RepaintBoundary] so it never repaints the rest of the menu.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/constants.dart';

/// How many mascots to show (capped at the 4-player palette per the budget).
const int _kMascotCount = 4;

/// Vertical band the lineup is drawn in.
const double _kBandHeight = 132;

/// Figure scale relative to the base hero proportions.
const double _kFigureScale = 1.18;

/// Gentle breathing bob amplitude (px).
const double _kBobAmplitude = 3.0;

/// Subtle breathing scale amplitude (fraction of base size) layered on the bob
/// so each mascot visibly "breathes" while idling.
const double _kBreathAmplitude = 0.025;

/// Peak height of a mascot's springy jump (px).
const double _kJumpHeight = 26.0;

/// Min / max seconds a mascot rests (idle breathing) between stunts.
const double _kRestMin = 0.7;
const double _kRestMax = 2.4;

/// Duration of a JUMP arc and a RUN-in-place burst (seconds).
const double _kJumpDur = 0.62;
const double _kRunBurstMin = 0.7;
const double _kRunBurstMax = 1.4;

/// An animated lineup of player-colored stickmen. Drop into the hero section.
///
/// Optionally pass a [cheerSignal]: every time it notifies, the crew breaks into
/// a staggered celebratory hop (used when QUICK PLAY is pressed). It is purely
/// cosmetic — the lineup behaves identically when it is null.
class HomeMascots extends StatefulWidget {
  const HomeMascots({super.key, this.height = _kBandHeight, this.cheerSignal});

  /// Height of the drawing band.
  final double height;

  /// Optional trigger; each notification makes the crew cheer.
  final Listenable? cheerSignal;

  @override
  State<HomeMascots> createState() => _HomeMascotsState();
}

class _HomeMascotsState extends State<HomeMascots>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  final List<_Mascot> _mascots = <_Mascot>[];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _buildMascots();
    widget.cheerSignal?.addListener(_cheer);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(HomeMascots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cheerSignal != widget.cheerSignal) {
      oldWidget.cheerSignal?.removeListener(_cheer);
      widget.cheerSignal?.addListener(_cheer);
    }
  }

  /// Kick off a staggered celebratory hop across the crew.
  void _cheer() {
    for (int i = 0; i < _mascots.length; i++) {
      _mascots[i].requestCheer(i * 0.08);
    }
  }

  void _buildMascots() {
    final StickProportions proportions =
        StickProportions.hero.scaled(_kFigureScale);
    for (int i = 0; i < _kMascotCount; i++) {
      final Color color =
          Color(PlayerPalette.argb[i % PlayerPalette.argb.length]);
      // Inner figures face the centre so the group reads as a crew facing in.
      final double facing = i < _kMascotCount / 2 ? 1.0 : -1.0;
      final StickFigure figure = StickFigure(
        proportions: proportions,
        style: _styleFor(color),
        facing: facing,
      )..setLoco(LocoState.idle);
      _mascots.add(
        _Mascot(
          figure: figure,
          // A per-figure RNG seeded by index keeps each mascot's stunt order
          // varied yet stable for the widget's lifetime.
          rng: math.Random(0x5715 + i * 97),
          // Stagger phases + first-stunt delays so the lineup never moves in
          // lockstep — one's mid-jump while another is just winding up.
          bobPhase: i * 0.7,
          restTimer: 0.35 + i * 0.5,
        ),
      );
    }
  }

  /// A vivid player-colored neon style for a mascot.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        coreColor: _brighten(color, 0.7),
        rimAlpha: 0.3,
        shadowAlpha: 0.0,
        gradientBottom: 0.55,
        smearAlpha: 0.25,
      );

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t) ?? c;

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    final double clampedDt = dt.clamp(0.0, 0.05);
    final double now = elapsed.inMicroseconds / 1e6;

    for (final _Mascot m in _mascots) {
      m.tick(clampedDt, now);
    }
    _frame.value++;
  }

  @override
  void dispose() {
    widget.cheerSignal?.removeListener(_cheer);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _MascotPainter(_frame, _mascots),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// The stunts a mascot can perform between rests.
enum _Stunt { jump, run, dash, special, cast, combo }

/// Per-figure animation bookkeeping (mutable; lives for the widget's lifetime).
class _Mascot {
  _Mascot({
    required this.figure,
    required this.rng,
    required this.bobPhase,
    required this.restTimer,
  });

  final StickFigure figure;
  final math.Random rng;
  final double bobPhase;

  /// Gentle vertical breathing (px), recomputed each tick.
  double _bob = 0;

  /// Vertical lift from an active jump arc (px, <= 0 = up).
  double _jumpY = 0;

  /// Total vertical offset the painter applies to the render root.
  double get yOffset => _bob + _jumpY;

  /// A subtle breathing scale (~1.0) the painter applies for extra liveliness —
  /// the torso swells a touch on the inhale. Recomputed each tick.
  double _breath = 1.0;
  double get breathScale => _breath;

  /// Seconds left before a queued cheer fires (>0 ⇒ counting down to the hop).
  /// Negative when no cheer is pending. Lets the crew stagger their celebration.
  double _cheerDelay = -1;

  /// Queue a celebratory hop after [delay] seconds (staggered per mascot).
  void requestCheer(double delay) {
    _cheerDelay = delay;
  }

  /// Seconds left before the next stunt is chosen (>0 ⇒ resting/idle).
  double restTimer;

  /// The stunt currently playing, if any.
  _Stunt? _active;

  /// Progress timer + duration for timed stunts (jump / run).
  double _t = 0;
  double _dur = 0;

  /// Cycles attack combos for variety.
  int _comboIndex = 0;

  /// Weighted playlist: springy jumps + run bursts are the eye-catchers, with
  /// upper-body flourishes mixed in. Repeated entries bias the random pick.
  static const List<_Stunt> _playlist = <_Stunt>[
    _Stunt.jump,
    _Stunt.jump,
    _Stunt.run,
    _Stunt.dash,
    _Stunt.special,
    _Stunt.cast,
    _Stunt.combo,
  ];

  void tick(double dt, double now) {
    figure.update(dt);
    _bob = math.sin((now + bobPhase) * 1.6) * _kBobAmplitude;
    // Breathing swell, slightly out of phase with the bob so it never reads as a
    // single mechanical pulse.
    _breath =
        1.0 + math.sin((now + bobPhase) * 1.3 + 0.6) * _kBreathAmplitude;

    // A queued cheer fires once the figure is free, launching a springy hop.
    if (_cheerDelay >= 0) {
      _cheerDelay -= dt;
      if (_cheerDelay <= 0 && !figure.actionPlaying) {
        _cheerDelay = -1;
        _active = _Stunt.jump;
        _t = 0;
        _dur = _kJumpDur;
        figure.setLoco(LocoState.jump);
        figure.special();
      }
    }

    if (_active == _Stunt.jump) {
      _t += dt;
      final double p = (_t / _dur).clamp(0.0, 1.0);
      // Parabolic arc: 0 → up → 0.
      _jumpY = -_kJumpHeight * math.sin(math.pi * p);
      // Swap to a falling pose past the apex for a believable landing.
      if (p >= 0.55 && figure.loco == LocoState.jump) {
        figure.setLoco(LocoState.fall);
      }
      if (p >= 1.0) {
        _jumpY = 0;
        figure.setLoco(LocoState.idle);
        figure.land();
        _endStunt();
      }
      return;
    }

    if (_active == _Stunt.run) {
      _t += dt;
      if (_t >= _dur) {
        figure.setLoco(LocoState.idle);
        _endStunt();
      }
      return;
    }

    // One-shot upper-body stunts (dash/special/cast/combo) just play out on the
    // animator; we wait for them to finish before resting.
    if (_active != null) {
      if (!figure.actionPlaying) _endStunt();
      return;
    }

    // Resting: count down, then launch a fresh stunt.
    restTimer -= dt;
    if (restTimer <= 0 && !figure.actionPlaying) _startStunt();
  }

  void _endStunt() {
    _active = null;
    _t = 0;
    restTimer = _kRestMin + rng.nextDouble() * (_kRestMax - _kRestMin);
  }

  void _startStunt() {
    final _Stunt s = _playlist[rng.nextInt(_playlist.length)];
    _active = s;
    _t = 0;
    switch (s) {
      case _Stunt.jump:
        _dur = _kJumpDur;
        figure.setLoco(LocoState.jump);
        break;
      case _Stunt.run:
        _dur =
            _kRunBurstMin + rng.nextDouble() * (_kRunBurstMax - _kRunBurstMin);
        figure.setLoco(LocoState.run);
        break;
      case _Stunt.dash:
        figure.dash();
        break;
      case _Stunt.special:
        figure.special();
        break;
      case _Stunt.cast:
        figure.cast();
        break;
      case _Stunt.combo:
        figure.attack(_comboIndex++);
        break;
    }
  }
}

/// Renders the mascot lineup. The figures are laid out evenly across the width
/// and vertically anchored so their feet sit near the band's bottom.
class _MascotPainter extends CustomPainter {
  _MascotPainter(this.repaintFrame, this.mascots) : super(repaint: repaintFrame);

  final ValueListenable<int> repaintFrame;
  final List<_Mascot> mascots;

  /// Reused across mascots and frames; only the shader is reassigned (the glow
  /// follows each bobbing mascot, so the shader is rebuilt, but the Paint object
  /// is not reallocated per mascot per frame on the always-on menu).
  final Paint _glowPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (mascots.isEmpty) return;
    final int n = mascots.length;
    // Pelvis baseline: leave room for the legs below it (~thigh+shin) plus a
    // little ground breathing space.
    final double baseline = size.height * 0.72;
    final double slot = size.width / n;

    for (int i = 0; i < n; i++) {
      final _Mascot m = mascots[i];
      final double cx = slot * (i + 0.5);
      final Offset root = Offset(cx, baseline + m.yOffset);
      // Soft ground glow under each mascot for grounding. Anchored to the ground
      // (not the jump), and it shrinks a touch as the mascot leaps for "lift".
      _drawGroundGlow(canvas, m, baseline, cx, slot);
      // Breathing: scale the figure about its pelvis root (a touch more on Y)
      // so the torso swells without the feet sliding. Cheap save/transform.
      final double s = m.breathScale;
      canvas.save();
      canvas.translate(root.dx, root.dy);
      canvas.scale(s, s * 1.04);
      canvas.translate(-root.dx, -root.dy);
      m.figure.render(canvas, root);
      canvas.restore();
    }
  }

  void _drawGroundGlow(
      Canvas canvas, _Mascot m, double baseline, double cx, double slot) {
    final Color tint = m.figure.style.outline;
    final double gy = baseline + 56;
    // Higher leaps cast a smaller, fainter pool — a subtle airborne cue.
    final double lift = (-m.yOffset / _kJumpHeight).clamp(0.0, 1.0);
    final double r = slot * (0.42 - 0.10 * lift);
    final double a = 0.20 * (1.0 - 0.45 * lift);
    _glowPaint.shader = ui.Gradient.radial(
      Offset(cx, gy),
      r,
      <Color>[tint.withValues(alpha: a), tint.withValues(alpha: 0.0)],
    );
    canvas.drawCircle(Offset(cx, gy), r, _glowPaint);
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) => false;
}
