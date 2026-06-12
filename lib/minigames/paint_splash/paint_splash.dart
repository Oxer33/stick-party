import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/fx/particles.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/area_fill_grid.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'paint_render.dart';

/// Numeric tuning — no magic numbers inline. Times in seconds; positions and
/// speeds are in normalized 0..1 arena space unless noted.
class _Tuning {
  static const int cols = 30;
  static const int rows = 38;
  static const double timeLimit = 30;

  // ── Steering (the heart of the control) ───────────────────────────────────
  // The cursor chases the player's touch with an exponential ease so a drag
  // reads as a fluid brush stroke rather than a teleport. Speed is in "follow
  // fraction per second" via 1-exp(-k*dt), so it is frame-rate independent.
  static const double followPerSec = 14.0; // cursor → touch chase speed
  static const double botMoveSpeed = 0.62; // bot cursor travel (units/sec)

  // ── Continuous spray ──────────────────────────────────────────────────────
  // Holding sprays a fresh splat every [spraySec]; a quick tap always lays at
  // least one. Spraying COSTS ink (see the reserve below), so you cannot just
  // hold forever — the skill is pacing bursts and aiming them at fresh turf.
  static const double spraySec = 0.085; // seconds between continuous splats
  static const double touchIdleTimeout = 0.18; // stop spraying after touch lull

  // ── INK RESERVE (the decision that interposes) ─────────────────────────────
  // Every brush carries a limited reserve of ink in 0..1. Each splat spends
  // [inkPerSplat]; ink ONLY refills while the brush is NOT spraying
  // ([inkRechargePerSec]), so a held finger drains the can and then SPUTTERS
  // (dud splats that paint nothing). The winning rhythm is short aimed bursts
  // with little release gaps — NOT one endless hold.
  //
  // The wasted-paint surcharge is the targeting lever: a splat that lands mostly
  // on cells you ALREADY own (sitting on one spot, repainting home) costs up to
  // [inkWasteSurcharge]× extra, so it empties the can for almost no new ground.
  // Sweeping the brush onto FRESH or RIVAL cells keeps every splat ink-cheap,
  // so a player who manages ink + targets contested turf paints far more area
  // than one who blindly holds and wiggles in place.
  static const double inkPerSplat = 0.055; // base ink a splat spends
  static const double inkRechargePerSec = 0.42; // refill rate while not spraying
  static const double inkWasteSurcharge = 1.6; // extra ink mult for a fully-wasted splat
  static const double inkSputterFloor = 0.06; // below this the can only sputters
  static const double inkLowWarn = 0.22; // ring shows a low-ink warning here

  // A sputtering (near-empty) splat is a feeble dud: a tiny radius that paints
  // almost nothing, so over-holding visibly stops growing your coverage.
  static const double sputterRadius = 0.012;

  // ── Splat sizing ──────────────────────────────────────────────────────────
  // A held, moving brush lays a steady mid-size splat. There is deliberately NO
  // "sit still to grow it" bonus — lingering wastes ink instead — so coverage is
  // won by sweeping the brush across fresh canvas, not by parking it.
  static const double splatRadiusBase = 0.066;
  static const double splatRadiusMax = 0.12; // hard cap so it stays readable

  // ── Climax: the DOUBLE INK final burst (the unmistakable peak) ──────────────
  // For the last [doubleInkSec] the ink economy is supercharged: splats cost
  // nothing, the can stays full and every splat is fattened by
  // [doubleInkRadiusMult] (capped above the normal max) and throws extra
  // droplets — so the board churns wildly and a trailing kid can flip it in a
  // shouting finish. A one-shot banner + flash + shake announces it.
  static const double doubleInkSec = 6.0; // length of the double-ink finale
  static const double doubleInkRadiusMult = 1.7; // splat radius multiplier
  static const double doubleInkRadiusMax = 0.20; // raised cap during the burst
  static const int doubleInkExtraDroplets = 8; // bonus droplets per splat

  // Decisive-flip cue: when the lead changes hands during the finale we punch a
  // slow-mo + flash + popup so the moment the board flips reads as huge. Re-arms
  // after a short cooldown so a frantic back-and-forth keeps popping.
  static const double leadFlipSlowMoSec = 0.5;
  static const double leadFlipSlowScale = 0.45;
  static const double leadFlipCooldownSec = 0.7;
  static const double leadFlipMinFrac = 0.02; // ignore dead-heat jitter

  // Bot accuracy: an off-target splat is jittered by up to this (norm units),
  // scaled down by accuracy so better bots place paint where they aim.
  static const double botAimJitter = 0.05;

  // Bots stay passive for a beat so they never out-paint an idle human at the
  // gun; then they engage on a beatable cadence governed by [BotProfile].
  static const double botWarmupSec = 1.5;

