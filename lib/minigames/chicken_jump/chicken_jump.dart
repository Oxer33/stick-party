import 'dart:ui';

import '../../core/math2.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/lane_hopper.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_style.dart';

/// Numeric tuning — no magic numbers inline.
class _Tuning {
  static const double timeLimit = 45;
  static const int platformCount = 14;
  static const double topInset = 120; // px from top to highest platform
  static const double bottomInset = 120; // px from bottom to lowest platform
  static const double lavaRiseStart = 26; // px/s initial lava speed
  static const double lavaAccel = 5.5; // px/s^2 ramp so rounds always end
  static const double hopAnimSpeed = 14; // lane ease rate
  static const double figureLift = 6; // raise stick above platform top
  static const double platHeight = 12;
  static const double jumpHoldSec = 0.22; // how long jump pose shows
  static const double botSafetyGap = 70; // bot jumps when lava within this px
}

/// One climber occupying a platform lane, hopping upward to dodge lava.
class _Climber {
  final int playerId;
  final Color color;
  final double columnX; // horizontal track position
  final Hopper hopper;
  final StickFigure figure;
  bool alive = true;
  double jumpTimer = 0; // shows jump loco briefly after a hop
  ReactionClock? clock;
  _Climber({
    required this.playerId,
    required this.color,
    required this.columnX,
    required this.hopper,
    required this.figure,
    this.clock,
  });
}

