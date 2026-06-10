import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../art/stick/weapon_visual.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/reaction_gate.dart';
import '../../engine/input_zones.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'reaction_duel_rounds.dart';
import 'reaction_render.dart';

/// Reaction Duel — a samurai quick-draw standoff at dusk, played as a best-of:
/// a normal round, then a CLIMAX **LIGHTNING round worth double** (snappier
/// wait, a persistent gold ambience). Each round the field shows "WAIT…" through
/// a random delay (via [ReactionGate]), then a blinding "STRIKE!" signal; the
/// first valid tap lands an instant slash and ragdoll-KOs the loser(s) under a
/// slow-mo beat. Tapping BEFORE the signal is a false start (locked out for that
/// round). A late tap still records a reaction time, so the round ranks the
/// whole field, and the match ranks by cumulative points (see [buildDuelRanking]).
///
/// Bots draw after the signal on a [BotProfile]-driven reaction delay (+jitter)
/// and may jump the gun with probability [BotProfile.errorRate]; per-round and
/// overall timeouts guarantee the match always resolves within its limit.
class ReactionDuel extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'reaction_duel',
        name: 'Reaction Duel',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'TAP',
      );

  // ── Round tuning (no magic numbers inline) ──────────────────────────────────
  // The duel is now a short best-of: a normal round, then a LIGHTNING FINAL
  // round worth double. The cap is sized to comfortably fit both rounds (each
  // round: up to _maxGoDelay wait + a reaction window + the post-win linger).
  static const int _roundCount = 2; // total rounds (last one is the lightning)
  static const double _timeLimit = 20;
  static const double _minGoDelay = 1.2;
  static const double _maxGoDelay = 3.6;
  static const double _lightningMinGoDelay = 0.7; // snappier wait in the finale
  static const double _lightningMaxGoDelay = 2.0;
  static const double _lingerAfterWin = 1.0; // hold the KO beat before next round
  static const double _interRoundSec = 1.3; // beat between rounds (cue + reset)
  static const double _goWindow = 3.0; // max seconds in GO before force-ending
  static const double _penaltyScore = -1; // HUD score for false-starters

  // ── Climax: the LIGHTNING FINAL round (double points) ───────────────────────
  static const int _normalRoundPoints = 1; // winner's points in a normal round
  static const int _lightningPoints = 2; // winner's points in the finale
  static const double _lightningCueSec = 1.6; // "LIGHTNING ROUND!" banner life
  static const Color _lightningGold = Color(0xFFFFE45C);

  // ── Strike / feel tuning ────────────────────────────────────────────────────
  static const double _strikeFlashSec = 0.45; // blinding flash + screen-flash
  static const double _strikeWordSec = 0.55; // STRIKE word punch-in then fade
  static const double _screenFlashMax = 0.4; // peak white screen-flash opacity
  static const double _slashLifeSec = 0.55; // slash arc + speed-line life
  static const double _tooSoonLifeSec = 1.4; // "TOO SOON!" stamp life
  static const double _hitStopSec = 0.22; // slow-mo on the decisive strike
  static const double _hitStopScale = 0.12;
  // Ragdoll fling is a velocity in px/s (the ragdoll integrates at g≈1800), so
  // it is sized off arena height for a dramatic, resolution-independent launch.
  // The lift dominates and the sideways push is capped so the loser pops UP and
  // back (a readable KO) instead of sailing off the side of a row.
  static const double _flingBaseFracH = 0.40; // base fling speed / arena height
  static const double _flingDecisiveFracH = 0.24; // extra for a decisive win
  static const double _flingLiftFactor = 1.0; // upward share of the fling
  static const double _flingSidewaysFactor = 0.5; // capped horizontal share
  static const double _decisiveRefSec = 0.35; // reaction at/under = max decisive

  // ── Layout tuning (fractions of arena) ──────────────────────────────────────
  // Duelists stand in a row on the dueling ground (lower band), facing the
  // central signal that floats above them in the sky.
  static const double _lineYFrac = 0.66; // foot line for a single duelist
  static const double _lineSpreadFrac = 0.74; // total horizontal spread / width
  static const double _lineMarginFrac = 0.18; // edge margin / width
  static const double _depthStaggerFrac = 0.045; // alt near/far foot-line offset
  static const double _figureScale = 2.0; // readable swordsmen

  // ── Tension / vignette ──────────────────────────────────────────────────────
  static const double _vignetteWaitBase = 0.25;
  static const double _vignetteWaitGain = 0.6; // ramps over the wait
  static const double _vignettePulseHz = 5.0;
  static const double _cueCenterFrac = 0.21; // banner in the clean sky above sun
  static const Color _accentGold = Color(0xFFFFE08A); // confetti highlight

  // ── Per-zone signal (the unmistakable kid-clear cue) ─────────────────────────
  // Each player's whole zone is washed RED while waiting, then flashes a sudden
  // bright GREEN on GO ("TAP!"). The wash is the dominant signal; the samurai
  // figures + center cue ride on top as flavor. A false-starter's zone goes a
  // calm grey with a gentle "TOO EARLY!" — readable, never harsh.
  static const Color _zoneRed = Color(0xFFE53935); // WAIT red
  static const Color _zoneGreen = Color(0xFF24D16A); // GO green
  static const Color _zoneGrey = Color(0xFF6B6B72); // false-start grey
  static const double _zoneWaitAlpha = 0.30; // resting red wash strength
  static const double _zoneWaitPulse = 0.10; // red wash throb amplitude
  static const double _zoneGoBaseAlpha = 0.42; // steady green while GO holds
  static const double _zoneGoFlashAlpha = 0.45; // extra green at the GO edge
  static const double _zoneWinPulse = 0.18; // winner zone celebratory throb

  late Juice _juice;
  late ReactionGate _gate;
  late Size _size;
  late Offset _center;
  late StickProportions _proportions;
  late double _scaleUnit; // ≈ torso width — fx sizing base
  late double _footReach; // pelvis→foot length at rest (for grounding)

  double _elapsed = 0;
  double _sinceDone = 0;
  double _sinceGo = 0;
  double _animClock = 0; // real-time clock (never scaled) for sway/tension
  double _strikeFlash = 0; // 1 → 0 over [_strikeFlashSec] after the signal
  double _strikeWord = 0; // 1 → 0 over [_strikeWordSec]: banner punch then fade
  bool _signalSeen = false; // the GO signal has fired at least once
  bool _confettiFired = false;
  bool _feintLitLast = false; // edge-detect each fake-GO flash (bot bait)

  // ── Best-of round state (the climax is the final LIGHTNING round) ───────────
  int _round = 1; // 1-based; _round == _roundCount is the lightning final
  bool _between = false; // in the short inter-round beat (cue + reset)
  double _betweenTimer = 0; // time spent in the inter-round beat
  bool _roundScored = false; // this round's points have been tallied
  double _lightningCue = 0; // 1 → 0 life of the "LIGHTNING ROUND!" banner
  final Map<int, int> _points = <int, int>{}; // cumulative points across rounds

  final Map<int, _Reactor> _reactors = <int, _Reactor>{};
  final List<Slash> _slashes = <Slash>[]; // active slash arcs (winner→loser)

  bool get _isLightning => _round >= _roundCount;

  /// True while a fake-GO flash is lit before the real signal — the field bluffs
  /// green to bait a tap, but the gate is still WAITING so any tap is an early
  /// false start. Cleared the instant the real GO fires.
  bool get _feintLit => !_signalSeen && _gate.feintActive;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _gate = ReactionGate(ctx.rng, minDelay: _minGoDelay, maxDelay: _maxGoDelay);
    _size = ctx.arena;
    _center = Offset(_size.width / 2, _size.height * 0.5);

    _proportions = StickProportions.hero.scaled(_figureScale);
    _scaleUnit = _proportions.torsoWidth;
    // Legs are near-vertical at rest, so pelvis→foot ≈ thigh + shin.
    _footReach = _proportions.thigh + _proportions.shin;

    for (final p in ctx.players) {
      _points[p.id] = 0;
    }
    _buildDuelists();
    begin();
  }

  /// Place one swordsman per player, each facing the center, and build its
  /// figure (player color, sheathed sword) + reaction clock. With two players we
  /// stage a classic face-off line; otherwise we ring them around the signal.
  void _buildDuelists() {
    final positions = _layoutPositions(ctx.players.length);
    for (var i = 0; i < ctx.players.length; i++) {
      _reactors[ctx.players[i].id] = _makeReactor(ctx.players[i], positions[i]);
    }
  }

  /// Build a ready-stance duelist for [p] at [foot] (fresh figure facing the
  /// centre, fresh clock, per-round gun-jump roll). Shared by the first build
  /// and each round reset so the two never drift.
  _Reactor _makeReactor(PlayerSlot p, Offset foot) {
    final facing = foot.dx <= _center.dx ? 1.0 : -1.0; // face the signal
    final color = Color(p.colorArgb);
    return _Reactor(
      slot: p,
      foot: foot,
      figure: StickFigure(
        proportions: _proportions,
        style: _styleFor(color),
        weapon: _swordFor(color),
        facing: facing,
      )
        ..aimAngle = _sheathedAim(facing)
        ..setLoco(LocoState.idle),
      clock: ReactionClock(ctx.botProfile, ctx.rng),
      jumpsTheGun: p.isBot && ctx.rng.chance(ctx.botProfile.errorRate),
    );
  }

  /// Foot-line anchors per player: a row of duelists across the dueling ground,
  /// evenly spread and facing the central signal. Alternating duelists sit a
  /// touch nearer/farther (depth stagger) so a full row reads with depth rather
  /// than as a flat line. 1P stands dead center.
  List<Offset> _layoutPositions(int n) {
    final baseY = _size.height * _lineYFrac;
    if (n <= 1) return [Offset(_center.dx, baseY)];

    final spread = _size.width * _lineSpreadFrac;
    final left = _size.width * _lineMarginFrac;
    final stagger = _size.height * _depthStaggerFrac;
    return [
      for (var i = 0; i < n; i++)
        Offset(
          left + spread * (i / (n - 1)),
          baseY + (i.isOdd ? -stagger : stagger * 0.4),
        ),
    ];
  }

  /// Bright duelist style: player-color fill with a brightened outline + glow.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        rimAlpha: 0.3,
        shadowAlpha: 0.0, // we draw our own contact shadow
        gradientBottom: 0.55,
        smearAlpha: 0.3,
      );

  /// A katana whose edge picks up the duelist's color.
  WeaponVisual _swordFor(Color color) => WeaponVisual(
        shape: WeaponShape.sword,
        color: const Color(0xFFCED6E0),
        edge: _brighten(color, 0.35),
        length: _scaleUnit * 5.0,
        width: _scaleUnit * 0.7,
      );

  /// Sheathed/hand-on-hilt aim: blade angled down-forward so it reads as drawn
  /// from the hip rather than pointed at the sky.
  double _sheathedAim(double facing) => facing >= 0 ? 0.5 : math.pi - 0.5;

  // ── Input ───────────────────────────────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _handleTap(input.playerId);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);
    _decayEffects(dt);
    _advanceFigures(sdt);

    // The short beat between rounds: hold a cue, then arm the next round.
    if (_between) {
      _betweenTimer += dt;
      if (_betweenTimer >= _interRoundSec) _beginNextRound();
      // Absolute safety net even mid-transition.
      if (_elapsed >= _timeLimit) _finishFromPoints();
      return;
    }

    _gate.update(dt);
    _onSignalEdge();
    _driveBots(dt);
    _publishLiveScores();
    _resolveOutcome(dt);
  }

  /// Detect the WAIT→GO transition exactly once and fire the strike telegraph:
  /// a blinding flash, a sharp shake, and snap every honest duelist into a
  /// ready/draw cue.
  void _onSignalEdge() {
    if (_signalSeen || _gate.phase != ReactionPhase.go) return;
    _signalSeen = true;
    _strikeFlash = 1.0;
    _strikeWord = 1.0;
    _juice.shake.medium();
    _juice.hitStop.trigger(0.06);
    for (final r in _reactors.values) {
      if (!_gate.penalized.contains(r.slot.id)) r.figure.setLoco(LocoState.run);
    }
  }

  void _decayEffects(double dt) {
    if (_strikeFlash > 0) {
      _strikeFlash = (_strikeFlash - dt / _strikeFlashSec).clamp(0.0, 1.0);
    }
    if (_strikeWord > 0) {
      _strikeWord = (_strikeWord - dt / _strikeWordSec).clamp(0.0, 1.0);
    }
    if (_lightningCue > 0) {
      _lightningCue = (_lightningCue - dt / _lightningCueSec).clamp(0.0, 1.0);
    }
    for (final r in _reactors.values) {
      if (r.tooSoon > 0) {
        r.tooSoon = (r.tooSoon - dt / _tooSoonLifeSec).clamp(0.0, 1.0);
      }
    }
    for (final s in _slashes) {
      s.life = (s.life - dt / _slashLifeSec).clamp(0.0, 1.0);
    }
    _slashes.removeWhere((s) => s.life <= 0);
  }

  /// Bots: gun-jumpers tap during the wait; honest bots draw after the signal
  /// on their (jittered) reaction delay. Honest bots can also be BAITED by a
  /// feint — on each fresh fake-GO flash they roll [BotProfile.errorRate] and,
  /// if it lands, snap at the fake (a false start), so weak bots fall for feints
  /// and strong bots hold. A stalled GO closes its own window so a round of
  /// all-false-starts still resolves.
  void _driveBots(double dt) {
    final inGo = _gate.phase == ReactionPhase.go;
    if (inGo) {
      _sinceGo += dt;
      if (_gate.winner == null && _sinceGo >= _goWindow) _gate.forceDone();
    }
    _maybeBaitBotsOnFeint();
    for (final r in _reactors.values) {
      if (!r.slot.isBot || r.acted) continue;
      if (r.jumpsTheGun && _gate.phase == ReactionPhase.waiting) {
        if (r.clock.tick(dt)) {
          _handleTap(r.slot.id);
          r.acted = true;
        }
        continue;
      }
      if (inGo && r.clock.tick(dt)) {
        _handleTap(r.slot.id);
        r.acted = true;
      }
    }
  }

  /// On the rising edge of each feint flash, every honest, not-yet-acted bot
  /// rolls [BotProfile.errorRate]; a hit makes it tap the fake (an early false
  /// start). Rolled once per flash via [_feintLitLast] so a bot can't be tested
  /// every frame the flash is lit.
  void _maybeBaitBotsOnFeint() {
    final lit = _gate.feintActive;
    final rising = lit && !_feintLitLast;
    _feintLitLast = lit;
    if (!rising) return;
    for (final r in _reactors.values) {
      if (!r.slot.isBot || r.acted) continue;
      if (r.jumpsTheGun) continue; // already committed to jumping the gun
      if (ctx.rng.chance(ctx.botProfile.errorRate)) {
        _handleTap(r.slot.id); // taps a fake → penalized lockout
        r.acted = true;
      }
    }
  }

  /// Resolve one tap through the gate and play the matching beat.
  void _handleTap(int id) {
    final reactor = _reactors[id];
    if (reactor == null) return;
    final result = _gate.onTap(id);
    switch (result) {
      case ReactionTap.valid:
        _onStrike(reactor);
      case ReactionTap.early:
        _onFalseStart(reactor);
      case ReactionTap.late:
        // A valid-but-late draw: a small clash spark, no KO.
        _juice.hit(_chestOf(reactor), _colorOf(id), sparks: 5);
        reactor.figure.dash();
      case ReactionTap.ignored:
        break;
    }
  }

  /// The winning quick-draw: turn toward the field and whip out a horizontal
  /// slash that arcs to each loser (KO-flinging them), under a slow-mo beat, with
  /// a big "STRIKE!" popup.
  void _onStrike(_Reactor winner) {
    final reaction = _gate.reactionTimes[winner.slot.id] ?? _decisiveRefSec;
    final decisive =
        (1.0 - (reaction / _decisiveRefSec)).clamp(0.0, 1.0); // 0..1
    final color = _colorOf(winner.slot.id);

    // Face the loser cluster and level the blade at them, then whip the slash.
    final faceDir = _loserDirection(winner);
    winner.figure
      ..facing = faceDir
      ..aimAngle = faceDir >= 0 ? 0.0 : math.pi
      ..attack(0);

    _juice.hitStop.trigger(_hitStopSec, scale: _hitStopScale);
    _juice.shake.heavy();
    _juice.popup(
        _chestOf(winner).translate(0, -_scaleUnit * 3.4), 'STRIKE!', color,
        size: 44);

    final from = _bladeTipOf(winner);
    for (final r in _reactors.values) {
      if (r.slot.id == winner.slot.id) continue;
      if (_gate.penalized.contains(r.slot.id)) continue; // already toppled
      _fellLoser(r, from, decisive);
    }
  }

  /// +1/-1 toward the average position of the duelists the [winner] can topple
  /// (non-winner, non-penalized); falls back to facing screen center.
  double _loserDirection(_Reactor winner) {
    var sumX = 0.0;
    var count = 0;
    for (final r in _reactors.values) {
      if (r.slot.id == winner.slot.id) continue;
      if (_gate.penalized.contains(r.slot.id)) continue;
      sumX += r.foot.dx;
      count++;
    }
    final targetX = count > 0 ? sumX / count : _center.dx;
    return targetX >= winner.foot.dx ? 1.0 : -1.0;
  }

  /// Topple one loser: a slash arc + speed lines from the winner, then a real
  /// ragdoll flung away from the strike, with a KO burst + popup.
  void _fellLoser(_Reactor loser, Offset from, double decisive) {
    final color = _colorOf(loser.slot.id);
    final chest = _chestOf(loser);
    _slashes.add(Slash(from: from, to: chest, color: color, life: 1.0));

    _juice.ko(chest, color);

    if (loser.figure.isRagdoll) return;
    // Fling (a velocity in px/s): a capped sideways push away from the strike +
    // a dominant upward lift so the loser pops up-and-back (classic KO) and
    // mostly stays in frame, scaled by how decisive the win was.
    final away = _normalize(chest - from);
    final dirX = away.dx >= 0 ? 1.0 : -1.0;
    final mag =
        _size.height * (_flingBaseFracH + _flingDecisiveFracH * decisive);
    final fling = Offset(dirX * mag * _flingSidewaysFactor, -mag * _flingLiftFactor);
    final groundY = loser.foot.dy;
    loser.figure.enterRagdoll(_rootOf(loser), groundY, fling);
  }

  /// A false start: the gate already penalized them. Stamp "TOO SOON!", stagger
  /// them with a hurt pose, and a light shake.
  void _onFalseStart(_Reactor reactor) {
    // Gentle, kid-friendly: a soft hurt stagger + a light shake. The big GREY
    // zone wash + "TOO EARLY!" word (drawn per zone) is the real feedback, so we
    // keep the figure beat understated and never harsh.
    reactor.tooSoon = 1.0;
    reactor.figure.hurt();
    _juice.shake.light();
  }

  void _advanceFigures(double dt) {
    for (final r in _reactors.values) {
      r.figure.update(dt);
    }
  }

  /// Live HUD score: cumulative round points plus a tiny (<1) in-round nudge so
  /// a faster reaction edges ahead and a false-starter dips, while the round
  /// points always dominate — kids watch the tally climb, the finale swings it.
  void _publishLiveScores() {
    final times = _gate.reactionTimes;
    final penalized = _gate.penalized;
    for (final p in ctx.players) {
      final base = (_points[p.id] ?? 0).toDouble();
      if (penalized.contains(p.id)) {
        setScore(p.id, base + _penaltyScore * 0.001);
      } else {
        final t = times[p.id];
        // Tiny in-round nudge (<1) so cumulative points always dominate.
        setScore(p.id, base + (t != null ? 0.001 / (t + 0.01) : 0));
      }
    }
  }

  // ── Outcome (best-of rounds) ────────────────────────────────────────────────

  void _resolveOutcome(double dt) {
    if (_gate.phase == ReactionPhase.done) {
      _sinceDone += dt;
      if (!_confettiFired && _gate.winner != null) {
        _confettiFired = true;
        final w = _gate.winner;
        // Winner-tinted confetti, brightened so it reads clearly as celebration.
        _juice.confetti(_size,
            colors: w == null
                ? const []
                : [_colorOf(w), _brighten(_colorOf(w), 0.55), _accentGold]);
      }
      if (_sinceDone >= _lingerAfterWin) _onRoundOver();
    }
    // Absolute safety net: never exceed the time limit.
    if (_elapsed >= _timeLimit && status == MiniGameStatus.running) {
      _gate.forceDone();
      _tallyRound();
      _finishFromPoints();
    }
  }

  /// A round has fully resolved (winner + linger done): bank its points, then
  /// either kick off the inter-round beat or finish the whole match.
  void _onRoundOver() {
    _tallyRound();
    if (_round < _roundCount) {
      _beginInterRound();
    } else {
      _finishFromPoints();
    }
  }

  /// Award this round's points to its winner (double in the lightning final).
  /// Idempotent per round via [_roundScored] so a tally + safety-net can't
  /// double-count.
  void _tallyRound() {
    if (_roundScored) return;
    _roundScored = true;
    final winner = _gate.winner;
    if (winner == null) return;
    final award = _isLightning ? _lightningPoints : _normalRoundPoints;
    _points[winner] = (_points[winner] ?? 0) + award;
  }

  /// Open the inter-round beat; [update] times it out then arms the next round.
  void _beginInterRound() {
    _between = true;
    _betweenTimer = 0;
  }

  /// Arm the next round: bump the counter, roll a fresh gate (snappier delays in
  /// the lightning final), reset every duelist to a ready stance, clear the
  /// round-scoped fx + flags, and raise the LIGHTNING cue when it is the finale.
  void _beginNextRound() {
    _round += 1;
    _between = false;
    _betweenTimer = 0;
    _roundScored = false;
    _signalSeen = false;
    _confettiFired = false;
    _feintLitLast = false;
    _sinceDone = 0;
    _sinceGo = 0;
    _slashes.clear();

    _gate = _isLightning
        ? ReactionGate(ctx.rng,
            minDelay: _lightningMinGoDelay, maxDelay: _lightningMaxGoDelay)
        : ReactionGate(ctx.rng, minDelay: _minGoDelay, maxDelay: _maxGoDelay);

    _resetDuelistsForRound();

    if (_isLightning) {
      _lightningCue = 1.0;
      _juice.shake.medium();
      final center = Offset(_size.width / 2, _size.height * _cueCenterFrac);
      _juice.popup(center, 'LIGHTNING ROUND!', _lightningGold, size: 44);
      _juice.popup(center.translate(0, _scaleUnit * 2.6), 'DOUBLE POINTS',
          _brighten(_lightningGold, 0.2),
          size: 26);
    }
  }

  /// Reset each duelist for a fresh round by rebuilding it at the same foot
  /// anchor (un-ragdolls, re-poses, re-arms). Points live outside the reactors.
  void _resetDuelistsForRound() {
    for (final p in ctx.players) {
      final old = _reactors[p.id];
      if (old == null) continue;
      _reactors[p.id] = _makeReactor(p, old.foot);
    }
  }

  /// Build the final ranking from cumulative points (best→worst), with the last
  /// round's reaction times as a gentle tiebreak (see [buildDuelRanking]). Every
  /// player id appears exactly once.
  void _finishFromPoints() {
    if (status == MiniGameStatus.finished) return;
    _publishLiveScores();

    final ids = buildDuelRanking(
      ctx.players.map((p) => p.id).toList(),
      _points,
      _gate.reactionTimes,
    );

    finishWith(WinResult(
      ranking: ids,
      finalScores: Map<int, num>.from(scores.byPlayer),
    ));
  }

  // ── Render ───────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    ReactionRenderer.drawBackground(canvas, size, _animClock);
    ReactionRenderer.drawGround(canvas, size);
    ReactionRenderer.drawVignette(canvas, size, _vignettePulse());

    // The per-zone RED→GREEN wash is the dominant, kid-clear signal. Drawn under
    // the figures so the swordsmen sit on top of their colored ground.
    _drawZoneWashes(canvas, size);

    // The LIGHTNING (double-points) final round gets a persistent gold edge-wash
    // so the climax reads at a glance; the cue peak blooms at the round start.
    if (_isLightning) {
      ReactionRenderer.drawLightningAmbience(
          canvas, size, _lightningCue, _waitPulse(),
          gold: _lightningGold);
    }

    _drawDuelists(canvas);
    _drawSlashes(canvas);

    // Big per-zone word ("WAIT" / "TAP!" / "TOO EARLY!") over the figures so
    // every player reads their own state at a glance.
    _drawZoneLabels(canvas, size);

    // During a feint we paint the same green "GO!" cue (a bluff). A steady flash
    // value keeps the fake burst lit for the blink, snapping back to red after.
    final feinting = _feintLit;
    ReactionRenderer.drawCenterCue(
      canvas,
      size,
      struck: _signalSeen || feinting,
      strikeFlash: feinting ? 1.0 : _strikeFlash,
      strikeWord: feinting ? 1.0 : _strikeWord,
      waitPulse: _waitPulse(),
      centerFrac: _cueCenterFrac,
    );
    ReactionRenderer.drawScreenFlash(canvas, size, _strikeFlash * _screenFlashMax);

    _juice.render(canvas);
    canvas.restore();
  }

  /// Vignette pulse: dark + throbbing during WAIT (rising tension), calm after.
  double _vignettePulse() {
    if (_gate.phase != ReactionPhase.waiting) return 0.0;
    final ramp = (_elapsed / _maxGoDelay).clamp(0.0, 1.0);
    final throb = 0.5 + 0.5 * math.sin(_animClock * _vignettePulseHz);
    return (_vignetteWaitBase + _vignetteWaitGain * ramp * throb)
        .clamp(0.0, 1.0);
  }

  /// WAIT-cue throb in 0..1 (also breathes the center word).
  double _waitPulse() => 0.5 + 0.5 * math.sin(_animClock * _vignettePulseHz);

  void _drawDuelists(Canvas canvas) {
    for (final r in _reactors.values) {
      final fig = r.figure;
      final locked = _gate.penalized.contains(r.slot.id);

      // Ragdolled losers render their own self-anchored tumbling frame.
      if (fig.isRagdoll) {
        ReactionRenderer.drawDuelist(canvas, fig, _rootOf(r));
        continue;
      }

      final idx = ctx.players.indexWhere((p) => p.id == r.slot.id);
      ReactionRenderer.drawContactShadow(canvas, r.foot, _scaleUnit);
      ReactionRenderer.drawNamePlate(
        canvas,
        r.foot,
        _scaleUnit,
        _colorOf(r.slot.id),
        idx + 1,
        locked: locked,
      );
      ReactionRenderer.drawDuelist(canvas, fig, _rootOf(r));

      // Per-duelist readout above the head: a small reaction time once they
      // draw, for flavor. The WAIT/TAP/TOO-EARLY state is carried by the big
      // per-zone wash + word; a false start adds a gentle X over the figure.
      final above = _chestOf(r).translate(0, -_scaleUnit * 2.4);
      ReactionRenderer.drawReadout(
          canvas, above, _scaleUnit, _readoutFor(r), _colorOf(r.slot.id));

      if (r.tooSoon > 0) {
        ReactionRenderer.drawEarlyX(canvas, _chestOf(r), _scaleUnit, r.tooSoon);
      }
    }
  }

  void _drawSlashes(Canvas canvas) {
    for (final s in _slashes) {
      ReactionRenderer.drawSlashArc(canvas, s.from, s.to, s.color, s.life);
      ReactionRenderer.drawSpeedLines(canvas, s.from, s.to, s.color, s.life);
    }
  }

  /// Wash each player's whole zone with its signal color — the unmistakable
  /// cue. RED while waiting (gentle throb), a sudden bright GREEN on GO (a flash
  /// that spikes at the edge then settles to a steady "TAP!" green), GREEN for a
  /// player who has drawn, and a calm GREY for a false-starter.
  void _drawZoneWashes(Canvas canvas, Size size) {
    for (final r in _reactors.values) {
      final zone = ctx.zones.forPlayer(r.slot.id);
      if (zone == null) continue;
      final rect = _zoneRect(zone, size);
      final (color, alpha) = _zoneWash(r.slot.id);
      ReactionRenderer.drawZoneWash(canvas, rect, color, alpha);
    }
  }

  /// Big per-zone word over the figures, rotated to face that seat.
  void _drawZoneLabels(Canvas canvas, Size size) {
    for (final r in _reactors.values) {
      final zone = ctx.zones.forPlayer(r.slot.id);
      if (zone == null) continue;
      final rect = _zoneRect(zone, size);
      final (text, color) = _zoneLabel(r.slot.id);
      if (text.isEmpty) continue;
      ReactionRenderer.drawZoneLabel(
          canvas, rect, text, color, zone.rotationQuarters);
    }
  }

  Rect _zoneRect(PlayerZone zone, Size size) => Rect.fromLTRB(
        zone.normRect.left * size.width,
        zone.normRect.top * size.height,
        zone.normRect.right * size.width,
        zone.normRect.bottom * size.height,
      );

  /// Signal wash (color, alpha) for a player's zone given the gate state.
  (Color, double) _zoneWash(int id) {
    if (_gate.penalized.contains(id)) {
      return (_zoneGrey, _zoneWaitAlpha * 0.7);
    }
    final reacted = _gate.reactionTimes.containsKey(id);
    final isWinner = _gate.winner == id;
    if (isWinner) {
      final throb = 0.5 + 0.5 * math.sin(_animClock * _vignettePulseHz);
      return (_zoneGreen, _zoneGoBaseAlpha + _zoneWinPulse * throb);
    }
    if (reacted) return (_zoneGreen, _zoneGoBaseAlpha * 0.85);
    if (_signalSeen) {
      // Bright GREEN: a flash spike at the GO edge that settles to a steady "TAP".
      return (_zoneGreen, _zoneGoBaseAlpha + _zoneGoFlashAlpha * _strikeFlash);
    }
    if (_feintLit) {
      // FAKE GO: flash bright green to bait an early tap — same look as the real
      // signal, but the gate is still waiting so tapping it is a false start.
      return (_zoneGreen, _zoneGoBaseAlpha + _zoneGoFlashAlpha);
    }
    // Waiting: a gently throbbing RED so the kid feels "not yet".
    final throb = 0.5 + 0.5 * math.sin(_animClock * _vignettePulseHz);
    return (_zoneRed, _zoneWaitAlpha + _zoneWaitPulse * throb);
  }

  /// The big readable word for a player's zone: "WAIT" (red), "TAP!" (green),
  /// "WINNER!" / "GOT IT!" once drawn, or a gentle "TOO EARLY!" on a false start.
  (String, Color) _zoneLabel(int id) {
    if (_gate.penalized.contains(id)) {
      return ('TOO EARLY!', const Color(0xFFFFFFFF));
    }
    if (_gate.winner == id) return ('WINNER!', const Color(0xFFFFFFFF));
    if (_gate.reactionTimes.containsKey(id)) {
      return ('GOT IT!', const Color(0xFFFFFFFF));
    }
    // A feint shows the same "TAP!" bait as the real signal (it's a fake-out).
    if (_signalSeen || _feintLit) return ('TAP!', const Color(0xFFFFFFFF));
    return ('WAIT', const Color(0xFFFFFFFF));
  }

  /// The small flavor text above a duelist: their reaction time once they draw,
  /// nothing otherwise (the per-zone word carries the WAIT/TAP/EARLY state).
  String _readoutFor(_Reactor r) {
    if (_gate.penalized.contains(r.slot.id)) return '';
    final t = _gate.reactionTimes[r.slot.id];
    if (t != null) return '${(t * 1000).round()} ms';
    return '';
  }

  // ── Small pure helpers ──────────────────────────────────────────────────────

  /// Stick render root for a duelist: pelvis lifted by [_footReach] so the feet
  /// plant on the duelist's foot line.
  Offset _rootOf(_Reactor r) => Offset(r.foot.dx, r.foot.dy - _footReach);

  /// Chest height for fx anchoring (above the pelvis root).
  Offset _chestOf(_Reactor r) => _rootOf(r).translate(0, -_footReach * 0.55);

  /// Approximate blade-tip position: in front of the chest along facing, where
  /// the slash visually originates.
  Offset _bladeTipOf(_Reactor r) =>
      _chestOf(r).translate(r.figure.facing * _scaleUnit * 3.2, 0);

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return const Offset(0, -1);
    return v / d;
  }
}

/// Per-player reaction state for one round. Mutable round-scoped state (allowed
/// for the duration of a single round).
class _Reactor {
  final PlayerSlot slot;
  final Offset foot; // ground anchor (foot line) for this duelist
  final StickFigure figure;
  final ReactionClock clock;
  final bool jumpsTheGun; // bot decided to false-start this round

  bool acted = false;
  double tooSoon = 0; // 1 → 0 life of the "TOO SOON!" stamp

  _Reactor({
    required this.slot,
    required this.foot,
    required this.figure,
    required this.clock,
    required this.jumpsTheGun,
  });
}
