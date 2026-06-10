import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/constants.dart';
import '../../core/math2.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'masher_render.dart';

/// Button Masher — a carnival "high striker" (test-your-strength) race with an
/// OVERHEAT gauge. Every player owns a strength tower; each tap swings their
/// little stickman's hammer onto the lever and feeds HEAT into the striker.
///
/// Depth — the real per-tap DECISION (still one-touch MASH):
///  * **Heat gauge / sweet-zone**: every tap adds heat; heat bleeds off when you
///    ease up. A tap only kicks the puck a FULL notch while heat sits in the
///    GREEN band. Mash past the redline into the RED overheat zone and a tap
///    gives almost nothing AND the puck DROPS — a wild masher boils over and
///    slides back down. So you tap fast to get hot, then *ease off the throttle*
///    to stay in the green: a steady, listening player out-climbs a button-mash.
///  * **Score = HEIGHT, not taps**: a player is scored by the highest the puck
///    ever reached ([_Striker.peakHeight]), so managing heat — not raw mash
///    count — wins. The bell at the top is the clear goal.
///  * **FRENZY finale + comeback assist**: the final stretch gives the climb an
///    extra shove (a swingy late rally) and a trailing player a gentle catch-up
///    boost, both shaped so they help you climb without rewarding a redline mash.
///
/// Kid read: keep the gauge GREEN, don't let it go RED. Tap-tap-tap… ease…
/// tap-tap. Bots ride the green band on a [BotProfile]-driven cadence (harder
/// tiers hold the sweet zone tighter), so the towers feel like a real scramble.
class ButtonMasher extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'button_masher',
        name: 'Button Masher',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'MASH',
      );

  // ── Round tuning (no magic numbers inline) ──────────────────────────────────
  static const double _timeLimit = 10;
  static const int _levels = 12; // lit strength rungs on each tower
  // peakHeight is 0..1; scale it to a tidy integer score so the HUD reads big.
  static const double _scorePerHeight = 1000;

  // ── Heat gauge (the sweet-zone DECISION) ────────────────────────────────────
  // Heat 0..1. Each tap shoves it up; it bleeds down when you ease off. The puck
  // only climbs at full strength while heat is inside the GREEN band; below the
  // band a tap is a weak warm-up nudge, and ABOVE the redline the striker has
  // boiled over — taps stop climbing and the puck slides back down.
  static const double _heatPerTap = 0.13; // heat added per tap
  static const double _heatDecayPerSec = 0.55; // bleeds when you slack off
  static const double _heatGreenLo = 0.45; // green band lower edge
  static const double _heatGreenHi = 0.82; // green band upper edge (redline)
  // Below-green taps still nudge the puck a little so a timid player climbs
  // slowly instead of being stuck at zero (kid-forgiving warm-up).
  static const double _coldKickFrac = 0.4;
  // Overheated taps give almost nothing — the climb essentially stalls in red.
  static const double _overheatKickFrac = 0.06;

  // ── Puck climb ──────────────────────────────────────────────────────────────
  static const double _baseKickPerTap = 0.05; // puck height per green tap
  static const double _puckGravityPerSec = 0.16; // puck eases back down if idle
  // While overheated the puck doesn't just idle-bleed — it actively DROPS faster
  // (reuses the same gravity unit, scaled up) so boiling over is clearly costly.
  static const double _overheatDropMult = 2.2;
  static const double _puckSpringPerSec = 14.0; // puck chases its target height

  // ── Hammer swing (per tap) ──────────────────────────────────────────────────
  static const double _swingSec = 0.18; // one hammer down-stroke duration

  // ── Tap feedback ────────────────────────────────────────────────────────────
  static const double _flashLifeSec = 0.22; // tap flash ring life
  static const int _maxFlashes = 6; // flashes kept per striker

  // ── FRENZY climax ─────────────────────────────────────────────────────────
  // In the final stretch a green tap kicks the puck harder (a finale climb
  // surge) with a one-shot "FRENZY!" banner + shake, so the last seconds are a
  // swingy scramble where a late, well-managed rally can still steal the win.
  static const double _frenzyFrac = 0.75; // fraction of timeLimit → frenzy begins
  static const double _frenzyKickBoost = 0.6; // +60% green-tap climb during frenzy

  // ── Comeback (kid-assist) ────────────────────────────────────────────────────
  // A player whose puck sits below the leader's peak gets a small climb boost on
  // a GREEN tap, scaled by the height gap — keeps a trailing kid's tower rising
  // without ever rewarding a redline mash (the assist rides the same green tap).
  static const double _catchUpMaxBoost = 0.6; // +60% green climb at full gap
  static const double _catchUpGapFull = 0.5; // peak-height gap for the full boost

  // ── Bot mash cadence (sec/tap); harder bots ride the green band tighter ─────
  static const double _botBaseInterval = 0.16;
  static const double _botAccuracyBonus = 0.05; // faster at high accuracy
  static const double _botJitterBase = 0.05; // sloppier at low accuracy
  // A bot eases off the throttle when its own heat climbs near the redline, so a
  // strong bot hovers in the green instead of boiling over — its skill reads as
  // "holds the sweet zone". Weaker bots react later (higher trigger) so they
  // overheat more, mirroring a wild human masher.
  static const double _botEaseHeatBase = 0.7; // heat at which a bot starts easing
  static const double _botEasePause = 0.22; // sec a bot waits while it cools
  // Bots wait a beat before they start hammering so a human gets a fair head
  // start and an idle player is never instantly buried at the gun.
  static const double _botWarmupSec = 1.5;

  late Juice _juice;
  late Size _size;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock (never scaled) for bg shimmer
  bool _frenzyFired = false; // one-shot "FRENZY!" climax cue latch

  final Map<int, _Striker> _strikers = <int, _Striker>{};
  // Lane layout depends only on the (fixed) arena + roster, so build it once at
  // init rather than re-allocating the whole map every frame AND every tap
  // (bots tap many times a second, so the per-tap rebuild was the hot path).
  late final Map<int, _Lane> _laneByPlayer;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _laneByPlayer = _lanes(_size);

    final proportions = _strikerProportions();
    // Legs are near-vertical at rest, so pelvis→foot ≈ thigh + shin.
    final footReach = proportions.thigh + proportions.shin;

    for (final p in ctx.players) {
      _strikers[p.id] = _Striker(
        slot: p,
        figure: StickFigure(
          proportions: proportions,
          style: _styleFor(Color(p.colorArgb)),
          facing: 1,
        )..setLoco(LocoState.idle),
        footReach: footReach,
        botInterval: _botInterval(),
        botJitter: _botJitter(),
        botEaseHeat: _botEaseHeat(),
      );
    }
    begin();
  }

  /// Stocky carnival build derived from the hero proportions — scaled up so the
  /// hammer-swinging striker reads clearly at the foot of its tower.
  StickProportions _strikerProportions() => StickProportions.hero.scaled(1.9);

  /// Bright player style: color fill, brightened outline, strong glow. We draw
  /// our own contact shadow so the figure's own ground shadow is disabled.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        rimAlpha: 0.3,
        shadowAlpha: 0.0,
        gradientBottom: 0.55,
        smearAlpha: 0.28,
      );

  double _botInterval() {
    final prof = ctx.botProfile;
    return math.max(0.05, _botBaseInterval - _botAccuracyBonus * prof.accuracy);
  }

  /// Sloppier (more jitter) at low accuracy so weak bots stutter and strong
  /// bots stay metronomic.
  double _botJitter() {
    final prof = ctx.botProfile;
    return _botJitterBase * (1.0 - prof.accuracy.clamp(0.0, 1.0)) +
        _botJitterBase * 0.25;
  }

  /// The heat at which a bot eases off to cool down. A high-accuracy bot eases
  /// early (just under the redline) so it rides the green; a low-accuracy bot
  /// eases late (or past the line) so it boils over like a wild masher.
  double _botEaseHeat() {
    final prof = ctx.botProfile;
    // accuracy 1 → ease at the green ceiling; accuracy 0 → ease well into red.
    return _botEaseHeatBase + (1.0 - prof.accuracy.clamp(0.0, 1.0)) * 0.25;
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _tap(input.playerId);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _maybeFireFrenzy();
    _driveBots(sdt);

    for (final s in _strikers.values) {
      _tickStriker(s, sdt);
      // Score = HEIGHT reached (×scale, rounded). Managing heat — not raw mash
      // count — drives the climb, so a steady player out-scores a spammer.
      setScore(s.slot.id, (s.peakHeight * _scorePerHeight).round());
    }

    if (_elapsed >= _timeLimit) {
      finishByScore(); // most height (≡ best heat management) wins
    }
  }

  /// True once the round enters the final stretch — green taps climb harder so
  /// the finale is a swingy scramble.
  bool get _inFrenzy => _elapsed >= _timeLimit * _frenzyFrac;

  /// Fire the one-shot "FRENZY!" climax cue over the towers when frenzy begins.
  void _maybeFireFrenzy() {
    if (_frenzyFired || !_inFrenzy) return;
    _frenzyFired = true;
    _juice.popup(
      Offset(_size.width / 2, _size.height * 0.16),
      'FRENZY!',
      MasherRenderer.bellGold,
      size: 40,
    );
    _juice.shake.medium();
  }

  void _tickStriker(_Striker s, double dt) {
    // Heat bleeds off so you must keep tapping to stay hot — but easing off is
    // exactly how you drop OUT of the red back into the green.
    s.heat = math.max(0.0, s.heat - _heatDecayPerSec * dt);

    // Puck eases toward its target. While overheated it drops faster (an active
    // boil-over slide), otherwise it just idle-bleeds toward the target.
    final drop = _isOverheated(s.heat)
        ? _puckGravityPerSec * _overheatDropMult
        : _puckGravityPerSec;
    s.targetHeight = math.max(0.0, s.targetHeight - drop * dt);
    final follow = (1.0 - math.exp(-_puckSpringPerSec * dt)).clamp(0.0, 1.0);
    s.puckHeight += (s.targetHeight - s.puckHeight) * follow;
    s.peakHeight = math.max(s.peakHeight, s.puckHeight);

    // Hammer swing + tap-flash clocks.
    if (s.swing > 0) s.swing = math.max(0.0, s.swing - dt);
    for (final f in s.flashes) {
      f.life -= dt;
    }
    s.flashes.removeWhere((f) => f.life <= 0);
    s.sinceTap += dt;

    s.figure.update(dt);
  }

  /// True when heat has crossed the redline into the overheat (RED) zone.
  bool _isOverheated(double heat) => heat > _heatGreenHi;

  /// True when heat sits inside the GREEN band (full-strength climb).
  bool _isInGreen(double heat) => heat >= _heatGreenLo && heat <= _heatGreenHi;

  // ── Tap → heat + puck kick + swing + feedback ───────────────────────────────

  void _tap(int id) {
    final s = _strikers[id];
    if (s == null) return;

    s.sinceTap = 0;

    // Add heat FIRST, then judge the band — a tap that tips you over the redline
    // boils over on that very tap (so spamming is self-punishing).
    s.heat = math.min(1.0, s.heat + _heatPerTap);

    // Climb strength by band: green = full, cold = weak warm-up, red = stall.
    final double bandFrac;
    if (_isOverheated(s.heat)) {
      bandFrac = _overheatKickFrac;
    } else if (_isInGreen(s.heat)) {
      bandFrac = 1.0;
    } else {
      bandFrac = _coldKickFrac; // below the green band
    }

    // FRENZY shoves a green climb harder; COMEBACK gives a trailing striker a
    // gentle extra push — both ride the green tap so neither rewards a redline.
    final frenzyMult = _inFrenzy ? (1.0 + _frenzyKickBoost) : 1.0;
    final catchUpMult = 1.0 + _catchUpBoost(s);
    final kick = _baseKickPerTap * bandFrac * frenzyMult * catchUpMult;
    s.targetHeight = math.min(1.0, s.targetHeight + kick);

    // Swing the hammer down-stroke + a chop drives the lever.
    s.swing = _swingSec;
    s.figure.attack(1);

    _spawnTapFeedback(s);
    _maybeRingBell(s);
  }

  /// Extra green-tap climb for a trailing striker, scaled 0..1 by how far its
  /// puck sits below the current leader's peak (capped at [_catchUpGapFull]).
  /// Zero for the leader. Gap is on peak height (the scored quantity).
  double _catchUpBoost(_Striker s) {
    final gap = _leadPeak() - s.peakHeight;
    if (gap <= 0) return 0;
    final t = (gap / _catchUpGapFull).clamp(0.0, 1.0);
    return _catchUpMaxBoost * t;
  }

  /// The highest peak height across all strikers (the current leader).
  double _leadPeak() {
    var best = 0.0;
    for (final s in _strikers.values) {
      if (s.peakHeight > best) best = s.peakHeight;
    }
    return best;
  }

  /// Each tap = a flash ring + a small spark spray off the lever plate. A red
  /// (overheated) tap sprays in the danger color so a boil-over reads instantly.
  void _spawnTapFeedback(_Striker s) {
    final base = _leverAnchor(s);
    final color =
        _isOverheated(s.heat) ? MasherRenderer.overheatRed : _colorOf(s.slot.id);
    s.flashes.add(_Flash(at: base, life: _flashLifeSec));
    if (s.flashes.length > _maxFlashes) s.flashes.removeAt(0);
    _juice.particles.burst(
      at: base,
      count: 4,
      color: color,
      speed: 150,
      baseAngle: -math.pi / 2,
      spread: math.pi * 0.8,
      size: 4,
      gravity: 500,
      life: 0.3,
    );
  }

  /// The first time a puck tops out, ring the bell: golden burst + DING popup +
  /// hit-stop + shake. Fires once per striker per round.
  void _maybeRingBell(_Striker s) {
    if (s.belled || s.targetHeight < 1.0) return;
    s.belled = true;
    final bell = _bellAnchor(s);
    final color = _colorOf(s.slot.id);
    _juice.particles.burst(
      at: bell,
      count: 20,
      color: MasherRenderer.bellGold,
      speed: 360,
      spread: math.pi * 2,
      size: 7,
      gravity: 500,
      life: 0.7,
    );
    _juice.particles.burst(
      at: bell,
      count: 12,
      color: color,
      speed: 260,
      size: 5,
      life: 0.6,
    );
    _juice.popup(
      bell.translate(0, -_size.height * 0.04),
      'DING!',
      MasherRenderer.bellGold,
      size: 38,
    );
    _juice.shake.medium();
    _juice.hitStop.trigger(Feel.hitStopDefaultSec);
  }

  /// Bots mash on a cadence clock with [BotProfile]-driven interval + jitter, and
  /// — the skill layer — EASE OFF when their heat nears the redline so a strong
  /// bot rides the green band instead of boiling over. The guard caps catch-up
  /// taps for huge frame steps.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // let the human get a head start
    for (final s in _strikers.values) {
      if (!s.slot.isBot) continue;
      // Cooling pause: while easing, the bot holds off tapping so its heat
      // bleeds back down into the green (mirrors a human laying off the button).
      if (s.botCooldown > 0) {
        s.botCooldown = math.max(0.0, s.botCooldown - dt);
        continue;
      }
      s.botClock += dt;
      var guard = 0;
      while (s.botClock >= s.nextTapAt && guard++ < 8) {
        s.botClock -= s.nextTapAt;
        _tap(s.slot.id);
        // After tapping, if heat has climbed to this bot's ease point, take a
        // cooling beat before the next tap.
        if (s.heat >= s.botEaseHeat) {
          s.botCooldown = _botEasePause;
          break;
        }
        s.nextTapAt = _nextBotInterval(s);
      }
    }
  }

  double _nextBotInterval(_Striker s) =>
      math.max(0.04, s.botInterval + ctx.rng.jitter(s.botJitter));

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    MasherRenderer.drawBackground(canvas, size, _animClock);

    for (final p in ctx.players) {
      final s = _strikers[p.id];
      final lane = _laneByPlayer[p.id];
      if (s == null || lane == null) continue;
      _drawStriker(canvas, s, lane);
    }

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawStriker(Canvas canvas, _Striker s, _Lane lane) {
    final color = _colorOf(s.slot.id);
    final tower = _Tower.of(lane);

    MasherRenderer.drawTower(
      canvas,
      tower.spec,
      color: color,
      levels: _levels,
      litFraction: s.puckHeight,
      number: s.slot.id + 1,
      glowPulse: 0.5 + 0.5 * math.sin(_animClock * 3.0 + s.slot.id),
    );
    MasherRenderer.drawPuck(
      canvas,
      tower.spec,
      heightFrac: s.puckHeight,
      color: color,
    );
    MasherRenderer.drawBell(
      canvas,
      tower.spec,
      color: color,
      rung: s.belled,
      glowPulse: 0.5 + 0.5 * math.sin(_animClock * 6.0 + s.slot.id),
    );

    // Tap flash rings over the lever plate (behind the striker so the figure
    // stays readable even during a frantic mash).
    for (final f in s.flashes) {
      final t = (f.life / _flashLifeSec).clamp(0.0, 1.0);
      MasherRenderer.drawTapFlash(canvas, f.at, t, color, tower.width);
    }

    // Striker stickman + hammer, standing to the left of the tower hardware and
    // swinging the hammer rightward onto the lever plate. Kept inside the lane.
    final feet = Offset(lane.center - tower.width * 0.66, lane.feet.dy);
    final root = Offset(feet.dx, feet.dy - s.footReach);
    MasherRenderer.drawContactShadow(canvas, feet, tower.width * 0.5);
    MasherRenderer.drawStriker(
      canvas,
      s.figure,
      root,
      hammerSwing: _swingPhase(s),
      hammerHead: tower.leverPlate,
      color: color,
      scale: tower.width,
    );

    // HEAT gauge at the lane base: the green sweet-zone band, the red overheat
    // zone, and the live heat fill. This is the player's decision readout — keep
    // the fill in the green, off the red.
    MasherRenderer.drawHeatGauge(
      canvas,
      Offset(lane.center, lane.feet.dy + tower.width * 0.55),
      tower.width * 1.7,
      heat: s.heat,
      greenLo: _heatGreenLo,
      greenHi: _heatGreenHi,
      color: color,
      pulse: 0.5 + 0.5 * math.sin(_animClock * 12.0 + s.slot.id),
    );
  }

  /// 0 (rest) → 1 (hammer slammed onto the plate) → 0 over a swing, eased so the
  /// down-stroke snaps and the recovery is gentle.
  double _swingPhase(_Striker s) {
    if (s.swing <= 0) return 0;
    final p = 1.0 - (s.swing / _swingSec).clamp(0.0, 1.0); // 0..1 through swing
    // Fast down to the plate by ~40% of the swing, then ease back up.
    return p < 0.4 ? easeOut(p / 0.4) : easeOut((1 - p) / 0.6);
  }

  // ── Layout ──────────────────────────────────────────────────────────────────

  /// One vertical lane per player, split evenly across the width.
  Map<int, _Lane> _lanes(Size size) {
    final players = ctx.players;
    final n = players.length;
    final result = <int, _Lane>{};
    final groundY = size.height * 0.86; // foot line
    for (var i = 0; i < n; i++) {
      final center = size.width * (i + 0.5) / n;
      final width = (size.width / n) * 0.5; // tower base width
      result[players[i].id] = _Lane(
        center: center,
        width: width,
        topY: size.height * 0.08,
        feet: Offset(center, groundY),
      );
    }
    return result;
  }

  Offset _leverAnchor(_Striker s) {
    final lane = _laneByPlayer[s.slot.id];
    if (lane == null) return Offset(_size.width / 2, _size.height / 2);
    return _Tower.of(lane).leverPlate;
  }

  Offset _bellAnchor(_Striker s) {
    final lane = _laneByPlayer[s.slot.id];
    if (lane == null) return Offset(_size.width / 2, _size.height * 0.1);
    return _Tower.of(lane).bell;
  }

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;
}

