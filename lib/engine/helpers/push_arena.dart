import 'dart:math' as math;
import 'dart:ui';

/// Frame rate the [PushArena.friction] coefficient is calibrated against, so a
/// value of e.g. 0.98 means "keep 98% of speed every 1/60 s" regardless of the
/// real frame [dt]. Keeps motion identical at any FPS.
const double kFrictionReferenceFps = 60.0;

/// Below this speed (in arena units per second) a body is snapped to rest, so
/// friction settles bodies instead of leaving them drifting forever.
const double kRestSpeedEpsilon = 0.001;

/// A movable circle in a [PushArena]: a player puck or the ball.
///
/// Mutable on purpose — the arena integrates these in place every frame and a
/// round-scoped sim does not need persistence. [id] is the owning player id, or
/// -1 for a neutral ball. [alive] flips to false when a body falls off a ring
/// arena (it is never set false by rect-bounded arenas).
class Body {
  /// Owning player id, or -1 for a neutral ball.
  final int id;

  /// Center position in arena units.
  Offset pos;

  /// Velocity in arena units per second.
  Offset vel;

  /// Collision radius in arena units.
  final double radius;

  /// Mass used for momentum-conserving collisions and overlap resolution.
  final double mass;

  /// False once eliminated (ring arenas only).
  bool alive;

  /// Creates a body.
  ///
  /// Throws [ArgumentError] when [radius] or [mass] is not strictly positive,
  /// or when any value is non-finite.
  Body({
    required this.id,
    required this.pos,
    this.vel = Offset.zero,
    required this.radius,
    this.mass = 1.0,
    this.alive = true,
  }) {
    if (!radius.isFinite || radius <= 0) {
      throw ArgumentError.value(radius, 'radius', 'must be > 0 and finite');
    }
    if (!mass.isFinite || mass <= 0) {
      throw ArgumentError.value(mass, 'mass', 'must be > 0 and finite');
    }
    if (!pos.dx.isFinite || !pos.dy.isFinite) {
      throw ArgumentError.value(pos, 'pos', 'must be finite');
    }
  }
}

/// A lightweight 2-D circle-physics arena: no Box2D/forge2d, just enough to
/// shove pucks around and bounce a ball.
///
/// Two flavours, chosen at construction:
///
/// * **Ring** (default): bodies whose *center* leaves the circle of
///   [ringRadius] around [center] are marked `alive = false` (knocked out).
///   This drives sumo / king-of-the-hill games.
/// * **Rect** (pass [bounds]): bodies bounce off the rectangle walls and are
///   never eliminated — used for an enclosed pitch.
///
/// Collisions between bodies are resolved as elastic impacts along the contact
/// normal, conserving momentum with per-body [Body.mass], and overlaps are
/// separated so circles never stick together.
///
/// Reused by Sumo Smash, Bumper Balls and One-Touch Soccer.
class PushArena {
  /// Ring center (also a convenient pitch center for rect arenas).
  final Offset center;

  /// Ring radius; bodies whose center passes this are eliminated (ring mode).
  final double ringRadius;

  /// Per-1/60s velocity retention in `(0, 1]`. 1 = frictionless.
  final double friction;

  /// Bounciness of body-body and wall collisions in `[0, 1]`. 1 = perfectly
  /// elastic, 0 = bodies stop dead along the contact normal.
  final double restitution;

  /// When set, the arena is rect-bounded: bodies bounce off these walls and are
  /// never eliminated. When null, the arena is a ring.
  final Rect? bounds;

  final List<Body> _bodies = <Body>[];

  /// Creates an arena.
  ///
  /// Throws [ArgumentError] when [ringRadius] <= 0, when [friction] is outside
  /// `(0, 1]`, when [restitution] is outside `[0, 1]`, or for non-finite input.
  PushArena({
    required this.center,
    required this.ringRadius,
    this.friction = 0.98,
    this.restitution = 0.9,
    this.bounds,
  }) {
    if (!ringRadius.isFinite || ringRadius <= 0) {
      throw ArgumentError.value(
          ringRadius, 'ringRadius', 'must be > 0 and finite');
    }
    if (!friction.isFinite || friction <= 0 || friction > 1) {
      throw ArgumentError.value(
          friction, 'friction', 'must be in (0, 1]');
    }
    if (!restitution.isFinite || restitution < 0 || restitution > 1) {
      throw ArgumentError.value(
          restitution, 'restitution', 'must be in [0, 1]');
    }
  }

  /// True when this arena bounces off rectangle walls instead of a ring.
  bool get isRectBounded => bounds != null;

  /// All bodies, alive or not (unmodifiable view; mutate via [add]).
  List<Body> get bodies => List<Body>.unmodifiable(_bodies);

  /// Only the bodies still in play.
  List<Body> get aliveBodies =>
      _bodies.where((b) => b.alive).toList(growable: false);