  // Shared-canvas raiding: when a bot is trailing the current leader it is
  // biased to hunt cells the LEADER owns (paint over them to steal turf) instead
  // of just filling empty space, so bots fight for the contested board rather
  // than politely staying home. The chance ramps with how far behind they are.
  static const double botRaidChanceMax = 0.7; // max odds a goal targets leader
  static const double botRaidRefGap = 0.18; // coverage gap (frac) for full odds
  static const double botLeaderCellWeight = 1.4; // pull toward a leader's cell

  // Bot ink discipline: a skilled bot RELEASES the trigger to refill once its
  // can runs low and only re-engages once it has recovered, just like a good
  // human. A sloppy bot keeps the trigger mashed and sputters on empty. The
  // accuracy term decides how disciplined the bot is.
  static const double botInkReleaseAcc = 0.7; // accuracy at/above which a bot paces ink
  static const double botInkLowFrac = 0.18; // disciplined bot releases below this
  static const double botInkResumeFrac = 0.6; // …and resumes once refilled past this

  // Visual stamp budget: only the most recent stamps are drawn crisply on top
  // of the baked coverage tint, which protects render cost in long games.
  static const int maxStamps = 80;

  // Particle feel.
  static const int dropletCountBase = 6;
  static const double dropletSpeed = 300; // px/s
  static const double dropletGravity = 520;
  static const double dropletLife = 0.5;
  static const double dropletSizeBase = 5;
  static const double dropletSizePerRadius = 26; // size add / normalized radius

  // Stamp sheen dry-out time.
  static const double sheenDrySec = 1.2;

  // Bot target search: sample stride over the grid's cells when hunting the
  // best target (every cell is overkill for a coarse target).
  static const int botSampleStride = 1;

  // Mascot: per-frame brush travel (norm units) above which the rider runs.
  static const double mascotMoveThreshold = 0.0015;
}

/// A player's paint cursor. Unlike the old auto-bouncing reticle, this is driven
/// entirely by the player: it eases toward wherever they touch on the SHARED
/// canvas, and sprays continuously while a touch is held — but only while there
/// is ink in the can. Position is in normalized 0..1 arena space. Mutable,
/// round-scoped value.
class _Cursor {
  final int playerId;
  final Color color;
  final bool isRoller; // visual tool variety (odd ids use a roller)
  final Rect zone; // this player's home region (normalized arena space)
  final ReactionClock? clock; // bots re-pick a target on this cadence

  /// The painter mascot riding this brush (purely visual; reacts to motion +
  /// spray + win). Owns its own pose/anim clock, advanced each frame.
  final StickFigure figure;

  Offset pos; // where the brush currently is
  Offset target; // where it is steering toward (clamped into arena)
  bool spraying = false; // a touch (or bot intent) is currently held
  double sprayAccum = 0; // time banked toward the next continuous splat
  double sinceTouch = 1e9; // seconds since the last steering input (human)
  double ink = 1.0; // 0..1 remaining paint reserve
  bool sputter = false; // last splat fired on empty (a feeble dud)
  bool botPaused = false; // a disciplined bot is releasing to refill
  double flash = 0; // recent-splat flash timer (visual)
  Offset _botGoal; // bot's current coverage goal (normalized)
  Offset _prevPos; // last frame's position, to read motion for the mascot loco
  bool _facingRight = true; // mascot facing, flipped by horizontal travel

  _Cursor({
    required this.playerId,
    required this.color,
    required this.isRoller,
    required this.zone,
    required this.pos,
    required this.figure,
    this.clock,
  })  : target = pos,
        _botGoal = pos,
        _prevPos = pos;

  /// Drive the mascot's locomotion + facing from how far the brush moved this
  /// frame, and advance its animation clock. Purely visual — no sim effect.
  /// [moveNormThreshold] is the per-frame travel (norm units) above which the
  /// painter reads as running rather than idling.
  void updateMascot(double dt, double moveNormThreshold) {
    final delta = pos - _prevPos;
    final moved = delta.distance;
    if (moved > moveNormThreshold) {
      figure.setLoco(LocoState.run);
      if (delta.dx.abs() > moveNormThreshold * 0.5) {
        _facingRight = delta.dx >= 0;
      }
    } else {
      figure.setLoco(LocoState.idle);
    }
    _prevPos = pos;
    figure.update(dt);
  }

  bool get facingRight => _facingRight;

  bool get isBot => clock != null;

  /// Clamp a normalized point into the SHARED arena `[inset, 1-inset]^2`.
  ///
  /// This is the structural heart of the redesign: brushes are NOT walled into
  /// their own [zone] — every cursor roams the whole canvas, so painting over a
  /// rival's cells (last-writer-wins in [AreaFillGrid.paintCircleDelta]) STEALS
  /// them, turning coverage into a live tug-of-war. Each player still STARTS in
  /// their own corner (see [_spawnCursors]); [zone] is now only a starting/home
  /// hint for bots and a faint render label, not a barrier.
  Offset clampToZone(Offset p) {
    const inset = 0.005;
    return Offset(
      p.dx.clamp(inset, 1 - inset),
      p.dy.clamp(inset, 1 - inset),
    );
  }

