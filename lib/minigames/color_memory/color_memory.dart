import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'memory_render.dart';

/// Round phase. [showing] flashes the sequence (the light show); [input] takes
/// each player's reproduction by direct pad taps.
enum _Phase { showing, input }

/// Per-player reproduction state for the current round. Mutable round-scoped
/// state (allowed for the duration of one round).
class _Pad {
  final int playerId;
  final Color accent;
  bool alive = true;
  bool done = false; // finished this round's reproduction correctly
  int progress = 0; // correct entries so far this round
  int retriesLeft = 0; // forgiving extra tries this round (round 1 only)
  double koFlash = 0; // 0..1 elimination flash that fades after a KO
  double oopsFlash = 0; // 0..1 gentle "wrong, try again" flash on a forgiven miss
  final ReactionClock? clock;

  /// Bot only: the step index at which this bot will deliberately slip THIS
  /// round (or -1 = it will reproduce the whole pattern correctly). Decided once
  /// per round so a single slip ends a bot's run — instead of re-rolling the
  /// error on every entry, which used to wipe everyone before the pattern could
  /// ever grow. Difficulty + sequence length set how likely/early a slip is.
  int mistakeStep = -1;

  /// Per-pad bloom 0..1 (red, blue, green, yellow). Lit pads bloom bright and
  /// decay for an afterglow; purely cosmetic so it never affects logic.
  final List<double> bloom = <double>[0, 0, 0, 0];

  _Pad({required this.playerId, required this.accent, this.clock});

  void bumpBloom(int slot) {
    if (slot >= 0 && slot < bloom.length) bloom[slot] = 1.0;
  }

  void decay(double dt, double perSec) {
    for (var i = 0; i < bloom.length; i++) {
      if (bloom[i] > 0) bloom[i] = math.max(0, bloom[i] - perSec * dt);
    }
    if (koFlash > 0) koFlash = math.max(0, koFlash - dt);
    if (oopsFlash > 0) oopsFlash = math.max(0, oopsFlash - dt);
  }
}

