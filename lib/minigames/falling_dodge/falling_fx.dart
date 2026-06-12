import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../core/rng.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/lane_hopper.dart';
import 'falling_render.dart';

/// Visual + chaos helpers extracted from falling_dodge.dart to keep that file
/// under the size cap. Pure value types + a small per-track token manager; no
/// Flutter widgets, no global state.

/// One falling hazard in a player's band. Mutable, round-scoped value.
class HazardFx {
  final int lane;
  final HazardKind kind;
  final double size;
  final double speedMul;
  final double spinPhase; // deterministic per-hazard spin offset
  double y;
  bool counted = false; // near-miss/strike resolved once as it crosses

  HazardFx({
    required this.lane,
    required this.kind,
    required this.size,
    required this.speedMul,
    required this.spinPhase,
    required this.y,
  });
}

/// A short-lived per-lane near-miss flash anchor (visual only). Mutable,
/// round-scoped value.
class FlashFx {
  final int lane;
  double life;
  final double maxLife;
  FlashFx({required this.lane, required this.life}) : maxLife = life;
  double get strength => maxLife <= 0 ? 0 : (life / maxLife).clamp(0.0, 1.0);
}

/// A falling golden token any runner can scoop for bonus points — the CHAOS /
/// surprise lever. Drifts down a single lane; caught when the runner shares its
/// lane as it crosses the runner line, otherwise it falls away. Mutable value.
class TokenFx {
  final int lane;
  final double size;
  double y;
  bool resolved = false; // caught or missed exactly once at the runner line

  TokenFx({required this.lane, required this.size, required this.y});
}

/// Numeric tuning for the token chaos lever (no magic numbers inline).
class TokenTuning {
  const TokenTuning._();

  // Cadence: tokens are an occasional treat, not a stream. One token per track
  // at a time; a fresh one is scheduled a few seconds after the last resolves.
  static const double firstSpawnSec = 3.2; // earliest a token can appear
  static const double respawnMinSec = 4.0; // gap lower bound after one resolves
  static const double respawnMaxSec = 7.5; // gap upper bound

  static const double fallSpeed = 250; // px/s drift (independent of hazards)
  static const double sizeFactor = 0.5; // token size / lane spacing
  static const double bonusScore = 12; // points for a scoop (a stylish prize)

  static const Color gold = Color(0xFFFFD23C);
  static const Color goldSoft = Color(0xFFFFE99A);

  /// Hot accent for the one-shot sudden-death "DANGER!" climax cue.
  static const Color dangerColor = Color(0xFFFF5A4D);
}

/// Per-track golden-token state + scheduler. One token alive at a time; the
/// owner ticks it and asks whether it was just caught or missed at the runner
/// line. Keeps all token bookkeeping out of the main game file.
class TokenLane {
  TokenFx? token;
  double _nextSpawnAt;

  TokenLane({double firstSpawnAt = TokenTuning.firstSpawnSec})
      : _nextSpawnAt = firstSpawnAt;

  bool get hasToken => token != null;

  /// Spawn (on cadence) + fall the token, then resolve a catch/miss at the
  /// runner line. Returns the caught token (for fx) or null. Owns ALL token
  /// bookkeeping so the game's per-frame call is a one-liner.
  TokenFx? tick({
    required double dt,
    required double elapsed,
    required int spawnLane,
    required double laneSpacing,
    required double bandTop,
    required double bandBottom,
    required double runnerY,
    required int runnerLane,
    required SeededRng rng,
  }) {
    _maybeSpawn(elapsed, spawnLane, laneSpacing, bandTop);
    final t = token;
    if (t == null) return null;
    final prevY = t.y;
    t.y += TokenTuning.fallSpeed * dt;
    // Resolve the runner-line crossing exactly once.
    if (!t.resolved && prevY <= runnerY && t.y >= runnerY) {
      t.resolved = true;
      _scheduleNext(elapsed, rng);
      if (t.lane == runnerLane) {
        token = null; // consumed on the spot
        return t;
      }
    }
    if (t.y > bandBottom + t.size) token = null; // fell away
    return null;
  }

  void _maybeSpawn(
      double elapsed, int lane, double laneSpacing, double bandTop) {
    if (token != null || elapsed < _nextSpawnAt) return;
    final size = laneSpacing * TokenTuning.sizeFactor;
    token = TokenFx(lane: lane, size: size, y: bandTop - size);
  }