  /// Steer the brush toward [target] with a frame-rate-independent ease. [dt] is
  /// sim seconds.
  void steer(double dt) {
    final follow = (1.0 - math.exp(-_Tuning.followPerSec * dt)).clamp(0.0, 1.0);
    pos = Offset(
      pos.dx + (target.dx - pos.dx) * follow,
      pos.dy + (target.dy - pos.dy) * follow,
    );
  }

  /// Advance timers (flash). [dt] is real seconds.
  void tickTimers(double dt) {
    if (flash > 0) flash = math.max(0, flash - dt);
  }

  /// Refill the can while the trigger is up; spend nothing while held (splats
  /// debit it directly). During the finale the can stays full so the climax can
  /// churn freely. [dt] is sim seconds.
  void rechargeInk(double dt, {required bool freeFlow}) {
    if (freeFlow) {
      ink = 1.0;
      return;
    }
    if (!spraying) {
      ink = math.min(1.0, ink + _Tuning.inkRechargePerSec * dt);
    }
  }

  /// Spend ink for one splat, charging a waste surcharge proportional to how
  /// much of the stroke merely re-coated cells the player already owned. During
  /// the finale ink is free. Ink is clamped at 0.
  void spendInk(double wasteFraction, {required bool freeFlow}) {
    if (freeFlow) return;
    final surcharge =
        1.0 + _Tuning.inkWasteSurcharge * wasteFraction.clamp(0.0, 1.0);
    ink = math.max(0.0, ink - _Tuning.inkPerSplat * surcharge);
  }

  /// True when the can is too low to lay a real splat (it only sputters).
  bool get isEmpty => ink < _Tuning.inkSputterFloor;

  Offset get botGoal => _botGoal;
  set botGoal(Offset g) => _botGoal = clampToZone(g);

  /// 0..1 "charge" readout for the cursor ring — the remaining ink, so the brush
  /// visibly shows how much paint is left before it sputters.
  double get charge => ink.clamp(0.0, 1.0);
}

/// A drawn paint stamp recorded when a splat lands, so the renderer can paint a
/// crisp irregular blob (with drips/droplets) on top of the baked coverage
/// tint. Round-scoped; capped to [_Tuning.maxStamps].
class _Stamp {
  final Offset pos; // normalized 0..1
  final double radius; // normalized
  final Color color;
  final int seed; // deterministic visual variation
  double age = 0; // seconds since it landed (drives sheen/droplet fade)

  _Stamp({
    required this.pos,
    required this.radius,
    required this.color,
    required this.seed,
  });
}

