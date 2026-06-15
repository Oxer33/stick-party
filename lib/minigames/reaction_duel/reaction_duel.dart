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

/// QUICK-DRAW DUEL — a samurai standoff at dusk, played as a best-of race:
/// **first duelist to win [_targetDraws] DRAWS takes the match**.
///
/// OBJECTIVE: each DRAW is a "WAIT…" standoff that, after a random delay, snaps
/// to a real GO ("DRAW!" + green flash). The FASTEST valid tap AFTER the GO wins
/// that draw; everyone slower, silent, or false-started gets nothing. First to
/// [_targetDraws] draws wins the whole duel. The HUD shows each duelist's draw
/// tally and the "FIRST TO N" target.
///
/// THE LEARNABLE READ (real-vs-fake) — the skill the rework makes VISIBLE. During
/// the wait the field flashes 1–3 brief FAKE GOs (feints), but a feint and the
/// real GO are drawn UNMISTAKABLY DIFFERENTLY so a sharp player can learn to tell
/// them apart at a glance:
///   • FEINT  = a brief, dim, JITTERY AMBER blip + an amber "FAKE?" — no ping, no
///     full green wash. The gate stays WAITING, so tapping it is a FALSE START.
///   • REAL GO = a SUSTAINED bright GREEN wash that HOLDS + a green "DRAW!" + a
///     rising "ping" (expanding rings the feint never fires). Tap fast → you win.
/// "Amber, shaky, brief = fake; green, bright, holds + pings = real." A masher
/// who taps on any flash FALSE-STARTS on the feints and wins none; a duelist who
/// reads the cue and holds their nerve banks the draw — and the read is REWARDED
/// visibly (reaction-ms + a READ streak ▲ on a clean tap). As the match tightens
/// the GO band drifts later, feints grow more numerous, and the post-GO window
/// shrinks (see [_gateForDraw] / [_goWindowForDraw]).
///
/// ANTI-INCIDENTAL: a tap before the real GO can NEVER win a draw — the gate
/// classifies any wait-phase tap (including on a feint) as an early false start
/// and never sets it as the winner. Only a deliberate tap during the GO window
/// counts. No lucky early tap can back into a draw.
///
/// 1–4 players: every duelist contests every draw; the single fastest
/// non-false-starter wins it. The match ranks by draws won, then by the snappier
/// cumulative reaction as a tiebreak (see [buildDuelRanking]).
///
/// Bots draw after the signal on a [BotProfile]-driven reaction delay (+jitter)
/// and may jump the gun, or fall for a feint, with probability
/// [BotProfile.errorRate] (easy bots jump often; hard bots hold). Per-draw and
/// overall timeouts guarantee the match always resolves within its limit.
class ReactionDuel extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'reaction_duel',
        // Display name comes from l10n (game_reaction_duel); this is the
        // engine-level fallback, kept stable. The in-game flavor is QUICK-DRAW.
        name: 'Reaction Duel',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'TAP',
      );

  // ── Match shape (the "first to N draws" objective) ──────────────────────────
  // The duel is a race: first to _targetDraws won draws takes it. A hard draw
  // cap + the overall time cap are pure safety nets so the match always lands
  // inside its window even if every draw is a wash (all false starts / silence).
  static const int _targetDraws = 3; // first to this many draws wins
  static const int _maxDraws = 9; // safety cap on draws played
  static const double _timeLimit = 40; // overall cap (seconds)

  // ── Per-draw timing + the calibrated ramp ───────────────────────────────────
  // Draw 0 is gentle; each later draw shifts the GO band later, adds feints,
  // lengthens feint flashes, and tightens the post-GO window — the nerve test
  // ramps so reading real-vs-fake matters more as the match tightens.
  static const double _minGoDelay = 1.1; // base GO band (draw 0)
  static const double _maxGoDelay = 3.0;
  static const double _goDelayRampPerDraw = 0.18; // band drifts later per draw
  static const double _goDelayRampMax = 1.2; // cap the drift
  static const int _baseFeints = 1; // feints at draw 0
  static const int _maxFeints = 3; // feints late
  static const double _baseFeintFlash = 0.18; // feint flash life (draw 0)
  static const double _maxFeintFlash = 0.30; // longer, more GO-like later
  static const double _goWindowBase = 2.4; // post-GO window at draw 0
  static const double _goWindowMin = 1.1; // tightest post-GO window
  static const double _goWindowRampPerDraw = 0.22; // window shrink per draw
  static const double _lingerAfterWin = 0.9; // hold the KO beat before next draw
  static const double _interDrawSec = 1.1; // beat between draws (cue + reset)

  // ── Strike / feel tuning ────────────────────────────────────────────────────
  static const double _strikeFlashSec = 0.45; // blinding flash + screen-flash
  static const double _strikeWordSec = 0.55; // STRIKE word punch-in then fade
  static const double _slashLifeSec = 0.55; // slash arc + speed-line life
  static const double _tooSoonLifeSec = 1.4; // "TOO SOON!" stamp life
  static const double _hitStopSec = 0.22; // slow-mo on the decisive strike
  static const double _hitStopScale = 0.12;
  static const double _matchPointCueSec = 1.5; // "MATCH POINT!" banner life

  // ── The learnable read: rising-ping + visible reward tuning ──────────────────
  // The real GO fires a rising "ping" (expanding rings the feint never fires) and
  // a visible reward (reaction-ms + a read streak) so a sharp read feels earned.
  static const double _goPingSec = 0.7; // rising-ping expand/fade life
  static const double _readRewardSec = 1.3; // reaction-ms + streak popup life
  static const double _feintJitterHz = 1.0; // bluff wobble clock multiplier
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
  static const Color _matchPointGold = Color(0xFFFFE45C);
  static const Color _tallyOn = Color(0xFFFFE45C); // won-draw pip fill

  // ── Per-zone signal (the unmistakable kid-clear cue) ─────────────────────────
  // Each player's whole zone is washed RED while waiting, then flashes a sudden
  // bright GREEN on GO ("DRAW!"). The wash is the dominant signal; the samurai
  // figures + center cue ride on top as flavor. A false-starter's zone goes a
  // calm grey with a gentle "TOO EARLY!" — readable, never harsh.
  static const Color _zoneRed = Color(0xFFE53935); // WAIT red
  static const Color _zoneGreen = Color(0xFF24D16A); // GO green
  static const Color _zoneAmber = Color(0xFFE6A23C); // FEINT amber (the bluff)
  static const Color _zoneGrey = Color(0xFF6B6B72); // false-start grey
  static const double _zoneWaitAlpha = 0.30; // resting red wash strength
  static const double _zoneWaitPulse = 0.10; // red wash throb amplitude
  static const double _zoneGoBaseAlpha = 0.42; // steady green while GO holds
  static const double _zoneGoFlashAlpha = 0.45; // extra green at the GO edge
  // FEINT wash sits visibly below the real GO's steady green so the bluff can
  // never pass for the genuine signal — amber + dim + a fast nervous flicker.
  static const double _zoneFeintAlpha = 0.22; // resting amber bluff strength
  static const double _zoneFeintPulse = 0.12; // amber nervous flicker amplitude
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

  // ── The learnable read (visible reward) ──────────────────────────────────────
  // The real GO's rising "ping" + the reaction-ms / streak payoff. Cleared per
  // draw. The ping is the ONE cue the feint never fires, so it teaches the read.
  double _goPing = 0; // 1 → 0 over [_goPingSec]: expanding-ring ping on real GO
  double _readReward = 0; // 1 → 0 over [_readRewardSec]: reaction-ms + streak pop
  int _rewardMs = 0; // winner's reaction time (ms) on the current reward pop
  int _rewardStreak = 0; // read streak shown on the current reward pop
  int _rewardColorArgb = 0xFFFFFFFF; // winner color for the reward pop
  int _readStreak = 0; // consecutive draws won by the same duelist
  int? _lastDrawWinner; // who won the previous draw (drives the streak)

  // ── Best-of "first to N draws" state ────────────────────────────────────────
  int _drawIndex = 0; // 0-based index of the current draw (drives the ramp)
  bool _between = false; // in the short inter-draw beat (cue + reset)
  double _betweenTimer = 0; // time spent in the inter-draw beat
  bool _drawScored = false; // this draw's outcome has been banked
  double _matchPointCue = 0; // 1 → 0 life of the "MATCH POINT!" banner
  final Map<int, int> _drawsWon = <int, int>{}; // draws won per player
  final Map<int, double> _totalReaction = <int, double>{}; // Σ valid reactions

  final Map<int, _Reactor> _reactors = <int, _Reactor>{};
  final List<Slash> _slashes = <Slash>[]; // active slash arcs (winner→loser)

  /// The current draw is "match point" once any duelist sits one draw away from
  /// taking the match — used only for the cue banner + gold bloom.
  bool get _isMatchPoint {
    for (final won in _drawsWon.values) {
      if (won >= _targetDraws - 1) return true;
    }
    return false;
  }

  /// Read-only HUD/telemetry: the running READ streak (consecutive draws won by
  /// the same duelist). Drives the "READ x2 ▲" reward badge; exposed so the HUD
  /// and tests can observe that a sharp read is rewarded. 0 between streaks.
  int get readStreak => _readStreak;

  /// Read-only HUD/telemetry: the reaction time (ms) banked on the most recent
  /// clean winning tap — the proof the read was fast. 0 before any draw is won.
  int get lastReadMs => _rewardMs;

  /// Read-only: true while the REAL GO is showing and still unclaimed — the
  /// window where a tap wins. A feint is NOT the GO, so this stays false through
  /// every bluff. Lets a coach/replay (and tests) act on the genuine signal only,
  /// proving the read is the skill: tap when this is true, never on a feint.
  bool get isGoOpen =>
      !_between && _signalSeen && _gate.phase == ReactionPhase.go;

  /// True while a fake-GO flash is lit before the real signal — the field bluffs
  /// green to bait a tap, but the gate is still WAITING so any tap is an early
  /// false start. Cleared the instant the real GO fires.
  bool get _feintLit => !_signalSeen && _gate.feintActive;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _gate = _gateForDraw(0);
    _size = ctx.arena;
    _center = Offset(_size.width / 2, _size.height * 0.5);

    _proportions = StickProportions.hero.scaled(_figureScale);
    _scaleUnit = _proportions.torsoWidth;
    // Legs are near-vertical at rest, so pelvis→foot ≈ thigh + shin.
    _footReach = _proportions.thigh + _proportions.shin;

    for (final p in ctx.players) {
      _drawsWon[p.id] = 0;
      _totalReaction[p.id] = 0;
    }
    _buildDuelists();
    begin();
  }

  /// Build the gate for draw [index] with the calibrated ramp: the GO band
  /// drifts later, feints grow more numerous + more GO-like (longer flashes),
  /// and (via [_goWindowForDraw]) the post-GO window tightens as [index] climbs.
  /// All escalation is bounded so even a long match stays fair and finite.
  ReactionGate _gateForDraw(int index) {
    final shift =
        math.min(_goDelayRampMax, _goDelayRampPerDraw * index).toDouble();
    final feints = math.min(_maxFeints, _baseFeints + index);
    final flash = math.min(
      _maxFeintFlash,
      _baseFeintFlash + (_maxFeintFlash - _baseFeintFlash) * (index / 4.0),
    );
    return ReactionGate(
      ctx.rng,
      minDelay: _minGoDelay + shift,
      maxDelay: _maxGoDelay + shift,
      feints: feints,
      feintFlashSec: flash,
    );
  }

  /// Post-GO reaction window for draw [index]: starts at [_goWindowBase] and
  /// tightens by [_goWindowRampPerDraw] each draw down to [_goWindowMin], so a
  /// late or hesitant tap stops counting sooner as the match tightens.
  double _goWindowForDraw(int index) =>
      math.max(_goWindowMin, _goWindowBase - _goWindowRampPerDraw * index);

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
  /// centre, fresh clock, per-draw gun-jump roll). Shared by the first build and
  /// each draw reset so the two never drift.
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

    // The short beat between draws: hold a cue, then arm the next draw.
    if (_between) {
      _betweenTimer += dt;
      if (_betweenTimer >= _interDrawSec) _beginNextDraw();
      // Absolute safety net even mid-transition.
      if (_elapsed >= _timeLimit) _finishFromDraws();
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
    _goPing = 1.0; // the rising ping: a real-GO-only cue the feint never fires
    _juice.shake.medium();
    _juice.hitStop.trigger(0.06);
    // A bright GREEN screen flash on the real GO — the unmistakable "now!" cue.
    _juice.flashScreen(_zoneGreen, strength: 0.5);
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
    if (_matchPointCue > 0) {
      _matchPointCue =
          (_matchPointCue - dt / _matchPointCueSec).clamp(0.0, 1.0);
    }
    if (_goPing > 0) {
      _goPing = (_goPing - dt / _goPingSec).clamp(0.0, 1.0);
    }
    if (_readReward > 0) {
      _readReward = (_readReward - dt / _readRewardSec).clamp(0.0, 1.0);
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
  /// and strong bots hold. A stalled GO closes its own window (tightening per
  /// draw) so a draw of all-false-starts still resolves.
  void _driveBots(double dt) {
    final inGo = _gate.phase == ReactionPhase.go;
    if (inGo) {
      _sinceGo += dt;
      if (_gate.winner == null && _sinceGo >= _goWindowForDraw(_drawIndex)) {
        _gate.forceDone();
      }
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
        // A valid-but-late draw: a small clash spark, no KO, no draw won.
        _juice.hit(_chestOf(reactor), _colorOf(id), sparks: 5);
        reactor.figure.dash();
      case ReactionTap.ignored:
        break;
    }
  }

  /// The winning quick-draw: turn toward the field and whip out a horizontal
  /// slash that arcs to each loser (KO-flinging them), under a slow-mo beat, with
  /// a big "STRIKE!" popup. The draw itself is banked in [_tallyDraw].
  void _onStrike(_Reactor winner) {
    final reaction = _gate.reactionTimes[winner.slot.id] ?? _decisiveRefSec;
    final decisive =
        (1.0 - (reaction / _decisiveRefSec)).clamp(0.0, 1.0); // 0..1
    final color = _colorOf(winner.slot.id);

    // VISIBLE REWARD for the read: bank the reaction time (ms) + advance a streak
    // (consecutive draws won by the SAME duelist) and pop them big, so nailing a
    // sharp tap on the real GO feels earned — not just "you didn't false-start".
    _readStreak =
        (winner.slot.id == _lastDrawWinner) ? _readStreak + 1 : 1;
    _lastDrawWinner = winner.slot.id;
    _rewardMs = (reaction * 1000).round();
    _rewardStreak = _readStreak;
    _rewardColorArgb = winner.slot.colorArgb;
    _readReward = 1.0;

    // Face the loser cluster, level the blade at them, and snap into a full-body
    // VICTORY hold (fired once per draw) so the "FASTEST!" banner lands on a
    // triumphant pose instead of a frozen idle. The slash arc itself is a
    // separate effect drawn from the blade tip below, so the cheer doesn't eat
    // the strike read.
    final faceDir = _loserDirection(winner);
    winner.figure
      ..facing = faceDir
      ..aimAngle = faceDir >= 0 ? 0.0 : math.pi;
    if (!winner.cheered) {
      winner.cheered = true;
      winner.figure.victory();
    }

    _juice.hitStop.trigger(_hitStopSec, scale: _hitStopScale);
    // Signature FASTEST! cinematic: burst + shake + slow-mo + zoom toward the
    // winning duelist + flash + banner + haptic. Fired once per decisive draw.
    _juice.bigMoment(_chestOf(winner), color, banner: 'FASTEST!');
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
    final fling =
        Offset(dirX * mag * _flingSidewaysFactor, -mag * _flingLiftFactor);
    final groundY = loser.foot.dy;
    loser.figure.enterRagdoll(_rootOf(loser), groundY, fling);
  }

  /// A false start: the gate already penalized them (they LOSE this draw). Stamp
  /// "TOO SOON!", stagger them with a hurt pose, and a light shake.
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

  /// Live HUD score: cumulative draws won plus a tiny (<1) in-draw nudge so a
  /// faster reaction edges ahead and a false-starter dips, while the draw tally
  /// always dominates — kids watch the win count climb toward the target.
  void _publishLiveScores() {
    final times = _gate.reactionTimes;
    final penalized = _gate.penalized;
    for (final p in ctx.players) {
      final base = (_drawsWon[p.id] ?? 0).toDouble();
      if (penalized.contains(p.id)) {
        setScore(p.id, base - 0.001); // a dip for a false start this draw
      } else {
        final t = times[p.id];
        // Tiny in-draw nudge (<1) so cumulative draws always dominate.
        setScore(p.id, base + (t != null ? 0.001 / (t + 0.01) : 0));
      }
    }
  }

  // ── Outcome ("first to N draws") ────────────────────────────────────────────

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
      if (_sinceDone >= _lingerAfterWin) _onDrawOver();
    }
    // Absolute safety net: never exceed the time limit.
    if (_elapsed >= _timeLimit && status == MiniGameStatus.running) {
      _gate.forceDone();
      _tallyDraw();
      _finishFromDraws();
    }
  }

  /// A draw has fully resolved (winner + linger done): bank it, then either
  /// finish the match (someone reached the target / we hit the draw cap) or kick
  /// off the inter-draw beat.
  void _onDrawOver() {
    _tallyDraw();
    if (matchWon(_drawsWon, _targetDraws) || _drawIndex + 1 >= _maxDraws) {
      _finishFromDraws();
    } else {
      _beginInterDraw();
    }
  }

  /// Bank this draw's outcome: award the single draw to the gate's [winner] (the
  /// fastest valid tap; none if the draw was a wash), and fold every duelist's
  /// valid reaction into the cumulative tiebreak total. Idempotent per draw via
  /// [_drawScored] so a tally + safety-net can't double-count.
  void _tallyDraw() {
    if (_drawScored) return;
    _drawScored = true;
    // A washed draw (no valid tap — a timed-out GO or all false starts) breaks
    // any running read streak, so the streak only ever counts cleanly-won draws.
    if (_gate.winner == null) {
      _readStreak = 0;
      _lastDrawWinner = null;
    }
    final award = drawAward(
      ctx.players.map((p) => p.id).toList(),
      _gate.winner,
    );
    award.forEach((id, delta) {
      _drawsWon[id] = (_drawsWon[id] ?? 0) + delta;
    });
    _gate.reactionTimes.forEach((id, t) {
      _totalReaction[id] = (_totalReaction[id] ?? 0) + t;
    });
  }

  /// Open the inter-draw beat; [update] times it out then arms the next draw.
  void _beginInterDraw() {
    _between = true;
    _betweenTimer = 0;
  }

  /// Arm the next draw: bump the index, roll a fresh gate via the calibrated
  /// ramp ([_gateForDraw]), reset every duelist to a ready stance, clear the
  /// draw-scoped fx + flags, and raise the MATCH POINT cue when a duelist is one
  /// draw from taking the match.
  void _beginNextDraw() {
    _drawIndex += 1;
    _between = false;
    _betweenTimer = 0;
    _drawScored = false;
    _signalSeen = false;
    _confettiFired = false;
    _feintLitLast = false;
    _goPing = 0; // the new draw arms fresh; ping fires again on its real GO
    _readReward = 0;
    _sinceDone = 0;
    _sinceGo = 0;
    _slashes.clear();

    _gate = _gateForDraw(_drawIndex);
    _resetDuelistsForDraw();

    if (_isMatchPoint) {
      _matchPointCue = 1.0;
      _juice.shake.medium();
      final center = Offset(_size.width / 2, _size.height * _cueCenterFrac);
      _juice.popup(center, 'MATCH POINT!', _matchPointGold, size: 42);
    }
  }

  /// Reset each duelist for a fresh draw by rebuilding it at the same foot anchor
  /// (un-ragdolls, re-poses, re-arms). Draws won live outside the reactors.
  void _resetDuelistsForDraw() {
    for (final p in ctx.players) {
      final old = _reactors[p.id];
      if (old == null) continue;
      _reactors[p.id] = _makeReactor(p, old.foot);
    }
  }

  /// Build the final ranking from draws won (best→worst), with the cumulative
  /// reaction total as a gentle tiebreak (see [buildDuelRanking]). Every player
  /// id appears exactly once.
  void _finishFromDraws() {
    if (status == MiniGameStatus.finished) return;
    _publishLiveScores();

    final ids = buildDuelRanking(
      ctx.players.map((p) => p.id).toList(),
      _drawsWon,
      _totalReaction,
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
    _juice.applyWorldTransform(canvas);

    ReactionRenderer.drawBackground(canvas, size, _animClock);
    ReactionRenderer.drawGround(canvas, size);
    ReactionRenderer.drawVignette(canvas, size, _vignettePulse());

    // The per-zone RED→GREEN wash is the dominant, kid-clear signal. Drawn under
    // the figures so the swordsmen sit on top of their colored ground.
    _drawZoneWashes(canvas, size);

    // Match point gets a brief gold edge bloom so the climax reads at a glance.
    if (_matchPointCue > 0) {
      ReactionRenderer.drawLightningAmbience(
          canvas, size, _matchPointCue, _waitPulse(),
          gold: _matchPointGold);
    }

    _drawDuelists(canvas);
    _drawSlashes(canvas);

    // Big per-zone word ("WAIT" / "DRAW!" / "TOO EARLY!") over the figures so
    // every player reads their own state at a glance.
    _drawZoneLabels(canvas, size);

    // THE LEARNABLE READ. A feint paints the AMBER, jittery "FAKE" cue — never
    // the green GO — so a sharp player learns to ignore it. The real GO is the
    // punchy green "GO!" with its rising ping (below). Same center slot so both
    // demand a read, but they look unmistakably different.
    final feinting = _feintLit;
    ReactionRenderer.drawCenterCue(
      canvas,
      size,
      struck: _signalSeen,
      strikeFlash: feinting ? 1.0 : _strikeFlash,
      strikeWord: feinting ? 1.0 : _strikeWord,
      waitPulse: _waitPulse(),
      centerFrac: _cueCenterFrac,
      feint: feinting,
      jitter: (_animClock * _feintJitterHz) % 1.0,
    );

    // The rising GO PING — expanding rings the feint NEVER fires, drawn world-
    // space so it blooms from the same center as the cue. The single cue that
    // teaches "this one is real".
    if (_goPing > 0) {
      ReactionRenderer.drawGoPing(canvas, size, 1.0 - _goPing);
    }

    _juice.render(canvas);
    canvas.restore();

    // Screen-space HUD (draw tally + "FIRST TO N") + cinematic overlays (GO
    // flash + FASTEST! banner) after the world transform is restored, so they
    // are not shaken or zoomed. The GO wash is the green [Juice.flashScreen]
    // overlay fired once on the signal edge.
    _drawDrawTally(canvas, size);
    _juice.renderOverlay(canvas, size);

    // The VISIBLE REWARD for the read: the winner's reaction time (ms) + a read
    // streak ▲, popped screen-space under the center cue so a sharp tap feels
    // earned. Drawn last so it reads clearly over everything.
    if (_readReward > 0) {
      ReactionRenderer.drawReadReward(
        canvas,
        size,
        reactionMs: _rewardMs,
        streak: _rewardStreak,
        color: Color(_rewardColorArgb),
        life: _readReward,
        centerFrac: _cueCenterFrac,
      );
    }
  }

  /// The "first to N draws" HUD: a per-player tally of won-draw pips plus the
  /// target, drawn screen-space along the top so the objective + standings read
  /// at a glance. Built no-throw from plain snapshots.
  void _drawDrawTally(Canvas canvas, Size size) {
    final rows = <DrawTallyRow>[
      for (final p in ctx.players)
        DrawTallyRow(
          color: _colorOf(p.id),
          won: _drawsWon[p.id] ?? 0,
        ),
    ];
    ReactionRenderer.drawDrawTally(
      canvas,
      size,
      rows: rows,
      target: _targetDraws,
      onColor: _tallyOn,
    );
  }

  /// Vignette pulse: dark + throbbing during WAIT (rising tension), calm after.
  double _vignettePulse() {
    if (_gate.phase != ReactionPhase.waiting) return 0.0;
    final ramp =
        (_elapsed / (_maxGoDelay + _goDelayRampMax)).clamp(0.0, 1.0);
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
      _drawDuelistWithWaitSway(canvas, r, locked);

      // Per-duelist readout above the head: a small reaction time once they
      // draw, for flavor. The WAIT/DRAW/TOO-EARLY state is carried by the big
      // per-zone wash + word; a false start adds a gentle X over the figure.
      final above = _chestOf(r).translate(0, -_scaleUnit * 2.4);
      ReactionRenderer.drawReadout(
          canvas, above, _scaleUnit, _readoutFor(r), _colorOf(r.slot.id));

      if (r.tooSoon > 0) {
        ReactionRenderer.drawEarlyX(canvas, _chestOf(r), _scaleUnit, r.tooSoon);
      }
    }
  }

  // ── Wait-phase micro-sway ───────────────────────────────────────────────────
  // Tiny tuning for a pure-visual ready-stance breathing tilt while the field
  // holds its nerve through WAIT. Render only — touches no scoring/draw state.
  static const double _waitSwayRad = 0.025; // peak tilt (radians) during WAIT
  static const double _waitSwayHz = 1.6; // sway speed

  /// Draw a duelist, adding a faint breathing sway (a small tilt about the feet)
  /// ONLY while the gate is still WAITING and the duelist isn't locked out — a
  /// touch of life in the standoff. Purely visual: it never changes the figure's
  /// pose state, position, or any game value, so the strike still reads instantly.
  void _drawDuelistWithWaitSway(Canvas canvas, _Reactor r, bool locked) {
    final swaying = !locked && _gate.phase == ReactionPhase.waiting;
    if (!swaying) {
      ReactionRenderer.drawDuelist(canvas, r.figure, _rootOf(r));
      return;
    }
    // Per-duelist phase offset (from foot x) so the row doesn't sway in lockstep.
    final tilt = _waitSwayRad *
        math.sin(_animClock * _waitSwayHz + r.foot.dx * 0.02);
    final pivot = r.foot;
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(tilt);
    canvas.translate(-pivot.dx, -pivot.dy);
    ReactionRenderer.drawDuelist(canvas, r.figure, _rootOf(r));
    canvas.restore();
  }

  void _drawSlashes(Canvas canvas) {
    for (final s in _slashes) {
      ReactionRenderer.drawSlashArc(canvas, s.from, s.to, s.color, s.life);
      ReactionRenderer.drawSpeedLines(canvas, s.from, s.to, s.color, s.life);
    }
  }

  /// Wash each player's whole zone with its signal color — the unmistakable
  /// cue. RED while waiting (gentle throb), a sudden bright GREEN on GO (a flash
  /// that spikes at the edge then settles to a steady "DRAW!" green), GREEN for a
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
      // Bright GREEN that SUSTAINS: a flash spike at the GO edge that settles to a
      // steady, held "DRAW" green for the whole window — the real signal holds.
      return (_zoneGreen, _zoneGoBaseAlpha + _zoneGoFlashAlpha * _strikeFlash);
    }
    if (_feintLit) {
      // FAKE GO: an AMBER, dimmer, jittery wash — clearly NOT the GO-green, so the
      // zone itself teaches the read. A fast throb keeps it nervous/flickery and
      // the alpha sits below the real GO's steady green, so it never passes for it.
      final flick = 0.5 + 0.5 * math.sin(_animClock * _vignettePulseHz * 2.4);
      return (_zoneAmber, _zoneFeintAlpha + _zoneFeintPulse * flick);
    }
    // Waiting: a gently throbbing RED so the kid feels "not yet".
    final throb = 0.5 + 0.5 * math.sin(_animClock * _vignettePulseHz);
    return (_zoneRed, _zoneWaitAlpha + _zoneWaitPulse * throb);
  }

  /// The big readable word for a player's zone: "WAIT" (red), "DRAW!" (green),
  /// "WINNER!" / "GOT IT!" once drawn, or a gentle "TOO EARLY!" on a false start.
  (String, Color) _zoneLabel(int id) {
    if (_gate.penalized.contains(id)) {
      return ('TOO EARLY!', const Color(0xFFFFFFFF));
    }
    if (_gate.winner == id) return ('WINNER!', const Color(0xFFFFFFFF));
    if (_gate.reactionTimes.containsKey(id)) {
      return ('GOT IT!', const Color(0xFFFFFFFF));
    }
    // The real GO — and ONLY the real GO — shows the green "DRAW!" word. A feint
    // shows a small amber "FAKE?" instead (never "DRAW!"), so the zone word is a
    // learnable tell: green DRAW! = tap now, amber FAKE? = hold.
    if (_signalSeen) return ('DRAW!', const Color(0xFFFFFFFF));
    if (_feintLit) return ('FAKE?', _zoneAmber);
    return ('WAIT', const Color(0xFFFFFFFF));
  }

  /// The small flavor text above a duelist: their reaction time once they draw,
  /// nothing otherwise (the per-zone word carries the WAIT/DRAW/EARLY state).
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

/// Per-player reaction state for one draw. Mutable draw-scoped state (allowed for
/// the duration of a single draw).
class _Reactor {
  final PlayerSlot slot;
  final Offset foot; // ground anchor (foot line) for this duelist
  final StickFigure figure;
  final ReactionClock clock;
  final bool jumpsTheGun; // bot decided to false-start this draw

  bool acted = false;
  bool cheered = false; // fired the one-shot victory hold on a winning strike
  double tooSoon = 0; // 1 → 0 life of the "TOO SOON!" stamp

  _Reactor({
    required this.slot,
    required this.foot,
    required this.figure,
    required this.clock,
    required this.jumpsTheGun,
  });
}