  void _scheduleNext(double elapsed, SeededRng rng) {
    _nextSpawnAt = elapsed +
        rng.range(TokenTuning.respawnMinSec, TokenTuning.respawnMaxSec);
  }

  /// Draw the live token (a glowing golden coin) via the shared renderer.
  void render(Canvas canvas, double laneX, double t) {
    final tok = token;
    if (tok == null) return;
    FallingRenderer.drawToken(canvas, Offset(laneX, tok.y), tok.size, t);
  }
}

/// One-shot Juice bursts for the falling-dodge feel beats. Static so the main
/// game file stays lean (and under the size cap); all scoring/state stays in the
/// game — these only spray particles + popups + shake.
class FallingFx {
  const FallingFx._();

  /// The golden-burst + "GOLD!" popup + light shake for scooping a token.
  static void collectToken(
    Juice juice, {
    required Offset at,
    required Offset popupAt,
    required double figureScale,
  }) {
    juice.particles.burst(
      at: at,
      count: 14,
      color: TokenTuning.gold,
      speed: 280,
      size: 5,
      gravity: 420,
      life: 0.6,
    );
    juice.popup(popupAt, 'GOLD!', TokenTuning.goldSoft,
        size: 22 + 8 * figureScale);
    juice.shake.light();
  }

  /// A single "DANGER!" popup for one runner at the start of sudden death.
  static void dangerPopup(Juice juice, Offset at) {
    juice.popup(at, 'DANGER!', TokenTuning.dangerColor, size: 24);
  }
}

/// One player's dodge track: a horizontal band with lanes, a runner hopping
/// between them, and its own stream of falling hazards + a golden token. Mutable
/// round-scoped state (allowed for the duration of a single round).
class TrackFx {
  final int playerId;
  final Color color;
  final Rect band;
  final LaneSet lanes;
  final double runnerY; // fixed y where the runner stands
  final double figureLift; // pelvis lift so feet plant on the runner line
  final double figureScale;
  final Hopper hopper;
  final StickFigure figure;
  final List<HazardFx> hazards = <HazardFx>[];
  final List<FlashFx> flashes = <FlashFx>[];
  final TokenLane tokens = TokenLane();

  bool alive = true;
  int hopDir = 1; // last hop direction (bounces at the ends)
  double spawnTimer = 0;
  double hopHold = 0; // brief jump-pose timer after a hop
  int grazeChain = 0; // consecutive EARNED-dodge streak (resets on over-fleeing)
  int grazeBannerAt = 0; // highest chain that has fired a STREAK banner (latch)
  double respawnTimer = 0; // seconds until a crushed runner returns (0 = none)
  double invuln = 0; // post-respawn grace: can't be crushed (seconds)
  double aliveSec = 0; // cumulative seconds spent alive this run (tiebreaker)
  ReactionClock? clock;

  // ── Earned-dodge bookkeeping (what makes a graze SKILL, not proximity) ──────
  // When the runner hops AWAY from a lane that had an imminent hazard, we stamp
  // that lane + a short claim window here. A passing hazard only banks a graze
  // if it crosses the lane the runner just vacated UNDER THREAT within the
  // window — i.e. the player genuinely read the danger and stepped off in time.
  int dodgeFromLane = -1; // the threatened lane the runner just left (-1 = none)
  double dodgeClaimSec = 0; // remaining seconds to cash that dodge as a graze

  TrackFx({
    required this.playerId,
    required this.color,
    required this.band,
    required this.lanes,
    required this.runnerY,
    required this.figureLift,
    required this.figureScale,
    required this.hopper,
    required this.figure,
    this.clock,
  });

  /// Lane x-coordinates for the renderer.
  List<double> laneXs() =>
      [for (var i = 0; i < lanes.count; i++) lanes.coordOf(i)];

  /// 0..1 telegraph intensity for a hazard: grows as it nears the runner line.
  double telegraphProgress(HazardFx h) {
    final fall = runnerY - band.top;
    if (fall <= 0) return 1;
    final remaining = (runnerY - h.y).clamp(0.0, fall);
    return (1.0 - remaining / fall).clamp(0.0, 1.0);
  }