/// Color Memory — a classic Simon a young child can read at a glance.
///
/// Rule (documented, one clear scheme):
///  * Each round the shared color sequence first **plays back**: the matching
///    colored pad flashes on every cluster, one at a time ([_Phase.showing], the
///    "light show"). A central orb echoes the current color so it reads across
///    the room.
///  * Then everyone **repeats it by TAPPING their own colored pads directly, in
///    order** ([_Phase.input]). The pads are big quadrants in each player's zone;
///    a tap is hit-tested to the quadrant it lands in (forgiving, finger-sized
///    targets) and that real color is the player's next entry:
///    - correct → progress advances; once progress == sequence length the player
///      has cleared the round and waits;
///    - wrong → that player is eliminated ([Juice.ko]) — except on round 1, where
///      everyone gets a single forgiving retry ([_round1Retries]): the first
///      wrong tap just buzzes "OOPS" and lets them try the same step again.
///  * A tap that misses every pad (the center hub / a gap) is ignored, so a
///    fumbled touch never eliminates a kid.
///
/// When the round resolves, the sequence grows by one and replays. Last player
/// standing wins via [finishByOrder].
///
/// Termination is guaranteed several ways: a per-round input deadline
/// ([_roundDeadlineSec]) eliminates anyone who hasn't finished, a sequence
/// length cap ([_maxSeqLen]), last-player-standing, and the overall
/// [_timeLimit].
class ColorMemory extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'color_memory',
        name: 'Color Memory',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  // ── Rules / timing tuning (no magic numbers inline) ─────────────────────────
  static const int _palette = 4;
  static const double _timeLimit = 45;
  static const double _showStepSec = 0.6; // per-color flash during showing (slow, clear)
  static const double _showStepMinSec = 0.34; // floor as the show speeds up
  static const double _showLeadSec = 0.5; // calm beat before the light show
  static const double _roundDeadlineSec = 8.0; // generous cap on one input phase
  static const int _maxSeqLen = 20; // absolute cap so it always terminates
  static const int _startSeqLen = 1;
  static const int _round1Retries = 1; // forgiving extra tries on round 1

  // ── Climax: the DRUMROLL on a long pattern (the unmistakable peak) ──────────
  // Once the sequence reaches [_climaxSeqLen] the light show speeds up toward
  // [_showStepMinSec] (a longer pattern flashed faster = the hardest recall) and
  // a one-shot "DRUMROLL!" banner + a tightening tick of shakes during the
  // lead-in announces that this is the big one. Pure tension; the forgiving
  // round-1 retry is untouched.
  static const int _climaxSeqLen = 5; // sequence length that triggers the drumroll
  static const int _speedUpRefLen = 9; // pattern length that reaches the floor
  static const double _drumrollTickSec = 0.12; // gap between lead-in drum ticks
  static const Color _white = Color(0xFFFFFFFF); // climax banner ink

  // ── Bot memory model (fairness) ─────────────────────────────────────────────
  // A bot rolls ONE planned slip per round (not per entry). The chance it slips
  // grows with how many colors it must hold this round, scaled by difficulty via
  // [BotProfile.errorRate] — so difficulty reads as "how long a pattern the CPU
  // can remember". Short patterns are reproduced reliably, so the sequence
  // actually grows and the memory tension lands instead of a first-step coin
  // flip wiping the field.
  static const double _botSlipPerColor = 0.16; // added slip chance per color held
  static const double _botSlipCap = 0.85; // never a guaranteed slip
  static const int _botFreeRecall = 1; // colors a bot always nails (no slip)
  // Bots tap a little after the GO so an easy human can out-react them, and so
  // the light show clearly finishes before the first bot answer lands.
  static const double _botFirstAnswerDelaySec = 0.6;

  // ── Feel tuning ─────────────────────────────────────────────────────────────
  static const double _bloomDecayPerSec = 2.6; // pad afterglow fade rate
  static const double _flashHoldFrac = 0.6; // share of a step the orb stays lit
  static const double _koFlashSec = 0.5;
  static const double _oopsFlashSec = 0.45;
  static const double _bannerThrobHz = 2.4;

  late Juice _juice;
  final List<int> _sequence = [];
  final List<_Pad> _pads = [];

  // Elimination order (worst→best) used to build the final ranking.
  final List<int> _outOrder = [];

  _Phase _phase = _Phase.showing;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock for pulses (never time-scaled)
  double _phaseTimer = 0; // time spent in the current phase
  int _showIndex = -1; // which sequence color is flashing (-1 = lead-in)
  int _round = 1; // 1-based round counter (== sequence length)
  bool _drumrollAnnounced = false; // the climax banner fired for this round
  double _drumrollAcc = 0; // banks lead-in time toward each drum tick
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    for (final p in ctx.players) {
      _pads.add(_Pad(
        playerId: p.id,
        accent: Color(p.colorArgb),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
    for (var i = 0; i < _startSeqLen; i++) {
      _sequence.add(ctx.rng.intRange(0, _palette));
    }
    _enterShowing();
    begin();
  }

  // ---- Phase transitions ----------------------------------------------------

  void _enterShowing() {
    _phase = _Phase.showing;
    _phaseTimer = 0;
    _showIndex = -1; // lead-in beat before the first color lights
    _drumrollAnnounced = false;
    _drumrollAcc = 0;
  }

  /// True when the current pattern is long enough to be a climax round (the
  /// faster, drumrolled "big one").
  bool get _isClimaxRound => _sequence.length >= _climaxSeqLen;

  /// Per-color flash duration for the CURRENT pattern: a long pattern is flashed
  /// faster (toward [_showStepMinSec]) so recall gets genuinely harder near the
  /// end, while short early patterns stay slow and clear for little kids.
  double _currentShowStepSec() {
    final len = _sequence.length;
    if (len <= _climaxSeqLen) return _showStepSec;
    final span = (_speedUpRefLen - _climaxSeqLen).clamp(1, _maxSeqLen);
    final t = ((len - _climaxSeqLen) / span).clamp(0.0, 1.0);
    return _showStepSec + (_showStepMinSec - _showStepSec) * t;
  }

  void _enterInput() {
    _phase = _Phase.input;
    _phaseTimer = 0;
    for (final pad in _pads) {
      if (!pad.alive) continue;
      pad.progress = 0;
      pad.done = false;
      pad.retriesLeft = _round == 1 ? _round1Retries : 0;
      if (pad.clock != null) {
        pad.clock!.arm(ctx.botProfile, ctx.rng);
        pad.mistakeStep = _rollBotMistakeStep();
      }
    }
  }

  /// Decide, once for the round, whether a bot slips and where. Returns the step
  /// index of the slip, or -1 if the bot will reproduce the whole pattern.
  ///
  /// Slip chance scales with the pattern length and the profile's [errorRate]
  /// (easy bots slip on shorter patterns, hard bots hold longer). The first
  /// [_botFreeRecall] colors are always safe so a fresh round never collapses on
  /// step one. When a slip is chosen its step is biased toward later entries
  /// (memory fatigue), which both feels right and lets the sequence build.
  int _rollBotMistakeStep() {
    final len = _sequence.length;
    if (len <= _botFreeRecall) return -1;
    final recallable = len - _botFreeRecall;
    final slipChance =
        (ctx.botProfile.errorRate * recallable * _botSlipPerColor * _palette)
            .clamp(0.0, _botSlipCap);
    if (!ctx.rng.chance(slipChance)) return -1;
    // Bias the slip toward the back half of the recallable range.
    final lo = _botFreeRecall + recallable ~/ 2;
    return ctx.rng.intRange(lo, len);
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running ||
        _phase != _Phase.input ||
        input.phase != InputPhase.down) {
      return;
    }
    final pad = _padOf(input.playerId);
    if (pad == null || !pad.alive || pad.done) return;
    // Tap a real colored pad: hit-test the quadrant the touch landed in. A tap
    // that misses every pad (the hub / a gap) is ignored, never fatal.
    final slot = _padHitTest(input.playerId, input.normPos);
    if (slot < 0) return;
    _commit(pad, slot);
  }

  _Pad? _padOf(int id) {
    for (final p in _pads) {
      if (p.playerId == id) return p;
    }
    return null;
  }

  /// Map a full-screen 0..1 tap to one of the four pad slots in [playerId]'s
  /// cluster (0 = red TL, 1 = blue TR, 2 = green BL, 3 = yellow BR), or -1 if the
  /// tap is outside that player's pad plate. The plate is split into four equal
  /// quadrants (bigger than the drawn pads) so little fingers land reliably.
  int _padHitTest(int playerId, Offset normPos) {
    final index = _pads.indexWhere((p) => p.playerId == playerId);
    if (index < 0) return -1;
    final plate = _padBlockRect(_playerRegion(index, _pads.length));
    final px = normPos.dx * _lastSize.width;
    final py = normPos.dy * _lastSize.height;
    if (!plate.contains(Offset(px, py))) return -1;
    final col = px >= plate.center.dx ? 1 : 0;
    final row = py >= plate.center.dy ? 1 : 0;
    return row * 2 + col;
  }

  /// Apply a chosen color for [pad]: advance on a match, eliminate on a miss
  /// (with a forgiving round-1 retry). Fires the matching pad's bloom + a hit
  /// spark on a correct tap so taps feel solid.
  void _commit(_Pad pad, int color) {
    pad.bumpBloom(color);
    final expected = _sequence[pad.progress];
    if (color == expected) {
      pad.progress += 1;
      _juice.hit(_padCenter(pad.playerId), pad.accent, sparks: 6);
      if (pad.progress >= _sequence.length) {
        pad.done = true;
        _juice.popup(
            _padCenter(pad.playerId).translate(0, -_blockSide() * 0.5),
            'NICE!',
            pad.accent,
            size: 26);
      }
      return;
    }

    // Wrong color. On round 1 the first miss is forgiven: buzz "OOPS" and let
    // the kid try the same step again (progress unchanged).
    if (pad.retriesLeft > 0) {
      pad.retriesLeft -= 1;
      pad.oopsFlash = _oopsFlashSec;
      _juice.popup(
          _padCenter(pad.playerId).translate(0, -_blockSide() * 0.5),
          'OOPS!',
          MemoryRenderer.palette[3],
          size: 24);
      _juice.shake.light();
      return;
    }

    // Out of retries → a red "WRONG!" names the failure, then the KO beat.
    _juice.popup(
        _padCenter(pad.playerId).translate(0, -_blockSide() * 0.5),
        'WRONG!',
        MemoryRenderer.palette[0],
        size: 30);
    _eliminate(pad);
  }

  void _eliminate(_Pad pad) {
    if (!pad.alive) return;
    pad.alive = false;
    pad.koFlash = _koFlashSec;
    _outOrder.add(pad.playerId);
    _juice.ko(_padCenter(pad.playerId), pad.accent);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);
    _phaseTimer += sdt;

    for (final pad in _pads) {
      pad.decay(dt, _bloomDecayPerSec);
    }

    if (_phase == _Phase.showing) {
      _updateShowing(sdt);
    } else {
      _updateInput(sdt);
    }

    if (_elapsed >= _timeLimit) _finishNow();
  }

  /// Flash through the sequence (the light show): each step blooms every alive
  /// player's matching pad in lockstep + pops a spark at the central orb;
  /// advance to input once all colors have shown.
  void _updateShowing(double dt) {
    final step = _currentShowStepSec();
    final total = _showLeadSec + _sequence.length * step;

    // On a climax round, the lead-in is a building drumroll: a one-shot banner
    // plus a tightening tick of soft shakes so the kids feel the big one coming.
    if (_isClimaxRound && _showIndex < 0) _runDrumroll(dt);

    // Index of the color currently flashing, or -1 during the lead-in beat.
    final next = _phaseTimer < _showLeadSec
        ? -1
        : ((_phaseTimer - _showLeadSec) ~/ step)
            .clamp(0, _sequence.length - 1);
    if (next != _showIndex) {
      _showIndex = next;
      if (next >= 0) _flashSequenceColor(_sequence[next]);
    }
    if (_phaseTimer >= total) _enterInput();
  }

  /// The lead-in drumroll for a climax round: announce it once, then bank time
  /// toward evenly spaced soft shake "drum" ticks until the first color lights.
  void _runDrumroll(double dt) {
    if (!_drumrollAnnounced) {
      _drumrollAnnounced = true;
      final center = Offset(_lastSize.width / 2, _lastSize.height * 0.30);
      _juice.popup(center, 'DRUMROLL!', _white, size: 34);
    }
    _drumrollAcc += dt;
    var guard = 0;
    while (_drumrollAcc >= _drumrollTickSec && guard++ < 8) {
      _drumrollAcc -= _drumrollTickSec;
      _juice.shake.light();
    }
  }

  /// One light-show beat: bloom the color on every alive cluster + a central
  /// burst + a soft shake so the pattern is satisfying to watch.
  void _flashSequenceColor(int color) {
    for (final pad in _pads) {
      if (pad.alive) pad.bumpBloom(color);
    }
    final center = Offset(_lastSize.width / 2, _lastSize.height / 2);
    _juice.particles.burst(
      at: center,
      count: 10,
      color: MemoryRenderer.palette[color.clamp(0, _palette - 1)],
      speed: 220,
      size: 6,
      life: 0.5,
    );
    _juice.shake.light();
  }

  /// Drive bots, then resolve the round when everyone alive is done or the input
  /// deadline passes.
  void _updateInput(double dt) {
    _driveBots(dt);

    final deadlineHit = _phaseTimer >= _roundDeadlineSec;
    if (deadlineHit) {
      // Anyone who hasn't finished reproducing in time is out.
      for (final pad in _pads) {
        if (pad.alive && !pad.done) _eliminate(pad);
      }
    }

    if (_roundResolved()) _resolveRound();
  }

  /// Bots tap one pad per reaction tick. They reproduce the pattern from their
  /// per-round plan ([_Pad.mistakeStep]): correct on every step except the one
  /// planned slip, where they press a wrong color (→ elimination, unless a
  /// round-1 retry forgives it). This makes a bot's run a coherent "remembered N
  /// colors then fumbled" rather than an independent dice roll per tap, so
  /// patterns grow and difficulty is fair. The first answer is held a beat past
  /// the light show so a human can react first.
  void _driveBots(double dt) {
    if (_phaseTimer < _botFirstAnswerDelaySec) return;
    for (final pad in _pads) {
      if (pad.clock == null || !pad.alive || pad.done) continue;
      if (!pad.clock!.tick(dt)) continue;
      pad.clock!.arm(ctx.botProfile, ctx.rng);

      final expected = _sequence[pad.progress];
      final slips = pad.progress == pad.mistakeStep;
      _commit(pad, slips ? _wrongColor(expected) : expected);
    }
  }

  int _wrongColor(int expected) {
    final offset = ctx.rng.intRange(1, _palette);
    return (expected + offset) % _palette;
  }

  bool _roundResolved() {
    for (final pad in _pads) {
      if (pad.alive && !pad.done) return false;
    }
    return true;
  }

  /// Round over: check terminal conditions, else grow the sequence and replay.
  void _resolveRound() {
    final alive = _pads.where((p) => p.alive).length;

    // Last player standing (multi-player) ends the match.
    if (_pads.length > 1 && alive <= 1) {
      _finishNow();
      return;
    }
    // Everyone wiped simultaneously (e.g. single-player miss / mass deadline).
    if (alive == 0) {
      _finishNow();
      return;
    }
    // Sequence cap reached → stop here and rank survivors.
    if (_sequence.length >= _maxSeqLen) {
      _finishNow();
      return;
    }

    _sequence.add(ctx.rng.intRange(0, _palette));
    _round += 1;
    _enterShowing();
  }

  /// Build best→worst ranking: survivors first (more progress / longer-lived),
  /// then eliminated players in reverse knock-out order. Every id appears once.
  void _finishNow() {
    if (status == MiniGameStatus.finished) return;
    final survivors = _pads.where((p) => p.alive).toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    for (final pad in _pads) {
      // Score = entries cleared; survivors get full sequence-length credit.
      setScore(pad.playerId, pad.alive ? _sequence.length : pad.progress);
    }
    final ordered = <int>[
      ...survivors.map((p) => p.playerId),
      ..._outOrder.reversed,
    ];
    final seen = <int>{};
    final full = [
      for (final id in ordered)
        if (seen.add(id)) id,
    ];
    for (final p in ctx.players) {
      if (seen.add(p.id)) full.add(p.id);
    }
    finishByOrder(full);
  }

  // ---- Rendering ------------------------------------------------------------

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    MemoryRenderer.drawBackground(canvas, size);
    MemoryRenderer.drawVignette(canvas, size);

    final watching = _phase == _Phase.showing;
    _drawHud(canvas, size, watching);

    for (var i = 0; i < _pads.length; i++) {
      _drawCluster(canvas, _pads[i], i, watching);
    }

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawHud(Canvas canvas, Size size, bool watching) {
    final throb = 0.5 + 0.5 * math.sin(_animClock * _bannerThrobHz);
    MemoryRenderer.drawPhaseBanner(canvas, size,
        watching: watching, pulse: throb);
    MemoryRenderer.drawRoundCounter(canvas, size, _round);
    MemoryRenderer.drawSharedSequence(
      canvas,
      size,
      _sequence,
      shownCount: _showIndex + 1,
      watching: watching,
    );
    MemoryRenderer.drawFlashCore(
        canvas, size, _activeFlashColor(), _activeFlashStrength());
  }

  /// Color of the orb currently flashing during the light show (null otherwise).
  Color? _activeFlashColor() {
    if (_phase != _Phase.showing || _showIndex < 0) return null;
    return MemoryRenderer.palette[_sequence[_showIndex].clamp(0, _palette - 1)];
  }

  /// Orb brightness during a flash step: bright at the step start, eased to 0
  /// across [_flashHoldFrac] of the step so each color reads as a distinct beat.
  double _activeFlashStrength() {
    if (_phase != _Phase.showing || _showIndex < 0) return 0;
    final step = _currentShowStepSec();
    final intoStep = (_phaseTimer - _showLeadSec) - _showIndex * step;
    final hold = step * _flashHoldFrac;
    if (intoStep < 0 || intoStep > hold) return 0;
    return (1.0 - intoStep / hold).clamp(0.0, 1.0);
  }

  /// Draw one player's Simon cluster + identity tab + progress pips, plus the
  /// elimination stamp once they are out. During input the whole plate gives a
  /// gentle "your turn" pulse so a kid knows it is time to tap the colors (no
  /// per-pad cursor); a forgiven miss flashes the plate.
  void _drawCluster(Canvas canvas, _Pad pad, int index, bool watching) {
    final block = _padBlockRect(_playerRegion(index, _pads.length));
    final turnPulse = (!watching && pad.alive && !pad.done)
        ? 0.5 + 0.5 * math.sin(_animClock * _bannerThrobHz)
        : 0.0;

    MemoryRenderer.drawCluster(
      canvas,
      block,
      blooms: pad.bloom,
      alive: pad.alive,
      done: pad.done,
      accent: pad.accent,
      turnPulse: turnPulse,
      oops: pad.oopsFlash > 0
          ? (pad.oopsFlash / _oopsFlashSec).clamp(0.0, 1.0)
          : 0.0,
    );
    MemoryRenderer.drawPlayerTab(canvas, block, pad.accent, pad.playerId + 1,
        alive: pad.alive);
    MemoryRenderer.drawProgress(
        canvas, block, _sequence.length, pad.progress, pad.accent,
        alive: pad.alive);

    if (!pad.alive) {
      // Stamp fades in over the KO flash window, then holds.
      final stamp = pad.koFlash > 0
          ? (1.0 - pad.koFlash / _koFlashSec).clamp(0.0, 1.0)
          : 1.0;
      MemoryRenderer.drawEliminated(canvas, block, stamp);
    }
  }

  // ---- Layout helpers -------------------------------------------------------

  /// Normalized region for a player's cluster (mirrors ZoneLayout sensibilities;
  /// reserves the top strip for the HUD).
  Rect _playerRegion(int index, int count) {
    switch (count) {
      case 1:
        return const Rect.fromLTRB(0.18, 0.36, 0.82, 0.82);
      case 2:
        return index == 0
            ? const Rect.fromLTRB(0.18, 0.56, 0.82, 0.92)
            : const Rect.fromLTRB(0.18, 0.24, 0.82, 0.50);
      case 3:
        if (index == 0) return const Rect.fromLTRB(0.30, 0.60, 0.70, 0.92);
        return index == 1
            ? const Rect.fromLTRB(0.06, 0.26, 0.46, 0.52)
            : const Rect.fromLTRB(0.54, 0.26, 0.94, 0.52);
      default:
        final left = index.isEven;
        final bottom = index < 2;
        final l = left ? 0.07 : 0.55;
        final t = bottom ? 0.60 : 0.27;
        return Rect.fromLTRB(l, t, l + 0.38, t + 0.30);
    }
  }

  Rect _padBlockRect(Rect region) {
    final px = Rect.fromLTRB(
      region.left * _lastSize.width,
      region.top * _lastSize.height,
      region.right * _lastSize.width,
      region.bottom * _lastSize.height,
    );
    final side = math.min(px.width, px.height);
    return Rect.fromCenter(center: px.center, width: side, height: side);
  }

  double _blockSide() {
    final r = _padBlockRect(_playerRegion(0, _pads.length));
    return math.min(r.width, r.height);
  }

  Offset _padCenter(int playerId) {
    final index = _pads.indexWhere((p) => p.playerId == playerId);
    if (index < 0) return Offset(_lastSize.width / 2, _lastSize.height / 2);
    return _padBlockRect(_playerRegion(index, _pads.length)).center;
  }
}
