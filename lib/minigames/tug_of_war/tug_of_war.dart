import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';

/// Side of the rope. Left pulls the marker toward -1, right toward +1.
enum _Side { left, right }

/// Tug of War — two sides mash to drag a rope marker across their goal line.
/// Sides are split by [Team] when set (duel/2v2), else by even/odd player id.
/// A tap pulls the marker toward that side; a gentle center pull bleeds idle
/// gains so a side must keep mashing. First side past ±[_winThreshold] wins;
/// on timeout the side nearer its goal wins. Losers ragdoll-fly.
class TugOfWar extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'tug_of_war',
        name: 'Tug of War',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1, GameMode.team2v2],
        inputHint: 'MASH',
      );

  // --- Tuning -----------------------------------------------------------------
  static const double _timeLimit = 30;
  static const double _winThreshold = 1.0; // |marker| to win
  static const double _tapPull = 0.02; // marker shift per tap
  static const double _centerPullPerSec = 0.06; // idle bleed toward 0
  static const double _ropeInsetX = 80;
  static const double _markerYFrac = 0.5;
  static const double _runnerGapX = 34; // spacing of stick figures per side
  static const double _goalHalfH = 40; // goal-line half height (render)
  static const double _runnerBackOff = 24; // figure offset behind goal line

  // Bot mash cadence (seconds/tap); harder bots mash faster.
  static const double _botBaseInterval = 0.16;
  static const double _botAccuracyBonus = 0.09;
  static const double _botJitter = 0.04;

  late Juice _juice;
  double _elapsed = 0;
  double _marker = 0; // [-1, 1]; -1 = left wins, +1 = right wins
  bool _resolved = false;

  final Map<int, _Puller> _pullers = <int, _Puller>{};

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    for (final p in ctx.players) {
      _pullers[p.id] = _Puller(
        slot: p,
        side: _sideFor(p),
        figure:
            StickFigure(style: StickStyle.hero.copyWith(fill: Color(p.colorArgb)))
              ..setLoco(LocoState.idle),
        botInterval: _botInterval(ctx),
      );
    }
    begin();
  }

  /// Team-aware split: Team.a/Team.b honor explicit teams; otherwise even ids
  /// pull left, odd ids pull right. Guarantees a non-empty opposing side when
  /// there are 2+ players.
  _Side _sideFor(PlayerSlot p) {
    if (p.team == Team.a) return _Side.left;
    if (p.team == Team.b) return _Side.right;
    return p.id.isEven ? _Side.left : _Side.right;
  }

  double _botInterval(MiniGameContext ctx) {
    final prof = ctx.botProfile;
    return _botBaseInterval - _botAccuracyBonus * prof.accuracy;
  }

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
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _driveBots(sdt);
    _applyCenterPull(sdt);

    for (final pl in _pullers.values) {
      pl.figure.update(sdt);
    }
    _publishScores();

    if (_marker <= -_winThreshold) {
      _resolve(_Side.left);
    } else if (_marker >= _winThreshold) {
      _resolve(_Side.right);
    } else if (_elapsed >= _timeLimit) {
      // Nearer goal wins; dead-even falls to left for determinism.
      _resolve(_marker <= 0 ? _Side.left : _Side.right);
    }
  }

  void _applyCenterPull(double dt) {
    if (_marker == 0) return;
    final pull = _centerPullPerSec * dt;
    if (_marker > 0) {
      _marker = math.max(0, _marker - pull);
    } else {
      _marker = math.min(0, _marker + pull);
    }
  }

  /// Score = how far this player's side has dragged the marker (0..1), so the
  /// on-field HUD shows the leading side. Both teammates share their side value.
  void _publishScores() {
    for (final pl in _pullers.values) {
      final advantage = pl.side == _Side.left
          ? math.max(0.0, -_marker)
          : math.max(0.0, _marker);
      setScore(pl.slot.id, advantage);
    }
  }

  void _driveBots(double dt) {
    for (final pl in _pullers.values) {
      if (!pl.slot.isBot) continue;
      pl.botClock += dt;
      while (pl.botClock >= pl.nextTapAt) {
        pl.botClock -= pl.nextTapAt;
        _tap(pl.slot.id);
        pl.nextTapAt = _nextBotInterval(pl);
      }
    }
  }

  double _nextBotInterval(_Puller pl) {
    final jitter = ctx.rng.jitter(_botJitter);
    return math.max(0.03, pl.botInterval + jitter);
  }

  void _tap(int id) {
    final pl = _pullers[id];
    if (pl == null) return;
    _marker += pl.side == _Side.left ? -_tapPull : _tapPull;
    _marker = _marker.clamp(-_winThreshold, _winThreshold);
    pl.figure.setLoco(LocoState.run);
  }

  void _resolve(_Side winner) {
    if (_resolved) return;
    _resolved = true;

    // Losers ragdoll-fly away from center; a burst of confetti for the winners.
    final arena = ctx.arena;
    final groundY = arena.height;
    for (final pl in _pullers.values) {
      if (pl.side == winner) continue;
      final dir = pl.side == _Side.left ? -1.0 : 1.0;
      final root = _runnerRoot(pl, arena);
      pl.figure.enterRagdoll(root, groundY, Offset(dir * 320, -260));
      _juice.ko(root, Color(pl.slot.colorArgb));
    }
    _juice.confetti(arena);
    _publishScores();

    final winners = <int>[];
    final losers = <int>[];
    for (final pl in _pullers.values) {
      (pl.side == winner ? winners : losers).add(pl.slot.id);
    }
    finishByOrder([...winners, ...losers]);
  }

  // --- Render -----------------------------------------------------------------

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    _drawRope(canvas, size);
    for (final pl in _pullers.values) {
      pl.figure.render(canvas, _runnerRoot(pl, size));
    }

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawRope(Canvas canvas, Size size) {
    final y = size.height * _markerYFrac;
    final leftX = _ropeInsetX;
    final rightX = size.width - _ropeInsetX;
    final rope = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(leftX, y), Offset(rightX, y), rope);

    // Goal lines.
    final goal = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 2;
    canvas.drawLine(
        Offset(leftX, y - _goalHalfH), Offset(leftX, y + _goalHalfH), goal);
    canvas.drawLine(
        Offset(rightX, y - _goalHalfH), Offset(rightX, y + _goalHalfH), goal);

    // Marker (rope center knot) mapped from [-1,1] to [leftX, rightX].
    final t = (_marker + 1) / 2;
    final mx = lerpDouble(leftX, rightX, t)!;
    canvas.drawCircle(
        Offset(mx, y), 12, Paint()..color = const Color(0xFFFFFFFF));
  }

  /// Stick root for a puller: stacked just behind their goal line, offset by
  /// their index within the side so multiple figures don't overlap.
  Offset _runnerRoot(_Puller pl, Size size) {
    final y = size.height * _markerYFrac;
    final indexOnSide = _indexOnSide(pl);
    if (pl.side == _Side.left) {
      return Offset(
          _ropeInsetX - _runnerBackOff - indexOnSide * _runnerGapX, y);
    }
    return Offset(
        size.width - _ropeInsetX + _runnerBackOff + indexOnSide * _runnerGapX,
        y);
  }

  int _indexOnSide(_Puller pl) {
    var i = 0;
    for (final other in _pullers.values) {
      if (other.side != pl.side) continue;
      if (other.slot.id == pl.slot.id) return i;
      i++;
    }
    return i;
  }
}

/// Per-player tug state for one round.
class _Puller {
  final PlayerSlot slot;
  final _Side side;
  final StickFigure figure;
  final double botInterval;

  double botClock = 0;
  double nextTapAt;

  _Puller({
    required this.slot,
    required this.side,
    required this.figure,
    required this.botInterval,
  }) : nextTapAt = botInterval;
}
