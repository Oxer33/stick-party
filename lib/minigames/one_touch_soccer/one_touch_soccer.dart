import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/push_arena.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'soccer_render.dart';

/// One-Touch Soccer — a rect-bounded pitch with a neutral ball (id -1) and one
/// stick player per seat. A tap LUNGES your player at the ball: a kick-dash.
///
/// Depth (still one-touch):
///  * **Kick power** scales with the player's approach speed plus a strong
///    proximity bonus, so a well-timed lunge into the ball is a satisfying
///    "thwack" (squash + spark burst + hit-stop) while a far lunge is a gentle
///    nudge. The ball carries spin, leaves a motion trail and bounces off the
///    walls with restitution.
///  * **Teams / goals**: even ids / [Team.a] attack the RIGHT goal, odd ids /
///    [Team.b] attack the LEFT goal (duel1v1 and team2v2). A goal is scored when
///    the ball crosses a goal mouth (centered, ~42% of the wall height) and
///    awards a point to every player on the scoring side.
///  * **Goal celebration**: net-bulge flash + big "GOAL!" popup + confetti +
///    slow-mo (hit-stop) + a crowd-roar popup, then a brief kickoff pause before
///    the ball resets to center.
///  * Most goals when the 45 s timer expires wins ([finishByScore]); the round
///    always resolves.
///
/// Bots chase the ball, but the rear player on each side drops back to guard its
/// own goal; [BotProfile] drives reaction timing and aim error so positioning
/// reads as intentional rather than a swarm.
class OneTouchSoccer extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'one_touch_soccer',
        name: 'One-Touch Soccer',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.duel1v1, GameMode.team2v2],
        inputHint: 'TAP',
      );

  // ── Arena / sim tuning (no magic numbers inline) ───────────────────────────
  static const double _timeLimit = 45;
  static const int _ballId = -1;
  static const double _pitchInsetFactor = 0.055;
  static const double _ballRadiusFactor = 0.026;
  static const double _playerRadiusFactor = 0.05;
  static const double _ballMass = 0.55; // lighter than pucks so kicks fly
  static const double _pitchFriction = 0.99; // glides on grass
  static const double _ballRestitution = 0.78; // wall bounce damping
  static const double _goalMouthFraction = 0.42; // of pitch height, centered
  static const double _figureScale = 0.95;

  // ── Kick / lunge tuning ─────────────────────────────────────────────────────
  static const double _lungePerSecond = 3.0; // base lunge impulse ≈ pitch*3 /s
  static const double _approachBonus = 0.55; // + share scaled by own speed
  static const double _approachSpeedRef = 520.0; // speed mapped to full bonus
  static const double _proximityRangeFactor = 2.4; // “close” = within this*radii
  static const double _proximityBonus = 0.9; // +90% impulse at point-blank
  static const double _kickCooldownSec = 0.22; // min gap between own lunges
  static const double _directKickScale = 1.7; // explicit ball impulse on contact
  static const double _spinPerSpeed = 0.012; // ball spin gain / speed
  static const double _spinDecayPerSec = 1.6;
  static const double _squashDecayPerSec = 4.5;
  static const double _hardKickSpeed = 360.0; // ball speed above → thwack juice
  static const int _trailLen = 12;

  // ── Goal / celebration tuning ───────────────────────────────────────────────
  static const double _kickoffPauseSec = 1.25; // sim frozen after a goal
  static const double _bulgeDurationSec = 0.9; // net ripple length
  static const double _goalHitStopSec = 0.5; // slow-mo on a goal
  static const double _goalHitStopScale = 0.18;

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botGuardDepthFactor = 0.22; // keeper x offset from wall
  static const double _botGuardLaneGain = 0.7; // how hard keeper tracks ball y
  static const double _botStrikeRangeFactor = 6.0; // commit within this*radii
  static const double _botAimErrorRad = 0.55; // aim jitter at accuracy 0
  static const double _botCarrySpeed = 110.0; // skip lunge while already fast

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _leftAccent = Color(0xFF4D9BFF); // left goal / side B
  static const Color _rightAccent = Color(0xFFFF5A5A); // right goal / side A
  static const Color _confettiA = Color(0xFFFFC93C);
  static const Color _confettiB = Color(0xFF54E08A);
  static const double _runSpeed = 55.0;

  late Juice _juice;
  late PushArena _arena;
  late Rect _pitch;
  late Size _size;
  double _elapsed = 0;
  double _kickoffPause = 0; // > 0 while the post-goal pause runs
  double _leftBulge = 0; // net ripple timers
  double _rightBulge = 0;
  double _ballSpin = 0; // radians, for the seam hint
  double _ballSquash = 0; // 0..1, flatten on hard hits
  Offset _ballLastDir = Offset.zero;

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, StickFigure> _figures = <int, StickFigure>{};
  final Map<int, _KickState> _kick = <int, _KickState>{};

  /// True if this player attacks the RIGHT goal (else the LEFT goal).
  final Map<int, bool> _attacksRight = <int, bool>{};

  /// Recent ball centers (newest last) for the motion trail.
  final List<Offset> _ballTrail = <Offset>[];

  late Body _ball;
  late double _ballRadius;
  late double _playerRadius;
  Rect _goalMouth = Rect.zero; // vertical span both goals share
  double _leftLine = 0;
  double _rightLine = 0;
  bool _hasLeftSide = false; // someone defends/attacks each goal
  bool _hasRightSide = false;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    final inset = math.min(_size.width, _size.height) * _pitchInsetFactor;
    _pitch = Rect.fromLTRB(
      inset,
      inset,
      _size.width - inset,
      _size.height - inset,
    );
    final minSide = math.min(_pitch.width, _pitch.height);
    _ballRadius = minSide * _ballRadiusFactor;
    _playerRadius = minSide * _playerRadiusFactor;

    _arena = PushArena(
      center: _pitch.center,
      ringRadius: _pitch.shortestSide / 2, // unused in rect mode but required
      friction: _pitchFriction,
      restitution: _ballRestitution,
      bounds: _pitch,
    );

    _computeGoals();
    _buildBall();
    _buildPlayers();
    begin();
  }

  void _computeGoals() {
    final mouthHeight = _pitch.height * _goalMouthFraction;
    final top = _pitch.center.dy - mouthHeight / 2;
    _goalMouth =
        Rect.fromLTRB(_pitch.left, top, _pitch.right, top + mouthHeight);
    // A goal counts once the ball center reaches the wall contact line.
    _leftLine = _pitch.left + _ballRadius;
    _rightLine = _pitch.right - _ballRadius;
  }

  void _buildBall() {
    _ball = Body(
      id: _ballId,
      pos: _pitch.center,
      vel: Offset.zero,
      radius: _ballRadius,
      mass: _ballMass,
    );
    _arena.add(_ball);
    _ballTrail.add(_ball.pos);
  }

  void _buildPlayers() {
    final players = ctx.players;
    for (final p in players) {
      final attacksRight = _resolveSide(p);
      _attacksRight[p.id] = attacksRight;
      if (attacksRight) {
        _hasRightSide = true;
      } else {
        _hasLeftSide = true;
      }

      // Spawn each player on its own defending half, stacked vertically.
      final defendLeft = attacksRight; // attack right ⇒ defend/start on left
      final sameSide =
          players.where((q) => _resolveSide(q) == attacksRight).toList();
      final indexOnSide = sameSide.indexWhere((q) => q.id == p.id);
      final lane = (indexOnSide + 1) / (sameSide.length + 1);
      final x = defendLeft
          ? _pitch.left + _pitch.width * 0.27
          : _pitch.right - _pitch.width * 0.27;
      final y = _pitch.top + _pitch.height * lane;
      _arena.add(Body(id: p.id, pos: Offset(x, y), radius: _playerRadius));

      _figures[p.id] = StickFigure(
        proportions: StickProportions.hero.scaled(_figureScale),
        style: _styleFor(Color(p.colorArgb)),
        facing: attacksRight ? 1.0 : -1.0,
      )..setLoco(LocoState.idle);

      _kick[p.id] = _KickState();
      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  /// Bright kit style: player-color fill with a brightened outline + glow.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 4,
        lineWidth: 1.0,
        rimAlpha: 0.26,
        shadowAlpha: 0.0, // renderer draws its own contact shadow
        gradientBottom: 0.5,
        smearAlpha: 0.26,
      );

  /// Even ids / Team.a attack right; odd ids / Team.b attack left.
  bool _resolveSide(PlayerSlot p) {
    if (p.team == Team.a) return true;
    if (p.team == Team.b) return false;
    return p.id.isEven;
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _act(input.playerId);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;

    // Juice always runs on real dt; the sim runs on hit-stop-scaled dt.
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);
    _tickTimers(dt);

    // During the kickoff pause the world is frozen (only juice + timers run).
    if (_kickoffPause > 0) {
      _syncFigures(0);
      if (_elapsed >= _timeLimit) finishByScore();
      return;
    }

    _tickKickStates(dt);
    _driveBots(dt);
    _arena.update(sdt);

    _updateBall(sdt);
    _syncFigures(sdt);
    _checkGoals();

    if (_elapsed >= _timeLimit) {
      finishByScore();
    }
  }

  void _tickTimers(double dt) {
    if (_kickoffPause > 0) _kickoffPause = math.max(0, _kickoffPause - dt);
    if (_leftBulge > 0) _leftBulge = math.max(0, _leftBulge - dt);
    if (_rightBulge > 0) _rightBulge = math.max(0, _rightBulge - dt);
  }

  void _tickKickStates(double dt) {
    for (final s in _kick.values) {
      s.tick(dt);
    }
  }

  /// Advance ball-only visual state (trail, spin, squash) on the sim clock.
  void _updateBall(double dt) {
    final speed = _ball.vel.distance;
    if (speed > 1) _ballLastDir = _ball.vel / speed;

    _ballTrail.add(_ball.pos);
    while (_ballTrail.length > _trailLen) {
      _ballTrail.removeAt(0);
    }

    // Spin accumulates with travel, decays at rest.
    _ballSpin += speed * _spinPerSpeed * dt;
    if (speed < 1) {
      _ballSpin *= math.max(0.0, 1 - _spinDecayPerSec * dt);
    }
    _ballSquash = (_ballSquash - _squashDecayPerSec * dt).clamp(0.0, 1.0);
  }

  void _driveBots(double dt) {
    for (final entry in _botClocks.entries) {
      final id = entry.key;
      if (!entry.value.tick(dt)) continue;
      entry.value.arm(ctx.botProfile, ctx.rng);
      _botDecide(id);
    }
  }

  /// Bot decision: the rear player on a side guards its goal (steers back toward
  /// the keeper slot); everyone else commits a lunge at the ball when it is in
  /// range and they are not already carrying speed. [BotProfile] adds hesitation
  /// (errorRate) and aim jitter (accuracy) so positioning feels deliberate.
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    final state = _kick[playerId];
    if (self == null || state == null || !state.ready) return;
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // deliberate hesitate

    if (_isKeeper(playerId)) {
      _botGuard(playerId, self);
      return;
    }

    final toBall = _ball.pos - self.pos;
    final inRange = toBall.distance <= _playerRadius * _botStrikeRangeFactor;
    final alreadyFast = self.vel.distance > _botCarrySpeed;
    if (!inRange || alreadyFast) return;

    var dir = _normalize(toBall);
    if (dir == Offset.zero) dir = const Offset(0, -1);
    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botAimErrorRad;
    final a = math.atan2(dir.dy, dir.dx) + ctx.rng.jitter(err);
    _commitLunge(playerId, self, Offset(math.cos(a), math.sin(a)));
  }

  /// Keeper behaviour: ease toward a guard slot in front of its own goal,
  /// tracking the ball's vertical position so it covers shots on goal.
  void _botGuard(int playerId, Body self) {
    final attacksRight = _attacksRight[playerId] ?? true;
    final guardX = attacksRight
        ? _pitch.left + _pitch.width * _botGuardDepthFactor
        : _pitch.right - _pitch.width * _botGuardDepthFactor;
    final targetY = _pitch.center.dy +
        (_ball.pos.dy - _pitch.center.dy) * _botGuardLaneGain;
    final target = Offset(guardX, targetY);
    // Only nudge if meaningfully out of position (keeps it from jittering).
    if ((target - self.pos).distance < _playerRadius * 0.8) return;
    final dir = _normalize(target - self.pos);
    if (dir == Offset.zero) return;
    _commitLunge(playerId, self, dir, lunge: false);
  }

  /// The rear-most player on a side (closest to its own goal) keeps net. A lone
  /// player on a side never keeps net (they must attack to ever score).
  bool _isKeeper(int playerId) {
    final attacksRight = _attacksRight[playerId] ?? true;
    final mates = _attacksRight.entries
        .where((e) => e.value == attacksRight)
        .map((e) => e.key)
        .toList();
    if (mates.length < 2) return false;
    // "Rear" = deepest in own half. Own goal is LEFT when attacking right.
    var rear = mates.first;
    var rearDepth = double.negativeInfinity;
    for (final id in mates) {
      final b = _bodyOf(id);
      if (b == null) continue;
      // Depth from the opponent goal (bigger = deeper toward own goal).
      final depth =
          attacksRight ? (_pitch.right - b.pos.dx) : (b.pos.dx - _pitch.left);
      if (depth > rearDepth) {
        rearDepth = depth;
        rear = id;
      }
    }
    return rear == playerId;
  }

  /// Human/bot tap → lunge toward the ball if off cooldown.
  void _act(int playerId) {
    final self = _bodyOf(playerId);
    final state = _kick[playerId];
    if (self == null || state == null || !state.ready) return;
    var dir = _normalize(_ball.pos - self.pos);
    if (dir == Offset.zero) dir = const Offset(1, 0);
    _commitLunge(playerId, self, dir);
  }

  /// Shared lunge commit: kick-power impulse (approach speed + proximity bonus),
  /// an explicit "thwack" on the ball when point-blank, cooldown, figure dash
  /// pose, dust kick and contact juice. [lunge] false = a quiet repositioning
  /// nudge (used by the keeper) with no thwack/dust.
  void _commitLunge(int playerId, Body self, Offset dir, {bool lunge = true}) {
    final state = _kick[playerId];
    if (state == null || !state.ready) return;

    final ownSpeed = self.vel.distance;
    final distToBall = (_ball.pos - self.pos).distance;
    final closeRange = (_playerRadius + _ballRadius) * _proximityRangeFactor;
    final proximity =
        (1.0 - (distToBall / closeRange)).clamp(0.0, 1.0); // 1 at point-blank
    final approach =
        (ownSpeed / _approachSpeedRef).clamp(0.0, 1.0); // 1 at full sprint

    final power = lunge
        ? 1.0 + _approachBonus * approach + _proximityBonus * proximity
        : 0.55; // gentle keeper reposition
    final magnitude = _pitch.width * _lungePerSecond * power;
    _arena.impulse(playerId, dir * magnitude);

    state.fire(_kickCooldownSec, charge: lunge ? power : 0);

    final fig = _figures[playerId];
    if (fig != null) {
      fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      if (lunge) fig.dash();
    }

    if (!lunge) return;

    // Explicit ball kick when the lunge starts point-blank: a crisp "thwack"
    // on top of the physical collision so close kicks feel powerful.
    if (proximity > 0.0) {
      final kickDir = _normalize(_ball.pos - self.pos);
      if (kickDir != Offset.zero) {
        final kickMag =
            _pitch.width * _lungePerSecond * _directKickScale * proximity;
        _arena.impulse(_ballId, kickDir * kickMag);
        _onBallKicked(proximity);
      }
    }

    // Dust kick behind the lunge + a light spark telegraph.
    _juice.particles.burst(
      at: self.pos - dir * _playerRadius,
      count: 6,
      color: const Color(0xFFDFF3E4),
      speed: 150,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 4,
      gravity: 220,
      life: 0.32,
    );
  }

  /// React to a hard ball contact: squash the ball + spark + hit-stop + a small
  /// crowd "THWACK" pop on the very hardest strikes.
  void _onBallKicked(double proximity) {
    final speed = _ball.vel.distance;
    _ballSquash =
        (proximity * 0.8 + (speed / _hardKickSpeed) * 0.4).clamp(0.0, 1.0);
    if (speed >= _hardKickSpeed) {
      _juice.hit(_ball.pos, const Color(0xFFFFFFFF), sparks: 10);
      _juice.shake.light();
      _juice.popup(_ball.pos.translate(0, -_ballRadius * 2.4), 'THWACK!',
          const Color(0xFFFFE08A), size: _ballRadius * 1.8);
    } else {
      _juice.particles.burst(
        at: _ball.pos,
        count: 5,
        color: const Color(0xFFFFFFFF),
        speed: 180,
        size: 4,
        life: 0.28,
      );
    }
  }

  void _syncFigures(double dt) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null) {
        fig.setLoco(
            body.vel.distance > _runSpeed ? LocoState.run : LocoState.idle);
      }
      fig.update(dt);
    }
  }

  /// Award a goal when the ball reaches a goal line within the goal mouth.
  void _checkGoals() {
    final withinMouth =
        _ball.pos.dy >= _goalMouth.top && _ball.pos.dy <= _goalMouth.bottom;
    if (!withinMouth) return;

    if (_ball.pos.dx <= _leftLine && _hasLeftSide) {
      // Scored on the LEFT goal ⇒ the RIGHT-attacking side scores.
      _scoreFor(attacksRight: true);
    } else if (_ball.pos.dx >= _rightLine && _hasRightSide) {
      // Scored on the RIGHT goal ⇒ the LEFT-attacking side scores.
      _scoreFor(attacksRight: false);
    }
  }

  void _scoreFor({required bool attacksRight}) {
    for (final p in ctx.players) {
      if (_attacksRight[p.id] == attacksRight) addScore(p.id, 1);
    }
    final color = _sideColor(attacksRight);

    // Net bulge on the goal that was scored ON (opposite the scorer's side).
    if (attacksRight) {
      _leftBulge = _bulgeDurationSec; // ball went into the LEFT goal
    } else {
      _rightBulge = _bulgeDurationSec;
    }

    // Celebration: explosion + GOAL popup + crowd roar + confetti + slow-mo.
    _juice.ko(_ball.pos, color);
    _juice.popup(
        _pitch.center, 'GOAL!', color, size: _pitch.shortestSide * 0.12);
    _juice.popup(_pitch.center.translate(0, _pitch.shortestSide * 0.12),
        'CROWD ROARS!', const Color(0xFFFFE08A),
        size: _pitch.shortestSide * 0.04);
    _juice.confetti(_size, colors: [color, _confettiA, _confettiB]);
    _juice.hitStop.trigger(_goalHitStopSec, scale: _goalHitStopScale);
    _juice.shake.heavy();

    _kickoffPause = _kickoffPauseSec;
    _resetBall();
  }

  void _resetBall() {
    _ball.pos = _pitch.center;
    _ball.vel = Offset.zero;
    _ballSpin = 0;
    _ballSquash = 0;
    _ballLastDir = Offset.zero;
    _ballTrail
      ..clear()
      ..add(_ball.pos);
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    SoccerRenderer.drawBackground(canvas, size);
    SoccerRenderer.drawPitch(canvas, _pitch);
    SoccerRenderer.drawGoal(canvas, _pitch, _goalMouth,
        onRight: false, color: _leftAccent, bulge: _bulgeFill(_leftBulge));
    SoccerRenderer.drawGoal(canvas, _pitch, _goalMouth,
        onRight: true, color: _rightAccent, bulge: _bulgeFill(_rightBulge));

    _drawPlayers(canvas);

    SoccerRenderer.drawBall(
      canvas,
      _ball.pos,
      _ballRadius,
      trail: List<Offset>.unmodifiable(_ballTrail),
      velDir: _ballLastDir,
      spin: _ballSpin,
      squash: _ballSquash,
    );

    SoccerRenderer.drawVignette(canvas, size);
    _drawScoreboard(canvas);
    SoccerRenderer.drawKickoffBanner(
        canvas, _pitch, 'KICK OFF', _kickoffBannerAlpha());

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawPlayers(Canvas canvas) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      if (body == null) continue;
      final actor = _actorFor(entry.key, body, entry.value);
      SoccerRenderer.drawActorGround(canvas, actor);
      SoccerRenderer.drawActor(canvas, actor);
    }
  }

  SoccerActor _actorFor(int id, Body body, StickFigure fig) {
    final feet = Offset(body.pos.dx, body.pos.dy + body.radius);
    return SoccerActor(
      figure: fig,
      // Figure pelvis anchors at feet so the stick stands on its disc.
      root: feet,
      feet: feet,
      radius: body.radius,
      color: Color(_colorOf(id)),
      number: id + 1,
      kickFlash: _kick[id]?.flash ?? 0,
    );
  }

  void _drawScoreboard(Canvas canvas) {
    SoccerRenderer.drawScoreboard(
      canvas,
      _pitch,
      SoccerSide(
        color: _leftAccent,
        score: _sideScore(attacksRight: false),
        label: 'L',
      ),
      SoccerSide(
        color: _rightAccent,
        score: _sideScore(attacksRight: true),
        label: 'R',
      ),
      math.max(0.0, _timeLimit - _elapsed),
    );
  }

  // ── Small pure helpers ──────────────────────────────────────────────────────

  /// 0..1 net-ripple strength with an ease-out fade.
  double _bulgeFill(double remaining) {
    if (remaining <= 0) return 0;
    return (remaining / _bulgeDurationSec).clamp(0.0, 1.0);
  }

  /// 0..1 fade for the kickoff banner (fades out as the pause ends).
  double _kickoffBannerAlpha() {
    if (_kickoffPause <= 0) return 0;
    return (_kickoffPause / _kickoffPauseSec).clamp(0.0, 1.0);
  }

  /// Score for one side (any one member's score; all members share it).
  int _sideScore({required bool attacksRight}) {
    for (final p in ctx.players) {
      if (_attacksRight[p.id] == attacksRight) return scoreOf(p.id).round();
    }
    return 0;
  }

  Color _sideColor(bool attacksRight) =>
      attacksRight ? _rightAccent : _leftAccent;

  Body? _bodyOf(int id) {
    for (final b in _arena.bodies) {
      if (b.id == id) return b;
    }
    return null;
  }

  int _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return p.colorArgb;
    }
    return 0xFFFFFFFF;
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }
}

/// Per-player kick bookkeeping: lunge cooldown + a short ground-ring flash.
/// Mutable round-scoped state (allowed for the duration of one round).
class _KickState {
  static const double _flashDecayPerSec = 5.0;
  double _cooldown = 0; // seconds until the next lunge is allowed
  double _flash = 0; // 0..1 ground-ring brighten on a recent kick

  bool get ready => _cooldown <= 0;

  /// 0..1 kick-charge flash for the ground ring.
  double get flash => _flash.clamp(0.0, 1.0);

  void tick(double dt) {
    if (_cooldown > 0) _cooldown = math.max(0, _cooldown - dt);
    if (_flash > 0) _flash = math.max(0, _flash - _flashDecayPerSec * dt);
  }

  void fire(double cooldownSec, {double charge = 0}) {
    _cooldown = cooldownSec;
    if (charge > _flash) _flash = charge.clamp(0.0, 1.0);
  }
}
