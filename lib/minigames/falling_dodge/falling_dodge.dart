import 'dart:ui';

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
  static const int laneCount = 4; // horizontal lanes per track
  static const double fallSpeedStart = 240; // px/s
  static const double fallAccel = 26; // px/s^2 ramp so rounds always end
  static const double spawnEveryStart = 1.1; // seconds between blocks
  static const double spawnMin = 0.4; // floor on spawn interval
  static const double spawnRamp = 0.012; // spawn interval shrink per second
  static const double blockSize = 46;
  static const double hopAnimSpeed = 16;
  static const double runnerInsetY = 70; // runner row above band bottom
  static const double laneMargin = 0.12; // fraction inset of lanes in a band
  static const double hitPad = 8; // collision slack
  static const double figureLift = 4;
}

/// A block falling down one player's track lane.
class _Block {
  final int lane;
  double y;
  _Block({required this.lane, required this.y});
}

/// One player's dodge track: a horizontal band with [laneCount] lanes, a runner
/// hopping between them, and its own stream of falling blocks.
class _Track {
  final int playerId;
  final Color color;
  final Rect band; // sub-region of the arena owned by this player
  final LaneSet lanes; // horizontal lane x-coordinates
  final double runnerY; // fixed y where the runner stands
  final Hopper hopper;
  final StickFigure figure;
  final List<_Block> blocks = <_Block>[];
  bool alive = true;
  int hopDir = 1; // alternates so bot/idle drift bounces in-bounds
  double spawnTimer = 0;
  ReactionClock? clock;
  _Track({
    required this.playerId,
    required this.color,
    required this.band,
    required this.lanes,
    required this.runnerY,
    required this.hopper,
    required this.figure,
    this.clock,
  });
}

