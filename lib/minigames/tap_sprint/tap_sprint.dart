import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/helpers/tap_mash_meter.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';

/// Tap Sprint — each player is a runner; mashing fills a no-decay meter whose
/// progress is the runner's position on the track. First to reach the line
/// finishes 1st; everyone else is ranked by finish time, then by progress.
class TapSprint extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'tap_sprint',
        name: 'Tap Sprint',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'MASH',
      );

  // --- Tuning -----------------------------------------------------------------
  static const double _timeLimit = 30;
  static const double _tapImpulse = 0.018; // ~56 taps to cross the line
  static const double _trackInsetX = 64; // px margin on each side of the track
  static const double _laneTopFrac = 0.18; // first lane y as fraction of arena
  static const double _laneStepFrac = 0.2; // vertical gap between lanes

  // Bot mash cadence (seconds between taps). Harder bots mash faster.
  static const double _botBaseInterval = 0.16;
  static const double _botAccuracyBonus = 0.09; // subtracted at accuracy 1.0
  static const double _botJitter = 0.04;

  late Juice _juice;
  double _elapsed = 0;

  final Map<int, _Runner> _runners = <int, _Runner>{};
  final List<int> _finishOrder = <int>[]; // by crossing time, best first
  bool _confettiFired = false;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    for (final p in ctx.players) {
      _runners[p.id] = _Runner(
        slot: p,
        meter: TapMashMeter(tapImpulse: _tapImpulse),
        figure:
            StickFigure(style: StickStyle.hero.copyWith(fill: Color(p.colorArgb)))
              ..setLoco(LocoState.idle),
        botInterval: _botInterval(ctx),
      );
    }
    begin();
  }

  double _botInterval(MiniGameContext ctx) {
    final p = ctx.botProfile;
    return _botBaseInterval - _botAccuracyBonus * p.accuracy;
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

    for (final r in _runners.values) {
      r.figure.update(sdt);
      setScore(r.slot.id, r.meter.progress);
      if (!r.finished && r.meter.full) {
        r.finished = true;
        _finishOrder.add(r.slot.id);
        r.figure.setLoco(LocoState.idle);
      }
    }

    if (!_confettiFired && _finishOrder.isNotEmpty) {
      _confettiFired = true;
      _juice.confetti(ctx.arena);
    }

    final allDone = _runners.values.every((r) => r.finished);
    if (allDone || _elapsed >= _timeLimit) {
      _finishRace();
    }
  }

  void _driveBots(double dt) {
    for (final r in _runners.values) {
      if (!r.slot.isBot || r.finished) continue;
      r.botClock += dt;
      while (r.botClock >= r.nextTapAt) {
        r.botClock -= r.nextTapAt;
        _tap(r.slot.id);
        r.nextTapAt = _nextBotInterval(r);
      }
    }
  }

  double _nextBotInterval(_Runner r) {
    final jitter = ctx.rng.jitter(_botJitter);
    return math.max(0.03, r.botInterval + jitter);
  }

  void _tap(int id) {
    final r = _runners[id];
    if (r == null || r.finished) return;
    r.meter.tap();
    r.figure.setLoco(LocoState.run);
  }

  /// Finishers (by crossing time) first, then unfinished runners by progress.
  void _finishRace() {
    final unfinished = _runners.values.where((r) => !r.finished).toList()
      ..sort((a, b) => b.meter.progress.compareTo(a.meter.progress));
    final order = <int>[
      ..._finishOrder,
      ...unfinished.map((r) => r.slot.id),
    ];
    finishByOrder(order);
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    final startX = _trackInsetX;
    final finishX = size.width - _trackInsetX;
    _drawLines(canvas, size, startX, finishX);

    var lane = 0;
    for (final p in ctx.players) {
      final r = _runners[p.id]!;
      final y = size.height * (_laneTopFrac + _laneStepFrac * lane);
      _drawLane(canvas, size, y, Color(p.colorArgb));
      final x = lerpDouble(startX, finishX, r.meter.progress)!;
      r.figure.render(canvas, Offset(x, y));
      lane++;
    }

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawLines(Canvas canvas, Size size, double startX, double finishX) {
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), paint);
    canvas.drawLine(Offset(finishX, 0), Offset(finishX, size.height),
        paint..color = const Color(0x88FFFFFF));
  }

  void _drawLane(Canvas canvas, Size size, double y, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    canvas.drawLine(
        Offset(_trackInsetX, y), Offset(size.width - _trackInsetX, y), paint);
  }
}

/// Per-player race state. Lives for one round only.
class _Runner {
  final PlayerSlot slot;
  final TapMashMeter meter;
  final StickFigure figure;
  final double botInterval;

  bool finished = false;
  double botClock = 0;
  double nextTapAt;

  _Runner({
    required this.slot,
    required this.meter,
    required this.figure,
    required this.botInterval,
  }) : nextTapAt = botInterval;
}
