import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/helpers/tap_mash_meter.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';

/// Button Masher — pure tap-count race over a fixed window. Each player has a
/// big pad that pulses on every tap; whoever taps the most when time runs out
/// wins. Score = total taps, ranked highest-first.
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

  // --- Tuning -----------------------------------------------------------------
  static const double _timeLimit = 10;
  static const double _padRadiusFrac = 0.16; // pad radius vs min(arena) side
  static const double _pulseDecayPerSec = 6; // how fast a pad pulse settles
  static const double _pulseGrow = 0.35; // extra scale at a fresh tap

  // Bot cadence (seconds/tap); harder bots mash faster.
  static const double _botBaseInterval = 0.15;
  static const double _botAccuracyBonus = 0.08;
  static const double _botJitter = 0.035;

  late Juice _juice;
  double _elapsed = 0;
  final Map<int, _Pad> _pads = <int, _Pad>{};

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    for (final p in ctx.players) {
      _pads[p.id] = _Pad(
        slot: p,
        meter: TapMashMeter(tapImpulse: 1, maxValue: 1e9), // count-only meter
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

    for (final pad in _pads.values) {
      // Settle the visual pulse back toward rest.
      pad.pulse = math.max(0, pad.pulse - _pulseDecayPerSec * sdt);
      setScore(pad.slot.id, pad.meter.tapCount);
    }

    if (_elapsed >= _timeLimit) {
      finishByScore(); // most taps wins
    }
  }

  void _driveBots(double dt) {
    for (final pad in _pads.values) {
      if (!pad.slot.isBot) continue;
      pad.botClock += dt;
      while (pad.botClock >= pad.nextTapAt) {
        pad.botClock -= pad.nextTapAt;
        _tap(pad.slot.id);
        pad.nextTapAt = _nextBotInterval(pad);
      }
    }
  }

  double _nextBotInterval(_Pad pad) {
    final jitter = ctx.rng.jitter(_botJitter);
    return math.max(0.03, pad.botInterval + jitter);
  }

  void _tap(int id) {
    final pad = _pads[id];
    if (pad == null) return;
    pad.meter.tap();
    pad.pulse = 1;
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    final radius = math.min(size.width, size.height) * _padRadiusFrac;
    final centers = _padCenters(size);
    for (final p in ctx.players) {
      final pad = _pads[p.id]!;
      _drawPad(canvas, centers[p.id]!, radius, pad);
    }

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawPad(Canvas canvas, Offset center, double radius, _Pad pad) {
    final color = Color(pad.slot.colorArgb);
    final scale = 1 + pad.pulse * _pulseGrow;
    final r = radius * scale;
    canvas.drawCircle(center, r, Paint()..color = color.withValues(alpha: 0.85));
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color,
    );
  }

  /// Lay pads out per player count: 1 center, 2 top/bottom, 3-4 in a grid.
  Map<int, Offset> _padCenters(Size size) {
    final players = ctx.players;
    final n = players.length;
    final w = size.width, h = size.height;
    final spots = switch (n) {
      1 => [Offset(w / 2, h / 2)],
      2 => [Offset(w / 2, h * 0.72), Offset(w / 2, h * 0.28)],
      3 => [
          Offset(w / 2, h * 0.72),
          Offset(w * 0.28, h * 0.28),
          Offset(w * 0.72, h * 0.28),
        ],
      _ => [
          Offset(w * 0.28, h * 0.72),
          Offset(w * 0.72, h * 0.72),
          Offset(w * 0.28, h * 0.28),
          Offset(w * 0.72, h * 0.28),
        ],
    };
    return {for (var i = 0; i < n; i++) players[i].id: spots[i]};
  }
}

/// Per-player pad state for one round.
class _Pad {
  final PlayerSlot slot;
  final TapMashMeter meter;
  final double botInterval;

  double pulse = 0; // 0..1 visual punch, decays each frame
  double botClock = 0;
  double nextTapAt;

  _Pad({
    required this.slot,
    required this.meter,
    required this.botInterval,
  }) : nextTapAt = botInterval;
}