  /// 0..1 how close the nearest in-lane hazard is to the runner line; drives the
  /// band frame danger glow.
  double dangerLevel() {
    if (!alive) return 0;
    var best = 0.0;
    for (final h in hazards) {
      if (h.lane != hopper.lane || h.y > runnerY) continue;
      best = math.max(best, telegraphProgress(h));
    }
    return best;
  }
}

/// Draws one full dodge track (band, lanes, flashes, telegraphs, runner, token,
/// hazards, label). Kept out of the game file so it stays under the size cap;
/// pure rendering, no state mutation.
class FallingTrackPainter {
  const FallingTrackPainter._();

  static const double _hintPulseHz = 3.2;
  static const double _spinPerSec = 2.4;
  static const int _chainMaxPips = 6; // streak pips shown above the runner
  static const double _chainPulseHz = 6.0; // streak badge throb rate
  static const double _chainLiftFactor = 0.5; // badge lift / lane spacing

  static void draw(
    Canvas canvas,
    TrackFx t, {
    required double scroll,
    required double animClock,
    required int laneCount,
  }) {
    FallingRenderer.drawBand(canvas, t.band, t.color,
        scroll: scroll, danger: t.dangerLevel(), alive: t.alive);
    FallingRenderer.drawLanes(
        canvas, t.band, t.laneXs(), t.hopper.visualLane, t.alive);

    // Near-miss lane flashes (under hazards).
    for (final f in t.flashes) {
      FallingRenderer.drawNearMissFlash(
          canvas, t.band, t.lanes.coordOf(f.lane), f.strength);
    }

    // Ground telegraphs for every approaching hazard.
    if (t.alive) {
      for (final h in t.hazards) {
        if (h.y > t.runnerY) continue;
        FallingRenderer.drawTelegraph(canvas, t.lanes.coordOf(h.lane),
            t.runnerY, h.size, t.telegraphProgress(h));
      }
    }

    // Runner contact shadow + figure.
    final runnerX = t.lanes.coordOfVisual(t.hopper.visualLane);
    if (!t.figure.isRagdoll) {
      FallingRenderer.drawContactShadow(canvas, Offset(runnerX, t.runnerY),
          t.lanes.spacing.abs() * 0.5, t.alive);
    }

    // Directional control affordance: small left/right hop hints flanking the
    // live runner. A side dims when blocked by a wall (already at the end lane).
    if (t.alive && !t.figure.isRagdoll) {
      final pulse = 0.5 + 0.5 * math.sin(animClock * _hintPulseHz);
      FallingRenderer.drawHopHints(
        canvas,
        Offset(runnerX, t.runnerY),
        t.lanes.spacing.abs(),
        t.color,
        pulse,
        canLeft: t.hopper.lane > 0,
        canRight: t.hopper.lane < laneCount - 1,
      );
    }

    FallingRenderer.drawRunner(
        canvas, t.figure, Offset(runnerX, t.runnerY - t.figureLift));

    // Live graze-chain streak badge floating above the runner's head. Only the
    // close dodge banks points, so showing the streak here makes "stay near the
    // danger" the obvious play.
    if (t.alive && t.grazeChain >= 1) {
      final pulse = 0.5 + 0.5 * math.sin(animClock * _chainPulseHz);
      final headY =
          t.runnerY - t.figureLift - t.lanes.spacing.abs() * _chainLiftFactor;
      FallingRenderer.drawGrazeChain(
        canvas,
        Offset(runnerX, headY),
        t.figureScale,
        t.grazeChain,
        _chainMaxPips,
        pulse,
      );
    }

    // Golden token (chaos pickup), drawn above the runner so the prize reads as
    // a falling collectible the player races to line up under.
    final tok = t.alive ? t.tokens.token : null;
    if (tok != null) {
      t.tokens.render(canvas, t.lanes.coordOf(tok.lane), animClock);
    }

    // Falling hazards (on top of the runner so a near-hit reads as overlap).
    for (final h in t.hazards) {
      final spin = h.spinPhase + animClock * _spinPerSec * h.speedMul;
      FallingRenderer.drawHazard(canvas, Offset(t.lanes.coordOf(h.lane), h.y),
          h.size, h.kind, t.runnerY, spin);
    }

    FallingRenderer.drawBandLabel(canvas, t.band, t.color, t.alive);
  }
}