/// Paint Splash — a splatter-paint turf war on ONE SHARED [AreaFillGrid].
///
/// OBJECTIVE (obvious, kid-readable): own the most canvas when the timer ends.
/// Score is the live owned-cell count, resolved via [finishByScore].
///
/// CONTROL (one touch, full agency, ONE canvas):
///  * Every player drives a paint cursor over the WHOLE arena. The cursor STEERS
///    to wherever the player touches: drag to move the brush anywhere. Players
///    START in their own corner so setup reads, then the board is open.
///  * HOLDING sprays paint continuously at the cursor. Because paint is
///    last-writer-wins, sweeping your brush OVER a rival's color FLIPS those
///    cells to you — you steal their turf, and they can steal it right back.
///
/// THE DECISION THAT INTERPOSES (why blind holding LOSES): every brush has a
/// limited INK reserve. Spraying drains it; it only refills while the trigger is
/// UP. Hold forever and the can empties and SPUTTERS (dud splats that paint
/// nothing). Worse, a splat that lands on cells you ALREADY own costs extra ink
/// for no new ground — so sitting on one spot drains the can for nothing. The
/// player who paces short bursts and aims them at FRESH or RIVAL turf paints far
/// more than the one who holds and wiggles blindly.
///
/// Bots roam the shared canvas: they head for the largest pocket they don't own
/// and, when behind, RAID the current leader's territory (painting over it to
/// steal cells), re-picking a goal on a [ReactionClock]. A SKILLED bot also
/// paces its ink (releases to refill when low); a sloppy bot mashes the trigger
/// and sputters. [BotProfile] accuracy decides discipline + aim, so easy bots
/// leave coverage a human can out-paint. A short warmup keeps them passive at
/// the gun.
class PaintSplash extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'paint_splash',
        name: 'Paint Splash',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'HOLD',
      );

  late Juice _juice;
  late AreaFillGrid _grid;
  final List<_Cursor> _cursors = <_Cursor>[];
  final List<_Stamp> _stamps = <_Stamp>[];
  double _elapsed = 0;
  int _splatSeq = 0; // monotonically increasing seed source for stamps
  bool _doubleInkAnnounced = false; // the DOUBLE INK cue fired once
  int? _lastLeaderId; // leader tracked frame-to-frame for the flip cue
  double _flipCooldown = 0; // re-arm timer for the decisive-flip punch
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _grid = AreaFillGrid(cols: _Tuning.cols, rows: _Tuning.rows);
    _spawnCursors();
    begin();
  }

  void _spawnCursors() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final zone = ctx.zones.forPlayer(p.id)?.normRect ??
          _fallbackZone(i, count); // robustness if zones are missing
      final start = zone.center;
      final color = Color(p.colorArgb);
      _cursors.add(_Cursor(
        playerId: p.id,
        color: color,
        isRoller: p.id.isOdd,
        zone: zone,
        pos: start,
        figure: StickFigure(style: _mascotStyle(color))
          ..setLoco(LocoState.idle),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// Bright painter-mascot style in the player's color: color fill, brightened
  /// neon outline, soft glow. Mirrors the sprinter style in tap_sprint so the
  /// cast reads consistently across games.
  StickStyle _mascotStyle(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 4,
        lineWidth: 1.0,
        rimAlpha: 0.28,
        shadowAlpha: 0.0, // the renderer draws its own contact shadow
        gradientBottom: 0.55,
      );

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  /// Horizontal-strip fallback so the game still works if a context arrives
  /// without a matching zone for a player id.
  Rect _fallbackZone(int index, int count) {
    final h = 1.0 / count;
    return Rect.fromLTRB(0, index * h, 1, (index + 1) * h);
  }

  // ── Input: steer to touch + spray while held ────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final c = _cursorOf(input.playerId);
    if (c == null) return;

    switch (input.phase) {
      case InputPhase.down:
        _steerTo(c, input.normPos);
        c.spraying = true;
        c.sprayAccum = _Tuning.spraySec; // lay the first splat immediately
      case InputPhase.holdTick:
        // A move sample carries a position; a pure per-frame held tick carries
        // only dt (normPos == Offset.zero) and just keeps the spray flowing.
        if (input.normPos != Offset.zero) _steerTo(c, input.normPos);
        c.spraying = true;
        // Any held tick is proof the finger is still down, so refresh the
        // idle-touch timer. Without this a stationary held finger (which emits
        // only positionless per-frame ticks) would trip the idle timeout in
        // update() after touchIdleTimeout and stop spraying mid-hold.
        c.sinceTouch = 0;
      case InputPhase.up:
        c.spraying = false;
    }
  }

  /// Point the cursor's steering target at [normPos] (full-screen), clamped only
  /// to the shared arena bounds so the brush can roam (and steal) anywhere.
  /// Resets the idle-touch timer so the continuous spray keeps running.
  void _steerTo(_Cursor c, Offset normPos) {
    if (!normPos.dx.isFinite || !normPos.dy.isFinite) return;
    c.target = c.clampToZone(normPos);
    c.sinceTouch = 0;
  }

  /// Lay paint for [c] centered at its current position.
  ///
  /// This is where the ink economy bites:
  ///  * If the can is empty the splat SPUTTERS — a feeble dud that paints almost
  ///    nothing and spends no further ink, so over-holding visibly stalls.
  ///  * Otherwise it paints the grid (last writer wins) and is charged ink with
  ///    a surcharge for how much of the stroke merely re-coated cells [c]
  ///    already owned (the wasted fraction), so parking on one spot drains fast.
  /// Records a visual stamp and fires juice scaled by what the stroke won.
  void _spray(_Cursor c) {
    final at = c.pos;
    if (!at.dx.isFinite || !at.dy.isFinite) return;
    final freeFlow = _inDoubleInk;

    // Empty can → sputter: a tiny dud blob, no grid paint, no further drain.
    if (!freeFlow && c.isEmpty) {
      c.sputter = true;
      c.flash = _Tuning.spraySec * 2;
      _recordStamp(at, _Tuning.sputterRadius, c.color);
      // A couple of dribble droplets sell the empty-can splutter.
      _juice.particles.burst(
        at: _toPixels(at),
        count: 3,
        color: c.color,
        speed: _Tuning.dropletSpeed * 0.4,
        size: _Tuning.dropletSizeBase * 0.6,
        gravity: _Tuning.dropletGravity,
        life: _Tuning.dropletLife * 0.6,
        shape: ParticleShape.circle,
      );
      return;
    }

    c.sputter = false;
    c.flash = _Tuning.spraySec * 2;
    final radius = _splatRadius(c);
    final result = _grid.paintCircleDelta(c.playerId, at, radius);
    // Waste fraction = how much of the stroke fell on cells we already owned.
    final wasteFraction =
        result.touched == 0 ? 1.0 : result.wasted / result.touched;
    c.spendInk(wasteFraction, freeFlow: freeFlow);
    _recordStamp(at, radius, c.color);
    _burstDroplets(at, radius, c.color, result.stolen);
    // The mascot swings its arm on each splat so it visibly paints.
    c.figure.attack(0);
  }

  /// True once the round enters its final DOUBLE INK burst window.
  bool get _inDoubleInk => _elapsed >= _Tuning.timeLimit - _Tuning.doubleInkSec;

  /// Splat radius from the base size. During the DOUBLE INK finale the radius is
  /// multiplied and allowed past the normal cap (up to the raised burst cap) so
  /// the bigger paint is unmistakable.
  double _splatRadius(_Cursor c) {
    if (_inDoubleInk) {
      return (_Tuning.splatRadiusBase * _Tuning.doubleInkRadiusMult)
          .clamp(_Tuning.splatRadiusBase, _Tuning.doubleInkRadiusMax);
    }
    return _Tuning.splatRadiusBase.clamp(0.0, _Tuning.splatRadiusMax);
  }

  void _recordStamp(Offset at, double radius, Color color) {
    _stamps.add(_Stamp(
      pos: at,
      radius: radius,
      color: color,
      seed: _splatSeq++,
    ));
    // Keep only the most recent stamps drawn crisply (the rest live on as the
    // baked coverage tint), protecting render cost in long games.
    if (_stamps.length > _Tuning.maxStamps) {
      _stamps.removeRange(0, _stamps.length - _Tuning.maxStamps);
    }
  }

  /// A burst of paint droplets + impact feel. A splat that STEALS rival cells
  /// throws more droplets and a touch more shake — the satisfying raid feedback.
  void _burstDroplets(Offset at, double radius, Color color, int stolen) {
    final px = _toPixels(at);
    final stealKick = math.min(stolen, 10);
    final count = _Tuning.dropletCountBase +
        stealKick +
        (_inDoubleInk ? _Tuning.doubleInkExtraDroplets : 0);
    _juice.particles.burst(
      at: px,
      count: count,
      color: color,
      speed: _Tuning.dropletSpeed *
          (0.8 + 0.2 * (radius / _Tuning.splatRadiusMax)),
      size: _Tuning.dropletSizeBase + radius * _Tuning.dropletSizePerRadius,
      gravity: _Tuning.dropletGravity,
      life: _Tuning.dropletLife,
      shape: ParticleShape.circle,
    );
    if (stolen > 4) _juice.shake.light();
  }

  /// Fire the one-shot DOUBLE INK cue the instant the finale window opens: a big
  /// banner, a screen flash, a shake and a bright burst so every kid knows the
  /// paint just went huge and unlimited — time to scribble for the win.
  void _maybeAnnounceDoubleInk() {
    if (_doubleInkAnnounced || !_inDoubleInk) return;
    _doubleInkAnnounced = true;
    final center = Offset(_lastSize.width / 2, _lastSize.height * 0.5);
    _juice.bigBanner('DOUBLE INK!', color: const Color(0xFFFFFFFF));
    _juice.flashScreen(const Color(0xFFFFFFFF), strength: 0.45);
    _juice.shake.medium();
    _juice.particles.burst(
      at: center,
      count: 24,
      color: const Color(0xFFFFFFFF),
      speed: 360,
      size: 7,
      life: 0.7,
    );
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);
    if (_flipCooldown > 0) _flipCooldown = math.max(0, _flipCooldown - dt);

    _maybeAnnounceDoubleInk();
    _driveBots(sdt);

    final freeFlow = _inDoubleInk;
    for (final c in _cursors) {
      c.sinceTouch += dt;
      // A human cursor whose touch went quiet stops spraying (finger lifted or
      // the up event was missed); bots manage their own [spraying] flag.
      if (!c.isBot && c.sinceTouch > _Tuning.touchIdleTimeout) {
        c.spraying = false;
      }
      c.steer(sdt);
      c.tickTimers(dt);
      c.rechargeInk(sdt, freeFlow: freeFlow);
      _tickSpray(c, sdt);
      // Advance the painter mascot: run while the brush travels, idle when still.
      c.updateMascot(sdt, _Tuning.mascotMoveThreshold);
    }
    for (final s in _stamps) {
      s.age += dt;
    }

    _maybeAnnounceLeadFlip();

    if (_elapsed >= _Tuning.timeLimit) _finish();
  }

  /// Emit continuous splats while a cursor is spraying: bank time and lay one
  /// splat per [_Tuning.spraySec], with a guard so a huge frame can't dump a
  /// hundred splats at once.
  void _tickSpray(_Cursor c, double dt) {
    if (!c.spraying) {
      c.sprayAccum = 0;
      return;
    }
    c.sprayAccum += dt;
    var guard = 0;
    while (c.sprayAccum >= _Tuning.spraySec && guard++ < 6) {
      c.sprayAccum -= _Tuning.spraySec;
      _spray(c);
    }
  }

  /// Watch for the lead changing hands during the DOUBLE INK finale and punch a
  /// slow-mo + flash + popup on the decisive flip so the moment the board turns
  /// over reads as the climax it is. Only fires in the finale (when swings are
  /// big), needs a real coverage lead (not dead-heat jitter), and re-arms after
  /// a short cooldown so a frantic back-and-forth keeps popping.
  void _maybeAnnounceLeadFlip() {
    final leader = _leaderId();
    final prev = _lastLeaderId;
    _lastLeaderId = leader;
    if (!_inDoubleInk || leader == null || prev == null || leader == prev) {
      return;
    }
    if (_flipCooldown > 0) return;
    // Require a clear margin so micro-jitter at a tie doesn't spam the cue.
    final margin = _grid.fractionOf(leader) - _grid.fractionOf(prev);
    if (margin < _Tuning.leadFlipMinFrac) return;

    _flipCooldown = _Tuning.leadFlipCooldownSec;
    final color = _cursorOf(leader)?.color ?? const Color(0xFFFFFFFF);
    _juice.slowMo(
        dur: _Tuning.leadFlipSlowMoSec, scale: _Tuning.leadFlipSlowScale);
    _juice.flashScreen(color, strength: 0.4);
    _juice.shake.medium();
    final center = Offset(_lastSize.width / 2, _lastSize.height * 0.42);
    _juice.popup(center, 'LEAD FLIP!', color, size: 40);
  }

  /// Bots roam the SHARED canvas, heading for the largest pocket they don't own
  /// and (when behind) raiding the leader's turf. They re-pick a goal on their
  /// reaction clock; [BotProfile] accuracy tightens the goal and decides ink
  /// discipline. A warmup keeps them passive at the gun so an idle human is
  /// never buried.
  void _driveBots(double dt) {
    final engaged = _elapsed >= _Tuning.botWarmupSec;
    final freeFlow = _inDoubleInk;
    for (final c in _cursors) {
      final clock = c.clock;
      if (clock == null) continue;
      if (!engaged) {
        c.spraying = false;
        continue;
      }
      _updateBotTrigger(c, freeFlow: freeFlow);
      if (clock.tick(dt)) {
        clock.arm(ctx.botProfile, ctx.rng);
        _repickBotGoal(c);
      }
      _stepBotCursor(c, dt);
    }
  }

  /// Decide whether a bot holds the trigger this frame, modeling ink discipline.
  ///
  /// A DISCIPLINED bot (accuracy ≥ [_Tuning.botInkReleaseAcc]) behaves like a
  /// good human: it releases the trigger to refill once its can runs low
  /// ([_Tuning.botInkLowFrac]) and only re-engages once recovered past
  /// [_Tuning.botInkResumeFrac], so its ink stays efficient. A SLOPPY bot just
  /// holds the trigger down and sputters on empty, wasting paint exactly like a
  /// blind human — which is what makes easy bots beatable. During the free-flow
  /// finale everyone simply holds.
  void _updateBotTrigger(_Cursor c, {required bool freeFlow}) {
    if (freeFlow) {
      c.botPaused = false;
      c.spraying = true;
      return;
    }
    final disciplined = ctx.botProfile.accuracy >= _Tuning.botInkReleaseAcc;
    if (!disciplined) {
      c.botPaused = false;
      c.spraying = true; // mashes the trigger, sputters when empty
      return;
    }
    if (c.botPaused) {
      // Refilling — resume once the can has recovered enough for a clean burst.
      if (c.ink >= _Tuning.botInkResumeFrac) c.botPaused = false;
    } else if (c.ink <= _Tuning.botInkLowFrac) {
      c.botPaused = true; // release to refill before it sputters
    }
    c.spraying = !c.botPaused;
  }

  /// Choose a fresh coverage goal for a bot on the SHARED canvas. Usually the
  /// centre of the best target cell ([_bestTargetSpot]); occasionally a random
  /// spot anywhere on the board on a deliberate error. Aim jitter (scaled by
  /// 1 - accuracy) keeps weak bots from nailing the optimum.
  void _repickBotGoal(_Cursor c) {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    Offset goal;
    if (ctx.rng.chance(ctx.botProfile.errorRate)) {
      // Drift to a random point anywhere on the shared arena (not just home).
      goal = Offset(ctx.rng.next(), ctx.rng.next());
    } else {
      goal = _bestTargetSpot(c) ?? c.zone.center;
      final jitter = _Tuning.botAimJitter * (1.0 - acc);
      if (jitter > 0) {
        goal = goal.translate(ctx.rng.jitter(jitter), ctx.rng.jitter(jitter));
      }
    }
    c.botGoal = goal;
  }

  /// Pick the best cell on the WHOLE shared grid for bot [c] to head toward.
  ///
  /// Cells the bot already owns are skipped (re-coating wastes ink), so bots
  /// naturally chase FRESH ground — the same discipline a human needs. Empty
  /// cells are the staple target; rival cells are worth taking too (stealing).
  /// When the bot is BEHIND the leader it rolls (odds scaling with the gap, up
  /// to [_Tuning.botRaidChanceMax]) to go on a raid: in raid mode the LEADER's
  /// cells get an extra pull ([_Tuning.botLeaderCellWeight]) so the bot drives
  /// into the leader's turf and paints over it. A mild distance term keeps it
  /// sweeping outward rather than dithering. Returns null only if the bot
  /// already owns every cell.
  Offset? _bestTargetSpot(_Cursor c) {
    final leaderId = _leaderId();
    final behind = _coverageGapBehindLeader(c.playerId, leaderId);
    final raidT = (behind / _Tuning.botRaidRefGap).clamp(0.0, 1.0);
    final raiding = leaderId != null &&
        leaderId != c.playerId &&
        ctx.rng.chance(_Tuning.botRaidChanceMax * raidT);

    Offset? best;
    var bestScore = -1.0;
    for (var row = 0; row < _Tuning.rows; row += _Tuning.botSampleStride) {
      final cy = (row + 0.5) / _Tuning.rows;
      for (var col = 0; col < _Tuning.cols; col += _Tuning.botSampleStride) {
        final owner = _grid.ownerAt(col, row);
        if (owner == c.playerId) continue; // already mine — skip (no waste)
        // Empty cells are the baseline target; rival cells are worth stealing.
        var weight = owner == kEmptyCell ? 1.0 : 0.6;
        // On a raid, the leader's cells are the juiciest steal.
        if (raiding && owner == leaderId) weight *= _Tuning.botLeaderCellWeight;
        final cx = (col + 0.5) / _Tuning.cols;
        final dist = (Offset(cx, cy) - c.pos).distance;
        final score = weight * (0.4 + dist);
        if (score > bestScore) {
          bestScore = score;
          best = Offset(cx, cy);
        }
      }
    }
    return best;
  }

  /// Id of the player currently owning the most cells, or null if nobody has
  /// painted yet (used to pick a raid target + drive the lead-flip cue).
  int? _leaderId() {
    int? leader;
    var bestCount = 0;
    for (final c in _cursors) {
      final n = _grid.coverageOf(c.playerId);
      if (n > bestCount) {
        bestCount = n;
        leader = c.playerId;
      }
    }
    return leader;
  }

  /// How far (coverage fraction) [playerId] trails [leaderId]; 0 if they ARE the
  /// leader or there is no leader yet.
  double _coverageGapBehindLeader(int playerId, int? leaderId) {
    if (leaderId == null || leaderId == playerId) return 0;
    final gap = _grid.fractionOf(leaderId) - _grid.fractionOf(playerId);
    return gap < 0 ? 0 : gap;
  }

  /// Move a bot's steering target toward its goal at a capped speed, then snap a
  /// fresh goal once it arrives so it keeps roaming and painting.
  void _stepBotCursor(_Cursor c, double dt) {
    final to = c.botGoal - c.target;
    final step = _Tuning.botMoveSpeed * dt;
    if (to.distance <= step || to.distance < 1e-4) {
      c.target = c.botGoal;
      _repickBotGoal(c);
    } else {
      c.target = c.clampToZone(c.target + to / to.distance * step);
    }
  }

  /// Score = covered cell count, then rank highest-first.
  void _finish() {
    if (status == MiniGameStatus.finished) return;
    for (final p in ctx.players) {
      setScore(p.id, _grid.coverageOf(p.id));
    }
    // Signature coverage-reveal beat: the biggest moment fires on the winner's
    // brush — burst + heavy shake + slow-mo + zoom-punch + flash + a WINNER!
    // banner in the leader's color, then winner-tinted confetti rains over the
    // finished board. The leader owns the most cells at the buzzer.
    final winnerId = _leaderId();
    final winnerColor = _leaderColor();
    final winnerPos = winnerId == null
        ? _lastSize.center(Offset.zero)
        : _toPixels(_cursorOf(winnerId)!.pos);
    _juice.bigMoment(winnerPos, winnerColor, banner: 'WINNER!');
    _juice.confetti(_lastSize, colors: [winnerColor]);
    // The winning painter cheers on the final board.
    if (winnerId != null) _cursorOf(winnerId)?.figure.victory();
    finishByScore();
  }

  /// The current leader's color for the win reveal, or white if nobody painted.
  Color _leaderColor() {
    final id = _leaderId();
    if (id == null) return const Color(0xFFFFFFFF);
    return _cursorOf(id)?.color ?? const Color(0xFFFFFFFF);
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    _juice.applyWorldTransform(canvas);

    PaintRenderer.drawBackground(canvas, size);
    _drawHomeCorners(canvas, size);
    _drawCoverage(canvas, size);
    _drawStamps(canvas, size);
    _drawCursors(canvas, size);
    _drawCoverageBars(canvas, size);

    _juice.render(canvas);
    canvas.restore();

    // Screen-space cinematic overlays (flash + WINNER! banner) after the world
    // transform is restored, so they are not shaken or zoomed. This is a
    // top-down board with no single focal point, so no zoom-punch is used.
    _juice.renderOverlay(canvas, size);
  }

  /// Faint player-tinted "home corner" washes (NOT walls): the canvas is shared
  /// and every brush roams it freely, so we only hint where each player starts.
  void _drawHomeCorners(Canvas canvas, Size size) {
    PaintRenderer.drawZoneBorders(canvas, size, [
      for (final c in _cursors) (rect: c.zone, color: c.color),
    ]);
  }

  /// Baked coverage under-layer (a soft tint per owned cell) so total territory
  /// reads clearly behind the crisp stamps.
  void _drawCoverage(Canvas canvas, Size size) {
    final colorById = <int, Color>{
      for (final p in ctx.players) p.id: Color(p.colorArgb),
    };
    PaintRenderer.drawCoverageTint(
      canvas,
      size,
      _Tuning.cols,
      _Tuning.rows,
      (col, row) {
        final owner = _grid.ownerAt(col, row);
        if (owner == kEmptyCell) return null;
        return colorById[owner];
      },
    );
  }

  /// The recent crisp blobs on top, oldest first so newer paint overlaps older.
  void _drawStamps(Canvas canvas, Size size) {
    if (_stamps.isEmpty) return;
    final minSide = math.min(size.width, size.height);
    for (final s in _stamps) {
      final center = _toPixelsIn(s.pos, size);
      final radiusPx = s.radius * minSide;
      // Sheen fades over ~sheenDrySec; droplet ring fades over the round.
      final wet = (1.0 - s.age / _Tuning.sheenDrySec).clamp(0.0, 1.0);
      final age01 = (s.age / _Tuning.timeLimit).clamp(0.0, 1.0);
      PaintRenderer.drawSplat(
        canvas,
        center,
        radiusPx,
        s.color,
        seed: s.seed,
        wet: wet,
        age01: age01,
      );
    }
  }

  void _drawCursors(Canvas canvas, Size size) {
    for (final c in _cursors) {
      final pulse = c.flash <= 0
          ? 0.0
          : (c.flash / (_Tuning.spraySec * 2)).clamp(0.0, 1.0);
      final center = _toPixelsIn(c.pos, size);
      // The ring reads as an INK GAUGE: charge is remaining ink, lowInk warns
      // when the can is nearly dry so a player knows to release and refill.
      PaintRenderer.drawReticle(
        canvas,
        size,
        center,
        c.color,
        charge: c.charge,
        isRoller: c.isRoller,
        pulse: pulse,
        spraying: c.spraying && !c.sputter,
        lowInk: c.ink < _Tuning.inkLowWarn,
      );
      // The painter mascot rides on top of the reticle, showing WHO is painting.
      PaintRenderer.drawMascot(
        canvas,
        size,
        center,
        c.figure,
        facingRight: c.facingRight,
      );
    }
  }

  /// Live coverage % bars; the current leader's bar glows.
  void _drawCoverageBars(Canvas canvas, Size size) {
    if (_cursors.isEmpty) return;
    var leaderId = _cursors.first.playerId;
    var leaderFrac = -1.0;
    for (final c in _cursors) {
      final f = _grid.fractionOf(c.playerId);
      if (f > leaderFrac) {
        leaderFrac = f;
        leaderId = c.playerId;
      }
    }
    final entries = <({Color color, double fraction, bool isLeader})>[
      for (final c in _cursors)
        (
          color: c.color,
          fraction: _grid.fractionOf(c.playerId),
          isLeader: c.playerId == leaderId && leaderFrac > 0,
        ),
    ];
    PaintRenderer.drawCoverageBars(canvas, size, entries);
  }

  // ── Small helpers ────────────────────────────────────────────────────────────

  _Cursor? _cursorOf(int id) {
    for (final c in _cursors) {
      if (c.playerId == id) return c;
    }
    return null;
  }

  Offset _toPixels(Offset norm) => _toPixelsIn(norm, _lastSize);

  Offset _toPixelsIn(Offset norm, Size size) =>
      Offset(norm.dx * size.width, norm.dy * size.height);
}
