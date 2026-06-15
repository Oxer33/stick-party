import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'memory_render.dart';

/// Round phase. [showing] flashes the sequence (the light show); [input] takes
/// each player's reproduction by direct pad taps; [appending] hands the round
/// WINNER one tap to choose the new color that everyone must remember next round
/// (call-and-response — the winner literally builds the pattern for the table).
enum _Phase { showing, input, appending }

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

  /// The reacting mascot standing beside this cluster (purely visual). Owns its
  /// own pose/anim clock, advanced each frame; idles while watching, swings on a
  /// correct tap, flinches on a KO, cheers on the win.
  final StickFigure figure;

  /// Bot only: the step index at which this bot will deliberately slip THIS
  /// round (or -1 = it will reproduce the whole pattern correctly). Decided once
  /// per round so a single slip ends a bot's run — instead of re-rolling the
  /// error on every entry, which used to wipe everyone before the pattern could
  /// ever grow. Difficulty + sequence length set how likely/early a slip is.
  int mistakeStep = -1;

  /// Per-pad bloom 0..1 (red, blue, green, yellow). Lit pads bloom bright and
  /// decay for an afterglow; purely cosmetic so it never affects logic.
  final List<double> bloom = <double>[0, 0, 0, 0];

  _Pad({
    required this.playerId,
    required this.accent,
    required this.figure,
    this.clock,
  });

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
/// Call-and-response growth (the PvP hook): the FIRST player to correctly
/// reproduce the whole pattern wins the round and becomes the **appender**. The
/// round then enters a short [_Phase.appending] beat where that winner taps ONE
/// colored pad — and THAT color is appended to the shared sequence everyone must
/// remember next round. So you are not just racing an isolated memory test: when
/// you win, you choose the tricky color the whole table (and the bots) has to
/// recall next. A winner who can't decide in time (or a round nobody cleared)
/// falls back to a random color so the game always moves on.
///
/// Last player standing wins via [finishByOrder].
///
/// Termination is guaranteed several ways: a per-round input deadline
/// ([_roundDeadlineSec]) eliminates anyone who hasn't finished, a bounded append
/// beat ([_appendDeadlineSec]) with a random-color fallback, a sequence length
/// cap ([_maxSeqLen]), last-player-standing, and the overall [_timeLimit].
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

  // ── Call-and-response append beat ────────────────────────────────────────────
  // After a round is won, the winner gets this long to tap their chosen color
  // for the next pattern. If they dawdle past it (or no one cleared the round),
  // a random color is appended so the game always advances.
  static const double _appendDeadlineSec = 3.0; // cap on the winner's choice
  static const double _appendLeadSec = 0.35; // calm beat before a tap counts
  // A bot winner "thinks" for a reaction beat, then taps a color it picks at
  // random (deterministic via ctx.rng) — so the CPU also feeds the table.
  static const double _botAppendDelaySec = 0.6;

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

  // ── Spectacle escalation (the new bar) ──────────────────────────────────────
  // Clearing an ever-LONGER pattern is the peak skill moment, so the clutch-recall
  // banner climbs with the pattern length: a normal clear says GENIUS!, a long one
  // INCREDIBLE!, a marathon one UNREAL! — each fired via [Juice.bigMoment] (burst +
  // slow-mo + zoom + flash + haptic). Tiers are the sequence lengths at which the
  // wording (and a full-screen flash) escalates.
  static const int _genius2SeqLen = 7; // pattern length → "INCREDIBLE!"
  static const int _genius3SeqLen = 10; // pattern length → "UNREAL!"
  static const double _clutchFlashStrength = 0.5; // screen flash on a clutch clear
  // The light show crossing into the fast tier earns a one-shot "FASTER!" speed
  // cue so the rising pace reads to the kids as a deliberate difficulty ramp.
  static const int _speedCueSeqLen = 7; // length at which the FASTER! cue fires
  // Finale: the champion reveal fires a signature [Juice.bigMoment] on the
  // winner's pad + a full-board CHAMPION banner + winner-tinted confetti.

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

  // ── Confidence reward tuning (streak) ────────────────────────────────────────
  // A streak adds at most [_streakBonusCap] to a player's FINAL score — a sub-
  // integer flair (max < 1) so it breaks ties between equally-deep survivors and
  // rewards a confident front-runner, but can NEVER round a shallow run up across
  // a depth threshold (so blind spam can't ride a streak into the climax depths).
  static const double _streakBonusPer = 0.04; // score flair per streak step
  static const double _streakBonusCap = 0.36; // hard ceiling on the flair (<0.5)
  static const int _hotStreak = 2; // streak at which the "HOT HAND" flair lights

  // ── Feel tuning ─────────────────────────────────────────────────────────────
  static const double _bloomDecayPerSec = 2.6; // pad afterglow fade rate
  static const double _flashHoldFrac = 0.6; // share of a step the orb stays lit
  static const double _koFlashSec = 0.5;
  static const double _oopsFlashSec = 0.45;
  static const double _bannerThrobHz = 2.4;
  // Tension: the heartbeat/closing-vignette intensity ramps from the climax
  // length up to the speed-up reference length, where it pegs at full.
  static const double _heartbeatHz = 1.6; // base heartbeat pulse rate
  static const double _heartbeatTensionHz = 1.8; // extra rate at full tension

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
  bool _speedCueShown = false; // the one-shot FASTER! speed cue fired this round
  double _drumrollAcc = 0; // banks lead-in time toward each drum tick
  Size _lastSize = const Size(1, 1);

  // ── Call-and-response state ─────────────────────────────────────────────────
  int? _appenderId; // who won this round (first to finish) → builds the pattern
  int? _appendedColor; // the color the winner chose for the next round (0..3)
  bool _appendBotChose = false; // latch so a bot winner only taps its choice once

  // ── Confidence reward: the fast-recall STREAK ────────────────────────────────
  // Consecutive rounds a player was FIRST to clear the whole pattern. A back-to-
  // back front-runner builds a streak that crowns them on the race track and adds
  // a tiny tie-break flair to their final score — an active edge for confident
  // recall, WITHOUT abandoning memory (the streak only grows by winning the round,
  // which still requires reproducing the pattern). Bounded + sub-integer so it can
  // never lift a shallow run across a depth threshold.
  final Map<int, int> _streak = <int, int>{}; // playerId → current win streak
  int _bestStreak = 0; // deepest streak any player reached (finale flair)
  int? _bestStreakId; // who holds the best streak (for the finale shout)

  // ── Finale: the clutch LAST-TWO beat ─────────────────────────────────────────
  // The instant the field narrows to exactly two survivors (in a 3+ starter
  // match) we fire a one-shot slow-mo + flash + "FINAL TWO" banner so the table
  // feels the showdown land. Latched so it only fires once per match.
  bool _finalTwoFired = false;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    for (final p in ctx.players) {
      final accent = Color(p.colorArgb);
      _pads.add(_Pad(
        playerId: p.id,
        accent: accent,
        figure: StickFigure(style: _mascotStyle(accent))
          ..setLoco(LocoState.idle),
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
    _speedCueShown = false;
    _drumrollAcc = 0;
  }

  /// True when the current pattern is long enough to be a climax round (the
  /// faster, drumrolled "big one").
  bool get _isClimaxRound => _sequence.length >= _climaxSeqLen;

  /// The clutch-recall banner, escalating with how long a pattern was just
  /// reproduced: a deeper recall earns a louder shout. Drives the round-win
  /// [Juice.bigMoment] so the spectacle climbs with the difficulty.
  String _clutchBanner() {
    final len = _sequence.length;
    if (len >= _genius3SeqLen) return 'UNREAL!';
    if (len >= _genius2SeqLen) return 'INCREDIBLE!';
    return 'GENIUS!';
  }

  /// Record a round win for the streak: the front-runner's streak grows, every
  /// other player's resets to 0 (you only keep a HOT HAND by winning again).
  /// Tracks the deepest streak + its holder for the finale shout.
  void _registerStreakWin(int winnerId) {
    for (final pad in _pads) {
      if (pad.playerId == winnerId) {
        _streak[pad.playerId] = (_streak[pad.playerId] ?? 0) + 1;
      } else {
        _streak[pad.playerId] = 0;
      }
    }
    final s = _streak[winnerId] ?? 0;
    if (s > _bestStreak) {
      _bestStreak = s;
      _bestStreakId = winnerId;
    }
  }

  /// The sub-integer score flair earned by a player's current streak: bounded
  /// well under 0.5 so it only ever breaks ties between equally-deep runs and
  /// can never round a shallow score up across a depth threshold.
  double _streakBonus(int playerId) =>
      ((_streak[playerId] ?? 0) * _streakBonusPer).clamp(0.0, _streakBonusCap);

  /// Mounting-tension level 0..1 for the round, derived from the pattern length:
  /// 0 below the climax length, ramping to 1 by the speed-up reference length.
  /// Drives the closing vignette + heartbeat (pure feel; never touches logic).
  double get _tension {
    final len = _sequence.length;
    if (len <= _climaxSeqLen) return 0.0;
    final span = (_speedUpRefLen - _climaxSeqLen).clamp(1, _maxSeqLen);
    return ((len - _climaxSeqLen) / span).clamp(0.0, 1.0);
  }

  /// Heartbeat phase 0..1 (a quickening pulse as tension climbs). Pure function
  /// of the real-time clock so it's deterministic and needs no extra Ticker.
  double get _heartbeat {
    final hz = _heartbeatHz + _heartbeatTensionHz * _tension;
    return 0.5 + 0.5 * math.sin(_animClock * 2 * math.pi * hz);
  }

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
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    if (_phase == _Phase.appending) {
      _handleAppendTap(input);
      return;
    }
    if (_phase != _Phase.input) return;
    final pad = _padOf(input.playerId);
    if (pad == null || !pad.alive || pad.done) return;
    // Tap a real colored pad: hit-test the quadrant the touch landed in. A tap
    // that misses every pad (the hub / a gap) is ignored, never fatal.
    final slot = _padHitTest(input.playerId, input.normPos);
    if (slot < 0) return;
    _commit(pad, slot);
  }

  /// During the append beat, ONLY the round winner's tap matters: the colored
  /// pad they tap becomes the next shared sequence entry. A short lead-in beat
  /// swallows the very first frames (so a leftover reproduction tap doesn't get
  /// captured by accident), and a tap that misses every pad is ignored.
  void _handleAppendTap(PlayerInput input) {
    if (_appendedColor != null) return; // already chosen
    if (input.playerId != _appenderId) return; // only the winner appends
    if (_phaseTimer < _appendLeadSec) return; // calm beat before a tap counts
    final slot = _padHitTest(input.playerId, input.normPos);
    if (slot < 0) return;
    _chooseAppendColor(slot);
  }

  /// Record the winner's chosen [color] (0..3) for the next round, with a happy
  /// pad bloom + spark so the choice reads, then let the round resolve & grow.
  void _chooseAppendColor(int color) {
    final c = color.clamp(0, _palette - 1);
    _appendedColor = c;
    final pad = _appenderId != null ? _padOf(_appenderId!) : null;
    if (pad != null) {
      pad.bumpBloom(c);
      _juice.hit(_padCenter(pad.playerId), MemoryRenderer.palette[c], sparks: 8);
      _juice.popup(
          _padCenter(pad.playerId).translate(0, -_blockSide() * 0.5),
          'ADD!',
          MemoryRenderer.palette[c],
          size: 26);
    }
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
      // The mascot swings on each correct color so the cluster reacts.
      pad.figure.attack(0);
      if (pad.progress >= _sequence.length) {
        pad.done = true;
        // Cleared the whole pattern this round → a flourish to mark it.
        pad.figure.special();
        // First player to clear the whole pattern WINS the round and earns the
        // right to append the next color (call-and-response). Latched once.
        final justWon = _appenderId == null;
        if (justWon) {
          _appenderId = pad.playerId;
          _registerStreakWin(pad.playerId);
          // Signature clutch-recall cinematic: burst + shake + slow-mo + zoom
          // toward the winner's pad + flash + banner + haptic. Fired once per
          // round, and the WORDING escalates with how long a pattern was just
          // recalled (a longer recall is a bigger feat) — the climax beat.
          _juice.bigMoment(_padCenter(pad.playerId), pad.accent,
              banner: _clutchBanner());
          // A long clutch recall also kicks a full-screen flash so the peak skill
          // moment lands across the room.
          if (_sequence.length >= _climaxSeqLen) {
            _juice.flashScreen(pad.accent, strength: _clutchFlashStrength);
          }
          // A HOT HAND (back-to-back first-clears) earns a loud streak shout so
          // a confident front-runner's edge reads to the table.
          final s = _streak[pad.playerId] ?? 0;
          if (s >= _hotStreak) {
            _juice.popup(
                _padCenter(pad.playerId).translate(0, -_blockSide() * 0.78),
                'HOT x$s!',
                _white,
                size: 28);
          }
        } else {
          _juice.popup(
              _padCenter(pad.playerId).translate(0, -_blockSide() * 0.5),
              'NICE!',
              pad.accent,
              size: 26);
        }
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
    _streak[pad.playerId] = 0; // a KO snaps any hot hand
    _outOrder.add(pad.playerId);
    _juice.ko(_padCenter(pad.playerId), pad.accent);
    // The mascot flinches as its player is knocked out.
    pad.figure.hurt();
    _maybeFireFinalTwo();
  }

  /// The clutch showdown beat: the instant the field narrows to exactly TWO
  /// survivors (in a 3+ starter match) fire a one-shot slow-mo + flash + banner
  /// so the table feels the duel land. Latched to fire at most once per match.
  void _maybeFireFinalTwo() {
    if (_finalTwoFired || _pads.length < 3) return;
    final alive = _pads.where((p) => p.alive).length;
    if (alive != 2) return;
    _finalTwoFired = true;
    _juice.slowMo();
    _juice.flashScreen(_white, strength: 0.4);
    _juice.bigBanner('FINAL TWO', color: _white);
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
      // Advance the mascot's animation clock so its reactions play out.
      pad.figure.update(dt);
    }

    switch (_phase) {
      case _Phase.showing:
        _updateShowing(sdt);
      case _Phase.input:
        _updateInput(sdt);
      case _Phase.appending:
        _updateAppending(sdt);
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
      if (next >= 0) {
        // The very first color of a fast (long) pattern gets a one-shot
        // "FASTER!" speed cue + a soft screen flash so the rising pace reads as
        // a deliberate difficulty ramp, not a glitch.
        if (next == 0 &&
            !_speedCueShown &&
            _sequence.length >= _speedCueSeqLen) {
          _speedCueShown = true;
          _juice.popup(Offset(_lastSize.width / 2, _lastSize.height * 0.30),
              'FASTER!', _white, size: 30);
          _juice.flashScreen(_white, strength: 0.18);
        }
        _flashSequenceColor(_sequence[next]);
      }
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

  /// Drive bots, then close the input phase when everyone alive is done or the
  /// input deadline passes.
  void _updateInput(double dt) {
    _driveBots(dt);

    final deadlineHit = _phaseTimer >= _roundDeadlineSec;
    if (deadlineHit) {
      // Anyone who hasn't finished reproducing in time is out.
      for (final pad in _pads) {
        if (pad.alive && !pad.done) _eliminate(pad);
      }
    }

    if (_roundResolved()) _endInputPhase();
  }

  /// Input is over. Resolve terminal conditions; if the match continues, hand
  /// off to the WINNER to append the next color (call-and-response). When no one
  /// cleared the round (e.g. a mass deadline wipe of survivors) there is no
  /// appender, so we grow with a random color and replay immediately.
  void _endInputPhase() {
    if (_checkTerminal()) return; // last-standing / wiped / cap → finished
    if (_appenderId != null && _padOf(_appenderId!)!.alive) {
      _enterAppending();
    } else {
      // No winner this round → keep the table moving with a random color.
      _growSequence(ctx.rng.intRange(0, _palette));
      _enterShowing();
    }
  }

  /// Terminal-condition gate shared by the input and append beats. Returns true
  /// (and finishes) when the match is over; false when it should continue.
  bool _checkTerminal() {
    final alive = _pads.where((p) => p.alive).length;
    // Last player standing (multi-player) ends the match.
    if (_pads.length > 1 && alive <= 1) {
      _finishNow();
      return true;
    }
    // Everyone wiped simultaneously (e.g. single-player miss / mass deadline).
    if (alive == 0) {
      _finishNow();
      return true;
    }
    // Sequence cap reached → stop here and rank survivors.
    if (_sequence.length >= _maxSeqLen) {
      _finishNow();
      return true;
    }
    return false;
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

  /// Begin the call-and-response append beat: the round winner now chooses the
  /// next color. Resets the per-beat clock + choice latches.
  void _enterAppending() {
    _phase = _Phase.appending;
    _phaseTimer = 0;
    _appendedColor = null;
    _appendBotChose = false;
  }

  /// The append beat: wait for the winner's chosen color (human tap routed via
  /// [_handleAppendTap], bot via [_driveAppendBot]). Once chosen — or the beat's
  /// deadline lapses (fallback to a random color) — grow the sequence & replay.
  void _updateAppending(double dt) {
    // A bot winner picks its color after a short "thinking" beat.
    _driveAppendBot();

    final timedOut = _phaseTimer >= _appendDeadlineSec;
    if (_appendedColor == null && !timedOut) return;

    // Chosen color, or a random fallback if the winner dawdled. Clamp guards a
    // stray value; the fallback keeps the game deterministic + always advancing.
    final color = _appendedColor ?? ctx.rng.intRange(0, _palette);
    _growSequence(color);
    _enterShowing();
  }

  /// If the round winner is a bot, after a reaction beat it taps one color it
  /// picks at random (deterministic via ctx.rng). Latched so it only chooses
  /// once per beat.
  void _driveAppendBot() {
    if (_appendBotChose || _appendedColor != null) return;
    final id = _appenderId;
    if (id == null) return;
    final pad = _padOf(id);
    if (pad == null || pad.clock == null) return; // human winner → wait for tap
    if (_phaseTimer < _botAppendDelaySec) return;
    _appendBotChose = true;
    _chooseAppendColor(ctx.rng.intRange(0, _palette));
  }

  /// Append [color] to the shared sequence and advance the round counter. The
  /// winner's pick (or a fallback) — this is how the pattern grows now.
  void _growSequence(int color) {
    _sequence.add(color.clamp(0, _palette - 1));
    _round += 1;
    _appenderId = null; // cleared for the next round's race
  }

  /// Build best→worst ranking: survivors first (more progress / longer-lived),
  /// then eliminated players in reverse knock-out order. Every id appears once.
  void _finishNow() {
    if (status == MiniGameStatus.finished) return;
    for (final pad in _pads) {
      // Base score = entries cleared; survivors get full sequence-length credit.
      // A confident front-runner's STREAK adds a sub-integer flair on top — it
      // breaks ties between equally-deep survivors and rewards back-to-back
      // first-clears, but is bounded under 0.5 so it can never round a shallow
      // run up (blind spam can't ride a streak into the depth a memoriser earns).
      final base = pad.alive ? _sequence.length : pad.progress;
      setScore(pad.playerId, base + _streakBonus(pad.playerId));
    }
    // Survivors rank by recall depth first, then by the streak flair (their
    // current score already encodes both), so a tie is settled by the hot hand.
    final survivors = _pads.where((p) => p.alive).toList()
      ..sort((a, b) => scoreOf(b.playerId).compareTo(scoreOf(a.playerId)));
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
    // ── Champion reveal (the finale spectacle) ────────────────────────────────
    // The winner is the deepest-recalling survivor. Crown them with a signature
    // bigMoment on their pad (burst + slow-mo + zoom + flash + haptic), a
    // full-board CHAMPION banner, winner-tinted confetti, and a victory cheer.
    if (full.isNotEmpty) {
      final champ = _padOf(full.first);
      if (champ != null) {
        final at = _padCenter(champ.playerId);
        _juice.bigMoment(at, champ.accent, banner: 'CHAMPION!', sparks: 34);
        _juice.bigBanner('CHAMPION!', color: champ.accent);
        _juice.confetti(_lastSize, colors: [champ.accent]);
        champ.figure.victory();
        // Finale flair: the deepest pattern the table reached + (if anyone went
        // on a tear) a HOT HAND callout, so the win celebrates BOTH the longest
        // recall and the round-stealing streak.
        _juice.popup(at.translate(0, -_blockSide() * 0.62),
            'LONGEST ${_sequence.length}', _white, size: 26);
        if (_bestStreak >= _hotStreak && _bestStreakId != null) {
          final hp = _padOf(_bestStreakId!);
          if (hp != null) {
            _juice.popup(_padCenter(hp.playerId).translate(0, -_blockSide() * 0.9),
                'HOT HAND x$_bestStreak', hp.accent, size: 24);
          }
        }
      }
    }
    finishByOrder(full);
  }

  // ---- Rendering ------------------------------------------------------------

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    _juice.applyWorldTransform(canvas);

    MemoryRenderer.drawBackground(canvas, size);
    MemoryRenderer.drawVignette(canvas, size);

    final watching = _phase == _Phase.showing;
    _drawHud(canvas, size, watching);

    for (var i = 0; i < _pads.length; i++) {
      _drawCluster(canvas, _pads[i], i, watching);
    }

    _juice.render(canvas);
    canvas.restore();

    // Mounting-tension overlay (screen-space, under the cinematic layer): a warm
    // closing vignette + heartbeat ring that tighten as the pattern grows, plus a
    // SPEED ▲ chevron stack beside the race track once the show goes fast. Drawn
    // before the flash/banner so a KO flash still reads on top.
    final tn = _tension;
    if (tn > 0.02) {
      MemoryRenderer.drawTensionFrame(canvas, size, tn, _heartbeat);
      MemoryRenderer.drawSpeedArrow(canvas, size, tn);
    }

    // Screen-space cinematic overlays (flash + GENIUS! banner) after the world
    // transform is restored, so they are not shaken or zoomed.
    _juice.renderOverlay(canvas, size);
  }

  void _drawHud(Canvas canvas, Size size, bool watching) {
    final throb = 0.5 + 0.5 * math.sin(_animClock * _bannerThrobHz);
    if (_phase == _Phase.appending) {
      // Call-and-response cue: tell the table the winner is adding a color.
      final accent = _appenderId != null
          ? (_padOf(_appenderId!)?.accent ?? _white)
          : _white;
      MemoryRenderer.drawAppendBanner(canvas, size,
          appenderNumber: (_appenderId ?? 0) + 1, accent: accent, pulse: throb);
    } else {
      MemoryRenderer.drawPhaseBanner(canvas, size,
          watching: watching, pulse: throb);
    }
    MemoryRenderer.drawRoundCounter(canvas, size, _round);
    MemoryRenderer.drawSharedSequence(
      canvas,
      size,
      _sequence,
      shownCount: _showIndex + 1,
      watching: watching,
    );
    // The live RACE TRACK — the silo-breaker. During the input phase (and the
    // winner's append beat) each player's progress slides along a shared rail so
    // the table SEES who's ahead, who's sweating, and who just got knocked off.
    // Hidden during the WATCH light show so the sequence stays the focus.
    if (_phase != _Phase.showing) {
      MemoryRenderer.drawRaceTrack(
        canvas,
        size,
        _buildRunners(),
        pulse: _heartbeat,
        leaderId: _leaderId(),
      );
    }
    MemoryRenderer.drawFlashCore(
        canvas, size, _activeFlashColor(), _activeFlashStrength());
  }

  /// Snapshot every pad into a [RaceRunner] for the live track: progress as a
  /// 0..1 fraction of the current pattern, alive/done/KO-flash carried through.
  /// A cleared (done) runner is parked at the flag (t = 1).
  List<RaceRunner> _buildRunners() {
    final denom = _sequence.isEmpty ? 1 : _sequence.length;
    return [
      for (final pad in _pads)
        RaceRunner(
          playerId: pad.playerId,
          number: pad.playerId + 1,
          accent: pad.accent,
          t: pad.done ? 1.0 : (pad.progress / denom).clamp(0.0, 1.0),
          alive: pad.alive,
          done: pad.done,
          koFade:
              pad.koFlash > 0 ? (pad.koFlash / _koFlashSec).clamp(0.0, 1.0) : 0.0,
        ),
    ];
  }

  /// The current front-runner among alive, not-yet-finished players (most
  /// progress wins; -1 if nobody is still racing). Drives the leader crown.
  int _leaderId() {
    var bestId = -1;
    var bestProgress = -1;
    for (final pad in _pads) {
      if (!pad.alive || pad.done) continue;
      if (pad.progress > bestProgress) {
        bestProgress = pad.progress;
        bestId = pad.playerId;
      }
    }
    return bestId;
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
  /// per-pad cursor); during the append beat the WINNER's plate pulses instead
  /// (tap to add a color); a forgiven miss flashes the plate.
  void _drawCluster(Canvas canvas, _Pad pad, int index, bool watching) {
    final block = _padBlockRect(_playerRegion(index, _pads.length));
    final appendingTurn = _phase == _Phase.appending &&
        pad.alive &&
        pad.playerId == _appenderId &&
        _appendedColor == null;
    final inputTurn = _phase == _Phase.input && pad.alive && !pad.done;
    final turnPulse = (inputTurn || appendingTurn)
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
      appendInvite: appendingTurn,
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

    // The reacting mascot stands beside the cluster. In a 2x2 grid each one
    // mounts toward its own screen edge (even ids left, odd ids right) so it
    // faces in and never overlaps a neighbour's plate; with fewer players the
    // single column reads fine mounted on the left.
    MemoryRenderer.drawMascot(
      canvas,
      block,
      pad.figure,
      alive: pad.alive,
      mountOnLeft: index.isEven,
    );

    // During the winner's APPEND beat the OTHER alive players are waiting (their
    // taps do nothing), so dim their whole zone to a soft scrim — no more silent
    // dead pads that a player taps in vain. The top banner names who is adding.
    if (_phase == _Phase.appending &&
        pad.alive &&
        pad.playerId != _appenderId) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            block, Radius.circular(block.shortestSide * 0.12)),
        Paint()..color = const Color(0xFF05070D).withValues(alpha: 0.5),
      );
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

  /// Bright mascot style in the player's accent: color fill, brightened neon
  /// outline, soft glow. Mirrors the sprinter style in tap_sprint so the cast
  /// reads consistently across games.
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
}
