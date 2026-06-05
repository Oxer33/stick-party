import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/reaction_gate.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';

/// Reaction Duel — wait for GO, then be the first to tap. Tapping during the
/// red "wait" phase is a false start (penalty). The first valid tap after GO
/// wins; remaining players are ranked by reaction time, penalized players last.
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

  // --- Tuning -----------------------------------------------------------------
  static const double _timeLimit = 12;
  static const double _minGoDelay = 1.0;
  static const double _maxGoDelay = 3.5;
  static const double _lingerAfterWin = 0.6; // let everyone tap once decided
  static const double _goWindow = 3.0; // max seconds in GO before force-ending
  static const double _penaltyScore = -1; // HUD score for false-starters

  late Juice _juice;
  late ReactionGate _gate;
  double _elapsed = 0;
  double _sinceDone = 0;
  double _sinceGo = 0;
  bool _confettiFired = false;

  final Map<int, _Reactor> _reactors = <int, _Reactor>{};

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _gate = ReactionGate(ctx.rng, minDelay: _minGoDelay, maxDelay: _maxGoDelay);
    for (final p in ctx.players) {
      _reactors[p.id] = _Reactor(
        slot: p,
        clock: ReactionClock(ctx.botProfile, ctx.rng),
        falseStarts: p.isBot && ctx.rng.chance(ctx.botProfile.errorRate),
      );
    }
    begin();
  }

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
    _elapsed += dt;
    _juice.update(dt);
    _gate.update(dt);

    _driveBots(dt);
    _publishLiveScores();

    if (_gate.phase == ReactionPhase.done) {
      _sinceDone += dt;
      if (!_confettiFired && _gate.winner != null) {
        _confettiFired = true;
        _juice.confetti(ctx.arena);
      }
      if (_sinceDone >= _lingerAfterWin) {
        _finishFromGate();
      }
    }

    // Absolute safety net: never exceed the time limit.
    if (_elapsed >= _timeLimit && status == MiniGameStatus.running) {
      _gate.forceDone();
      _finishFromGate();
    }
  }

  void _driveBots(double dt) {
    final inGo = _gate.phase == ReactionPhase.go;
    if (inGo) {
      _sinceGo += dt;
      // Everyone false-started (or stalled): close the GO window so we resolve.
      if (_gate.winner == null && _sinceGo >= _goWindow) {
        _gate.forceDone();
      }
    }
    for (final r in _reactors.values) {
      if (!r.slot.isBot || r.acted) continue;
      // Gun-jumping bots tap during the wait phase (false start).
      if (r.falseStarts && _gate.phase == ReactionPhase.waiting) {
        if (r.clock.tick(dt)) {
          _handleTap(r.slot.id);
          r.acted = true;
        }
        continue;
      }
      // Honest bots react only after GO, using their jittered delay.
      if (inGo && r.clock.tick(dt)) {
        _handleTap(r.slot.id);
        r.acted = true;
      }
    }
  }

  void _handleTap(int id) {
    final reactor = _reactors[id];
    if (reactor == null) return;
    final result = _gate.onTap(id);
    final color = Color(reactor.slot.colorArgb);
    switch (result) {
      case ReactionTap.valid:
        _juice.popup(_anchor(id), 'GO!', color, size: 40);
        _juice.hit(_anchor(id), color);
      case ReactionTap.early:
        _juice.popup(_anchor(id), 'EARLY', color);
      case ReactionTap.late:
      case ReactionTap.ignored:
        break;
    }
  }

  /// Live HUD score: fastest valid reaction = highest; false-start = penalty.
  void _publishLiveScores() {
    final times = _gate.reactionTimes;
    final penalized = _gate.penalized;
    for (final p in ctx.players) {
      if (penalized.contains(p.id)) {
        setScore(p.id, _penaltyScore);
      } else {
        final t = times[p.id];
        setScore(p.id, t != null ? 1 / (t + 0.01) : 0);
      }
    }
  }

  /// Build the final ranking from the gate: winner first, then valid reactions
  /// ascending, then non-reactors, with penalized players last (least-bad by
  /// stable id order).
  void _finishFromGate() {
    if (status == MiniGameStatus.finished) return;
    final times = _gate.reactionTimes;
    final penalized = _gate.penalized;
    final winner = _gate.winner;

    final ranked = <int>[];
    if (winner != null) ranked.add(winner);

    // Other valid reactors by ascending time.
    final others = times.keys
        .where((id) => id != winner && !penalized.contains(id))
        .toList()
      ..sort((a, b) => times[a]!.compareTo(times[b]!));
    ranked.addAll(others);

    // Non-reactors (never tapped, not penalized) in stable id order.
    for (final p in ctx.players) {
      if (ranked.contains(p.id) || penalized.contains(p.id)) continue;
      ranked.add(p.id);
    }

    // Penalized (false-start) players last.
    for (final p in ctx.players) {
      if (penalized.contains(p.id)) ranked.add(p.id);
    }

    _publishLiveScores();
    finishWith(WinResult(
      ranking: ranked,
      finalScores: Map<int, num>.from(scores.byPlayer),
    ));
  }

  // --- Render -----------------------------------------------------------------

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    _drawSignal(canvas, size);
    _juice.render(canvas);
    canvas.restore();
  }

  /// Full-field wash: red while waiting, green on GO, dimmed once decided.
  void _drawSignal(Canvas canvas, Size size) {
    final color = switch (_gate.phase) {
      ReactionPhase.waiting => const Color(0xFFB3261E), // red
      ReactionPhase.go => const Color(0xFF1FB85B), // green
      ReactionPhase.done => const Color(0xFF2A2F3A), // settled
    };
    canvas.drawRect(Offset.zero & size, Paint()..color = color);

    // Center pip per player so multi-player rounds read clearly.
    final n = ctx.players.length;
    final pipY = size.height * 0.5;
    final step = size.width / (n + 1);
    for (var i = 0; i < n; i++) {
      final p = ctx.players[i];
      final penalized = _gate.penalized.contains(p.id);
      final isWinner = _gate.winner == p.id;
      final pip = Paint()
        ..color = Color(p.colorArgb).withValues(alpha: penalized ? 0.25 : 1);
      final cx = step * (i + 1);
      canvas.drawCircle(Offset(cx, pipY), isWinner ? 26 : 18, pip);
    }
  }

  Offset _anchor(int id) {
    final n = ctx.players.length;
    final idx = ctx.players.indexWhere((p) => p.id == id).clamp(0, n - 1);
    final step = ctx.arena.width / (n + 1);
    return Offset(step * (idx + 1), ctx.arena.height * 0.5);
  }
}

/// Per-player reaction state for one round.
class _Reactor {
  final PlayerSlot slot;
  final ReactionClock clock;
  final bool falseStarts; // bot decided to jump the gun this round

  bool acted = false;

  _Reactor({
    required this.slot,
    required this.clock,
    required this.falseStarts,
  });
}