/// Chicken Jump: tap to hop up one platform; rising lava eliminates anyone it
/// catches. Last climber standing wins.
class ChickenJump extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'chicken_jump',
        name: 'Chicken Jump',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  late Juice _juice;
  late LaneSet _platforms;
  final List<_Climber> _climbers = <_Climber>[];
  final List<int> _eliminationOrder = <int>[]; // worst→best as they fall
  double _elapsed = 0;
  double _lavaY = 0; // current lava surface (screen px, rises = decreases)
  double _lavaSpeed = _Tuning.lavaRiseStart;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _buildWorld();
    begin();
  }

  void _buildWorld() {
    final arena = ctx.arena;
    final lowestY = arena.height - _Tuning.bottomInset;
    final span = lowestY - _Tuning.topInset;
    final spacing = -(span / (_Tuning.platformCount - 1)); // negative = upward
    // Lane 0 = lowest platform (largest y); higher lanes climb upward.
    _platforms = LaneSet(
      count: _Tuning.platformCount,
      start: lowestY,
      spacing: spacing,
      vertical: true,
    );
    _lavaY = arena.height; // lava starts off the bottom edge

    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final columnX = _columnX(i, count, arena.width);
      final figure = StickFigure(
        style: StickStyle.hero.copyWith(fill: Color(p.colorArgb)),
        facing: 1,
      )..setLoco(LocoState.idle);
      _climbers.add(_Climber(
        playerId: p.id,
        color: Color(p.colorArgb),
        columnX: columnX,
        hopper: Hopper(lane: 0, laneCount: _Tuning.platformCount),
        figure: figure,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// Evenly space player columns across the width.
  double _columnX(int index, int count, double width) {
    final slot = width / (count + 1);
    return slot * (index + 1);
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _jump(input.playerId);
  }

  void _jump(int id) {
    final c = _climberOf(id);
    if (c == null || !c.alive) return;
    c.hopper.hop(); // up one platform
    c.jumpTimer = _Tuning.jumpHoldSec;
    c.figure.setLoco(LocoState.jump);
  }

  _Climber? _climberOf(int id) {
    for (final c in _climbers) {
      if (c.playerId == id) return c;
    }
    return null;
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _raiseLava(sdt);
    _driveBots(dt);
    _stepClimbers(dt, sdt);
    _checkEnd();
  }

  void _raiseLava(double dt) {
    _lavaSpeed += _Tuning.lavaAccel * dt;
    _lavaY -= _lavaSpeed * dt; // rising = y decreases
  }

  /// Bots hop up when lava gets within a safety gap of their platform.
  void _driveBots(double dt) {
    for (final c in _climbers) {
      final clock = c.clock;
      if (clock == null || !c.alive) continue;
      if (!clock.tick(dt)) continue;
      if (_botShouldJump(c)) {
        _jump(c.playerId);
      }
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  bool _botShouldJump(_Climber c) {
    final platY = _platforms.coordOf(c.hopper.lane);
    final gap = _lavaY - platY; // positive while lava still below platform
    // Better bots keep a larger safety buffer; weak bots react late or skip.
    final buffer = _Tuning.botSafetyGap * (0.4 + ctx.botProfile.accuracy);
    if (gap <= buffer) {
      return !ctx.rng.chance(ctx.botProfile.errorRate);
    }
    return false;
  }

  void _stepClimbers(double dt, double sdt) {
    for (final c in _climbers) {
      if (!c.alive) {
        c.figure.update(dt);
        continue;
      }
      c.hopper.update(sdt, speed: _Tuning.hopAnimSpeed);
      if (c.jumpTimer > 0) {
        c.jumpTimer -= dt;
        if (c.jumpTimer <= 0) c.figure.setLoco(LocoState.idle);
      }
      c.figure.update(dt);
      _checkLava(c);
    }
  }

  void _checkLava(_Climber c) {
    final platY = _platforms.coordOf(c.hopper.lane);
    // Lava caught this platform once its surface rises to/above the platform.
    if (_lavaY <= platY) {
      _eliminate(c);
    }
  }

  void _eliminate(_Climber c) {
    c.alive = false;
    _eliminationOrder.add(c.playerId);
    final platY = _platforms.coordOf(c.hopper.lane);
    final at = Offset(c.columnX, platY);
    c.figure.enterRagdoll(at, platY, Offset(ctx.rng.sign() * 120, -160));
    _juice.ko(at, c.color);
  }

  void _checkEnd() {
    final alive = _climbers.where((c) => c.alive).toList();
    final timeUp = _elapsed >= _Tuning.timeLimit;
    if (alive.length > 1 && !timeUp) return;
    _finish(alive);
  }

  void _finish(List<_Climber> alive) {
    // Survivors (highest platform first) rank above the eliminated; eliminated
    // are ordered most-recent-first (they lasted longest).
    final survivors = alive.toList()
      ..sort((a, b) => b.hopper.lane.compareTo(a.hopper.lane));
    final ranking = <int>[
      for (final c in survivors) c.playerId,
      ..._eliminationOrder.reversed,
    ];
    // Score = platforms climbed (alive get a survival bonus).
    for (final c in _climbers) {
      final bonus = c.alive ? _Tuning.platformCount : 0;
      setScore(c.playerId, c.hopper.lane + bonus);
    }
    _juice.confetti(ctx.arena);
    finishByOrder(ranking);
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);
    _drawBackground(canvas, size);
    _drawPlatforms(canvas, size);
    _drawLava(canvas, size);
    for (final c in _climbers) {
      _drawClimber(canvas, c);
    }
    _juice.render(canvas);
    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0C1118));
  }

  void _drawPlatforms(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2A3A44);
    for (var lane = 0; lane < _platforms.count; lane++) {
      final y = _platforms.coordOf(lane);
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, y),
        width: size.width * 0.86,
        height: _Tuning.platHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );
    }
  }

  void _drawLava(Canvas canvas, Size size) {
    final top = clampD(_lavaY, -size.height, size.height);
    final rect = Rect.fromLTRB(0, top, size.width, size.height);
    final paint = Paint()..color = const Color(0xFFE0432A);
    canvas.drawRect(rect, paint);
    // Bright surface line.
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, 4),
      Paint()..color = const Color(0xFFFFC247),
    );
  }

  void _drawClimber(Canvas canvas, _Climber c) {
    final platY = _platforms.coordOfVisual(c.hopper.visualLane);
    final root = Offset(c.columnX, platY - _Tuning.figureLift);
    c.figure.render(canvas, root);
  }
}