/// A player's vertical column of the arena. Pure layout value.
class _Lane {
  final double center; // x of the lane center
  final double width; // tower base width
  final double topY; // top of the playable column (bell sits near here)
  final Offset feet; // ground line under the striker

  const _Lane({
    required this.center,
    required this.width,
    required this.topY,
    required this.feet,
  });
}

/// Derived geometry of one high-striker tower. Wraps a [TowerSpec] (the value
/// the renderer consumes) plus a couple of sim-side anchors so render and sim
/// agree on where the lever plate and bell sit.
class _Tower {
  final TowerSpec spec;

  const _Tower(this.spec);

  factory _Tower.of(_Lane lane) {
    // Lever plate sits low (near the striker's knees) like a real high striker,
    // so the hammer swings down onto it and the rail climbs up from there.
    final plateY = lane.feet.dy - lane.width * 0.45;
    final topY = lane.topY + lane.width * 0.9; // leave room for the bell
    return _Tower(TowerSpec(
      center: lane.center,
      width: lane.width,
      railTop: topY,
      railBottom: plateY,
    ));
  }

  double get width => spec.width;
  Offset get leverPlate => spec.leverPlate;
  Offset get bell => spec.bell;
}

/// A short-lived tap flash ring over the lever. Mutable round-scoped state.
class _Flash {
  final Offset at;
  double life;
  _Flash({required this.at, required this.life});
}

/// Per-player tower state for one round. Mutable round-scoped state (allowed for
/// the duration of a single round).
class _Striker {
  final PlayerSlot slot;
  final StickFigure figure;
  final double footReach;
  final double botInterval;
  final double botJitter;
  final double botEaseHeat; // heat at which this bot eases off to cool down

  double heat = 0; // 0..1 sweet-zone gauge (the decision)
  double puckHeight = 0; // 0..1 current rendered puck height
  double targetHeight = 0; // 0..1 height the puck eases toward
  double peakHeight = 0; // best height reached — THIS is the score source
  double swing = 0; // seconds of hammer down-stroke remaining
  bool belled = false; // rang the bell at least once
  double sinceTap = 1e9; // seconds since this striker's last tap

  // Bot cadence clock + cooling beat.
  double botClock = 0;
  double nextTapAt;
  double botCooldown = 0; // seconds the bot holds off to cool back into green

  final List<_Flash> flashes = <_Flash>[];

  _Striker({
    required this.slot,
    required this.figure,
    required this.footReach,
    required this.botInterval,
    required this.botJitter,
    required this.botEaseHeat,
  }) : nextTapAt = botInterval;
}