/// Falling Dodge: blocks rain down each player's lane track; tap to slide to an
/// adjacent lane. Getting struck eliminates you. Last runner standing wins.
class FallingDodge extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'falling_dodge',
        name: 'Falling Dodge',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  late Juice _juice;
  final List<_Track> _tracks = <_Track>[];
  final List<int> _eliminationOrder = <int>[];
  double _elapsed = 0;
  double _fallSpeed = _Tuning.fallSpeedStart;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _buildTracks();
    begin();
  }

  void _buildTracks() {
    final arena = ctx.arena;
    final count = ctx.players.length;
    final bandH = arena.height / count;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final band = Rect.fromLTWH(0, bandH * i, arena.width, bandH);
      final lanes = _laneSet(band);
      _tracks.add(_Track(
        playerId: p.id,
        color: Color(p.colorArgb),
        band: band,
        lanes: lanes,
        runnerY: band.bottom - _Tuning.runnerInsetY,
        hopper:
            Hopper(lane: _Tuning.laneCount ~/ 2, laneCount: _Tuning.laneCount),
        figure: StickFigure(
          style: StickStyle.hero.copyWith(fill: Color(p.colorArgb)),
          facing: 1,
        )..setLoco(LocoState.run),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  LaneSet _laneSet(Rect band) {
    final inset = band.width * _Tuning.laneMargin;
    final usable = band.width - inset * 2;
    final spacing = usable / (_Tuning.laneCount - 1);
    return LaneSet(
      count: _Tuning.laneCount,
      start: band.left + inset,
      spacing: spacing,
    );
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _swap(input.playerId);
  }

  /// Human tap: slide toward the safest lane (away from the nearest threat).
  void _swap(int id) {
    final t = _trackOf(id);
    if (t == null || !t.alive) return;
    final dir = _safeDirection(t);
    t.hopper.hop(dir);
    t.hopDir = dir;
  }

  _Track? _trackOf(int id) {
    for (final t in _tracks) {
      if (t.playerId == id) return t;
    }
    return null;
  }

  /// Pick a hop direction that moves away from the most imminent block, while
  /// staying inside the lane range.
  int _safeDirection(_Track t) {
    final lane = t.hopper.lane;
    final threatLane = _nearestThreatLane(t);
    var dir = t.hopDir;
    if (threatLane != null) {
      if (threatLane == lane) {
        dir = lane <= 0 ? 1 : -1; // step off the current lane
      } else {
        dir = threatLane > lane ? -1 : 1; // move opposite the threat
      }
    }
    // Bounce off the track ends.
    if (lane + dir < 0) dir = 1;
    if (lane + dir > _Tuning.laneCount - 1) dir = -1;
    return dir;
  }

  int? _nearestThreatLane(_Track t) {
    _Block? nearest;
    for (final b in t.blocks) {
      if (b.y > t.runnerY) continue; // already passed
      if (nearest == null || b.y > nearest.y) nearest = b;
    }
    return nearest?.lane;
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _fallSpeed = _Tuning.fallSpeedStart + _Tuning.fallAccel * _elapsed;
    for (final t in _tracks) {
      if (t.alive) {
        _spawnTick(t, sdt);
        _stepBlocks(t, sdt);
      }
      t.hopper.update(sdt, speed: _Tuning.hopAnimSpeed);
      t.figure.update(dt);
    }
    _driveBots(dt);
    _checkEnd();
  }

  void _spawnTick(_Track t, double dt) {
    t.spawnTimer -= dt;
    if (t.spawnTimer > 0) return;
    final interval = (_Tuning.spawnEveryStart - _Tuning.spawnRamp * _elapsed)
        .clamp(_Tuning.spawnMin, _Tuning.spawnEveryStart);
    t.spawnTimer = interval;
    final lane = ctx.rng.intRange(0, _Tuning.laneCount);
    t.blocks.add(_Block(lane: lane, y: t.band.top - _Tuning.blockSize));
  }

  void _stepBlocks(_Track t, double dt) {
    final survivors = <_Block>[];
    for (final b in t.blocks) {
      final y = b.y + _fallSpeed * dt;
      if (_strikes(t, b.lane, y)) {
        _eliminate(t, b.lane);
        return; // track is done; drop remaining blocks
      }
      if (y > t.band.bottom + _Tuning.blockSize) continue; // fell past
      survivors.add(_Block(lane: b.lane, y: y));
    }
    t.blocks
      ..clear()
      ..addAll(survivors);
  }

  bool _strikes(_Track t, int blockLane, double blockY) {
    if (blockLane != t.hopper.lane) return false;
    final dy = (blockY - t.runnerY).abs();
    return dy <= _Tuning.blockSize / 2 + _Tuning.hitPad;
  }

  /// Bots slide away from imminent blocks; accuracy gates whether they react.
  void _driveBots(double dt) {
    for (final t in _tracks) {
      final clock = t.clock;
      if (clock == null || !t.alive) continue;
      if (!clock.tick(dt)) continue;
      if (_botShouldDodge(t)) {
        _swap(t.playerId);
      }
      clock.arm(ctx.botProfile, ctx.rng);
    }
  }

  bool _botShouldDodge(_Track t) {
    final threat = _nearestThreatLane(t);
    if (threat == null || threat != t.hopper.lane) return false;
    // Skill gate: weak bots sometimes freeze (errorRate) and get hit.
    return !ctx.rng.chance(ctx.botProfile.errorRate);
  }

  void _eliminate(_Track t, int lane) {
    t.alive = false;
    t.blocks.clear();
    _eliminationOrder.add(t.playerId);
    final at = Offset(t.lanes.coordOf(lane), t.runnerY);
    t.figure.enterRagdoll(at, t.runnerY, Offset(ctx.rng.sign() * 140, -180));
    _juice.ko(at, t.color);
  }

  void _checkEnd() {
    final alive = _tracks.where((t) => t.alive).toList();
    final timeUp = _elapsed >= _Tuning.timeLimit;
    if (alive.length > 1 && !timeUp) return;
    _finish(alive);
  }

  void _finish(List<_Track> alive) {
    final ranking = <int>[
      for (final t in alive) t.playerId,
      ..._eliminationOrder.reversed,
    ];
    // Score = survival time in whole seconds (survivors capped at the limit).
    for (final t in _tracks) {
      final survived = t.alive ? _Tuning.timeLimit : _elapsed;
      setScore(t.playerId, survived.floor());
    }
    _juice.confetti(ctx.arena);
    finishByOrder(ranking);
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);
    for (final t in _tracks) {
      _drawTrack(canvas, t);
    }
    _juice.render(canvas);
    canvas.restore();
  }

  void _drawTrack(Canvas canvas, _Track t) {
    // Band backdrop with a thin divider.
    canvas.drawRect(t.band, Paint()..color = const Color(0xFF111722));
    canvas.drawRect(
      Rect.fromLTWH(t.band.left, t.band.top, t.band.width, 2),
      Paint()..color = const Color(0x22FFFFFF),
    );
    // Lane guide lines.
    final guide = Paint()
      ..color = const Color(0x18FFFFFF)
      ..strokeWidth = 2;
    for (var i = 0; i < t.lanes.count; i++) {
      final x = t.lanes.coordOf(i);
      canvas.drawLine(
        Offset(x, t.band.top + 8),
        Offset(x, t.band.bottom - 8),
        guide,
      );
    }
    // Falling blocks.
    for (final b in t.blocks) {
      _drawBlock(canvas, t, b);
    }
    // Runner.
    final rx = t.lanes.coordOfVisual(t.hopper.visualLane);
    t.figure.render(canvas, Offset(rx, t.runnerY - _Tuning.figureLift));
  }

  void _drawBlock(Canvas canvas, _Track t, _Block b) {
    final x = t.lanes.coordOf(b.lane);
    final rect = Rect.fromCenter(
      center: Offset(x, b.y),
      width: _Tuning.blockSize,
      height: _Tuning.blockSize,
    );
    final paint = Paint()..color = t.color.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      paint,
    );
    // Inner mark.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(10), const Radius.circular(4)),
      Paint()..color = const Color(0x33000000),
    );
  }
}