  /// Add a body to the simulation.
  void add(Body body) => _bodies.add(body);

  /// Apply an instantaneous velocity change of [delta] to every alive body with
  /// the given [id] (player puck or ball). No-op if none match or [delta] is
  /// non-finite.
  void impulse(int id, Offset delta) {
    if (!delta.dx.isFinite || !delta.dy.isFinite) return;
    for (final b in _bodies) {
      if (b.alive && b.id == id) {
        b.vel += delta;
      }
    }
  }

  /// True when [body]'s center is outside the ring (always false in rect mode).
  bool isOnRing(Body body) {
    if (isRectBounded) return false;
    return (body.pos - center).distance > ringRadius;
  }

  /// Advance the whole simulation by [dt] seconds:
  /// 1. apply friction, 2. integrate positions, 3. resolve body-body
  /// collisions, 4. apply boundary (ring elimination or wall bounce).
  ///
  /// Non-positive or non-finite [dt] is ignored.
  void update(double dt) {
    if (!dt.isFinite || dt <= 0) return;

    _applyFrictionAndIntegrate(dt);
    _resolveCollisions();
    if (isRectBounded) {
      _bounceWalls(bounds!);
    } else {
      _applyRingFalloff();
    }
  }

  /// Friction as frame-rate-independent exponential decay, then Euler step.
  void _applyFrictionAndIntegrate(double dt) {
    // friction^(dt * 60): exact per-1/60s retention compounded over this frame.
    final decay = friction == 1.0
        ? 1.0
        : math.pow(friction, dt * kFrictionReferenceFps).toDouble();
    for (final b in _bodies) {
      if (!b.alive) continue;
      var v = b.vel * decay;
      if (v.distance < kRestSpeedEpsilon) v = Offset.zero;
      b.vel = v;
      b.pos += v * dt;
    }
  }

  /// Resolve every alive pair of overlapping circles: separate them so they no
  /// longer interpenetrate, then exchange momentum along the contact normal.
  void _resolveCollisions() {
    final alive = _bodies.where((b) => b.alive).toList(growable: false);
    for (var i = 0; i < alive.length; i++) {
      for (var j = i + 1; j < alive.length; j++) {
        _collide(alive[i], alive[j]);
      }
    }
  }

  void _collide(Body a, Body b) {
    final delta = b.pos - a.pos;
    final dist = delta.distance;
    final minDist = a.radius + b.radius;
    if (dist >= minDist) return; // not touching

    // Contact normal (a -> b). Degenerate exactly-overlapping centers get a
    // deterministic fallback so we never divide by zero.
    final normal = dist > 0 ? delta / dist : const Offset(1, 0);
    final overlap = minDist - (dist > 0 ? dist : 0);

    // --- Positional correction: push apart inversely to mass. ---
    final invA = 1.0 / a.mass;
    final invB = 1.0 / b.mass;
    final invSum = invA + invB;
    final corr = normal * (overlap / invSum);
    a.pos -= corr * invA;
    b.pos += corr * invB;

    // --- Velocity response along the normal (1-D elastic with restitution). ---
    final relVel = b.vel - a.vel;
    final velAlongNormal = relVel.dx * normal.dx + relVel.dy * normal.dy;
    if (velAlongNormal > 0) return; // already separating

    final impulseMag = -(1 + restitution) * velAlongNormal / invSum;
    final impulse = normal * impulseMag;
    a.vel -= impulse * invA;
    b.vel += impulse * invB;
  }

  /// Mark any body whose center has left the ring as eliminated and freeze it.
  void _applyRingFalloff() {
    for (final b in _bodies) {
      if (!b.alive) continue;
      if ((b.pos - center).distance > ringRadius) {
        b.alive = false;
        b.vel = Offset.zero;
      }
    }
  }

  /// Reflect alive bodies off the rectangle walls, clamping the body fully
  /// inside so it cannot tunnel out, and damping by [restitution].
  void _bounceWalls(Rect rect) {
    for (final b in _bodies) {
      if (!b.alive) continue;
      var px = b.pos.dx;
      var py = b.pos.dy;
      var vx = b.vel.dx;
      var vy = b.vel.dy;
      final r = b.radius;

      final left = rect.left + r;
      final right = rect.right - r;
      final top = rect.top + r;
      final bottom = rect.bottom - r;

      if (px < left) {
        px = left;
        if (vx < 0) vx = -vx * restitution;
      } else if (px > right) {
        px = right;
        if (vx > 0) vx = -vx * restitution;
      }
      if (py < top) {
        py = top;
        if (vy < 0) vy = -vy * restitution;
      } else if (py > bottom) {
        py = bottom;
        if (vy > 0) vy = -vy * restitution;
      }

      b.pos = Offset(px, py);
      b.vel = Offset(vx, vy);
    }
  }
}
