import 'dart:math' as math;
import 'dart:ui';

import 'stick_skeleton.dart';
import 'stick_style.dart';
import 'weapon_visual.dart';

/// Renders a resolved [StickFrame] with a [StickStyle] onto a canvas.
///
/// Pure drawing — no state. Draw order fakes side-view depth (back limbs behind
/// the torso, front limbs + weapon in front).
///
/// Premium rendering features (all opt-out safe via StickStyle fields):
///  - Tapered filled bone quads with inner highlight rim.
///  - Layered neon: soft outer glow (single blur pass) + crisp core stroke + rim.
///  - Ground drop-shadow ellipse beneath lowest foot (no blur — cheap).
///  - Vertical gradient on torso fill.
///  - Head: filled circle + neon ring + bright eye dot + direction cue.
///  - Weapon motion arc trail when [prev] frame is provided (no blur).
///  - Velocity-based limb smear ghost on fast-moving limbs.
///  - Rounded silhouette: shoulder / hip / hand / foot accent shapes.
///  - Chest core glow with optional [StickStyle.corePulse] modulation.
///  - Rim light along lit side of torso.
///  - Weapon: sharp edge-light + tip sparkle.
///  - Per-style flourish flag: boss horns, shadow wisps.
class StickmanPainter {
  StickmanPainter._();

  // ── Static paint objects ── mutated in place, never recreated ──────────────
  //
  // INVARIANT: no `Paint()` call may appear inside paint() or any helper it
  // calls.  Every Paint is declared here as `static final` and mutated before
  // each use.  maskFilter is always cleared (set to null) after use.

  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final Paint _fill = Paint()..style = PaintingStyle.fill;

  /// Used ONLY for the single outer-glow pass with MaskFilter.blur.
  static final Paint _glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  // ── Reusable Path objects ── reset() before each use ───────────────────────

  /// General-purpose tapered-quad path; reused for every bone quad.
  static final Path _quadPath = Path();

  /// General-purpose second path for weapon trail + whip curve.
  static final Path _trailPath = Path();

  // ── Color helpers ───────────────────────────────────────────────────────────

  static Color _dim(Color c, double t) =>
      Color.lerp(c, const Color(0xFF000000), t) ?? c;

  static Color _withAlpha(Color c, double a) =>
      c.withValues(alpha: (c.a * a).clamp(0.0, 1.0));

  static Color _lerp(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Paint [frame] using [style].
  ///
  /// Optional [weapon] drawn in the front hand (defaults to none).
  /// Optional [prev] prior frame — enables weapon motion-trail arc and
  /// velocity-based limb smear ghosts.
  static void paint(
    Canvas canvas,
    StickFrame frame,
    StickStyle style, {
    WeaponVisual weapon = WeaponVisual.none,
    StickFrame? prev,
  }) {
    final a = style.alpha.clamp(0.0, 1.0);
    if (a <= 0.01) return;

    final limbW = frame.limbWidth * style.lineWidth;
    final torsoW = frame.torsoWidth * style.lineWidth;
    final outline = _withAlpha(style.outline, a);
    final backColor = _dim(outline, 0.45);

    // ── Ground drop-shadow (no blur — cheap ellipse) ─────────────────────────
    if (style.shadowAlpha > 0.01) {
      _drawGroundShadow(canvas, frame, style, a);
    }

    // ── SINGLE outer glow pass (the only MaskFilter.blur in the whole draw) ──
    if (style.glowSigma > 0) {
      _drawOuterGlow(canvas, frame, style, limbW, a);
    }

    // ── Velocity smear ghost (back limbs) — drawn below everything ───────────
    if (prev != null && style.smearAlpha > 0.01) {
      _drawSmear(canvas, frame, prev, style, limbW, a);
    }

    // ── Back limbs (behind torso, dimmer) ────────────────────────────────────
    _taperedBone(canvas, frame.chest, frame.backElbow, backColor, limbW,
        style.rimAlpha, a);
    _taperedBone(canvas, frame.backElbow, frame.backHand, backColor, limbW,
        style.rimAlpha, a);
    _taperedBone(canvas, frame.pelvis, frame.backKnee, backColor, limbW,
        style.rimAlpha, a);
    _taperedBone(canvas, frame.backKnee, frame.backFoot, backColor, limbW,
        style.rimAlpha, a);

    // Back hand/foot accents.
    _drawExtremity(canvas, frame.backHand, backColor, limbW * 0.55);
    _drawExtremity(canvas, frame.backFoot, backColor, limbW * 0.55);

    // ── Torso (gradient fill + bone + shoulder/hip nubs) ─────────────────────
    _drawTorso(canvas, frame, style, torsoW, outline, a);

    // Neck bone (chest → headCenter base).
    _taperedBone(
        canvas, frame.chest, frame.headCenter, outline, limbW, style.rimAlpha, a);

    // ── Head ─────────────────────────────────────────────────────────────────
    _drawHead(canvas, frame, style, outline, a);

    // ── Boss / shadow per-style flourishes ────────────────────────────────────
    if (style.flourish) {
      _drawFlourish(canvas, frame, style, outline, limbW, torsoW, a);
    }

    // ── Chest core glow (shadows / charged) ──────────────────────────────────
    if (style.coreColor != null) {
      final core = Offset.lerp(frame.pelvis, frame.chest, 0.5)!;
      // Pulse: add corePulse * (torsoW * 0.6) extra radius; default pulse=0.
      final baseR = math.max(1.5, torsoW * 0.48);
      final pulseR = baseR + style.corePulse.clamp(0.0, 1.0) * torsoW * 0.6;
      // Outer halo ring.
      _stroke
        ..color = _withAlpha(style.coreColor!, a * 0.35)
        ..strokeWidth = math.max(0.8, torsoW * 0.3)
        ..maskFilter = null;
      canvas.drawCircle(core, pulseR * 1.55, _stroke);
      // Bright core dot.
      _fill.color = _withAlpha(style.coreColor!, a * 0.9);
      canvas.drawCircle(core, pulseR, _fill);
    }

    // ── Front legs (in front, full color) ────────────────────────────────────
    _taperedBone(canvas, frame.pelvis, frame.frontKnee, outline, limbW,
        style.rimAlpha, a);
    _taperedBone(canvas, frame.frontKnee, frame.frontFoot, outline, limbW,
        style.rimAlpha, a);
    _drawExtremity(canvas, frame.frontFoot, outline, limbW * 0.65);

    // ── Weapon + motion trail (drawn before front arm) ────────────────────────
    if (weapon.shape != WeaponShape.none) {
      if (prev != null) {
        _drawWeaponTrail(canvas, frame, prev, weapon, a);
      }
      _weapon(canvas, frame, weapon, a);
    }

    // ── Front arms (in front of weapon base) ──────────────────────────────────
    _taperedBone(canvas, frame.chest, frame.frontElbow, outline, limbW,
        style.rimAlpha, a);
    _taperedBone(canvas, frame.frontElbow, frame.frontHand, outline, limbW,
        style.rimAlpha, a);
    _drawExtremity(canvas, frame.frontHand, outline, limbW * 0.65);

    // ── Rim light along lit side of torso ─────────────────────────────────────
    _drawTorsoRim(canvas, frame, style, torsoW, a);
  }

  // ── Ground drop-shadow (no blur) ────────────────────────────────────────────

  static void _drawGroundShadow(
      Canvas canvas, StickFrame frame, StickStyle style, double a) {
    final groundY = math.max(frame.backFoot.dy, frame.frontFoot.dy);
    final cx = (frame.backFoot.dx + frame.frontFoot.dx) * 0.5;
    final shadowA = (style.shadowAlpha * a * 0.7).clamp(0.0, 1.0);

    // Layered ellipses for soft look without blur.
    _fill.maskFilter = null;
    _fill.color = const Color(0xFF000000).withValues(alpha: shadowA * 0.5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, groundY + 4),
        width: frame.torsoWidth * 12 * style.lineWidth,
        height: frame.torsoWidth * 2.8 * style.lineWidth,
      ),
      _fill,
    );
    _fill.color = const Color(0xFF000000).withValues(alpha: shadowA * 0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, groundY + 2),
        width: frame.torsoWidth * 8 * style.lineWidth,
        height: frame.torsoWidth * 1.6 * style.lineWidth,
      ),
      _fill,
    );
  }

  // ── Outer glow pass — THE ONLY MaskFilter.blur in the entire draw ────────────

  static void _drawOuterGlow(Canvas canvas, StickFrame frame, StickStyle style,
      double limbW, double a) {
    final sigma = style.glowSigma.clamp(1.0, 5.0); // clamped to ≤5 per budget
    _glow
      ..color = _withAlpha(style.outline, a * 0.45)
      ..strokeWidth = limbW + 5
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

    void gl(Offset p, Offset q) => canvas.drawLine(p, q, _glow);
    gl(frame.chest, frame.backElbow);
    gl(frame.backElbow, frame.backHand);
    gl(frame.pelvis, frame.backKnee);
    gl(frame.backKnee, frame.backFoot);
    gl(frame.pelvis, frame.chest);
    gl(frame.chest, frame.frontElbow);
    gl(frame.frontElbow, frame.frontHand);
    gl(frame.pelvis, frame.frontKnee);
    gl(frame.frontKnee, frame.frontFoot);

    // Head glow — reuse _glow (already blurred).
    _glow
      ..color = _withAlpha(style.outline, a * 0.35)
      ..strokeWidth = math.max(2.5, frame.headRadius * 0.5);
    canvas.drawCircle(
      frame.headCenter,
      frame.headRadius + sigma * 0.5,
      _glow,
    );

    // Clear blur — must NOT leak to any subsequent draw call.
    _glow.maskFilter = null;
  }

  // ── Velocity smear ghost ──────────────────────────────────────────────────

  static void _drawSmear(Canvas canvas, StickFrame frame, StickFrame prev,
      StickStyle style, double limbW, double a) {
    // Detect fast limbs by measuring displacement.
    final smearA = style.smearAlpha * a;
    final color = _withAlpha(style.outline, smearA * 0.45);
    final backGhost = _dim(color, 0.3);

    // Front arm smear.
    final armDist = (frame.frontHand - prev.frontHand).distance;
    if (armDist > 5.0) {
      final t = (armDist / 18.0).clamp(0.0, 1.0);
      final gc = _withAlpha(color, smearA * t * 0.5);
      _taperedBone(canvas, prev.chest, prev.frontElbow, gc, limbW * 0.7,
          0, a * smearA * t * 0.5);
      _taperedBone(canvas, prev.frontElbow, prev.frontHand, gc, limbW * 0.7,
          0, a * smearA * t * 0.5);
    }

    // Front leg smear.
    final legDist = (frame.frontFoot - prev.frontFoot).distance;
    if (legDist > 5.0) {
      final t = (legDist / 18.0).clamp(0.0, 1.0);
      final gc = _withAlpha(backGhost, smearA * t * 0.5);
      _taperedBone(canvas, prev.pelvis, prev.frontKnee, gc, limbW * 0.7,
          0, a * smearA * t * 0.5);
      _taperedBone(canvas, prev.frontKnee, prev.frontFoot, gc, limbW * 0.7,
          0, a * smearA * t * 0.5);
    }
  }

  // ── Torso with vertical gradient ────────────────────────────────────────────

  static void _drawTorso(Canvas canvas, StickFrame frame, StickStyle style,
      double torsoW, Color outline, double a) {
    // Shoulder nubs — small circles at chest for silhouette volume.
    final shoulderR = math.max(1.5, torsoW * 0.7);
    _fill.color = _withAlpha(style.fill, a * 0.75);
    canvas.drawCircle(frame.chest, shoulderR * 1.2, _fill);

    // Hip nubs.
    canvas.drawCircle(frame.pelvis, shoulderR * 0.95, _fill);

    if (style.gradientBottom > 0.01 && torsoW > 1) {
      final topColor = _withAlpha(style.fill, a);
      final botColor = _withAlpha(
          _dim(style.fill, style.gradientBottom.clamp(0.0, 1.0)), a);
      final shader = Gradient.linear(
        frame.chest,
        frame.pelvis,
        [topColor, botColor],
      );
      _drawTaperedBoneGradient(
          canvas, frame.pelvis, frame.chest, torsoW, shader);
    } else {
      _taperedBone(canvas, frame.pelvis, frame.chest, outline, torsoW,
          style.rimAlpha, a);
      return;
    }

    // Bright core stroke over gradient fill.
    _stroke
      ..color = outline
      ..strokeWidth = math.max(1.0, torsoW * 0.45)
      ..maskFilter = null;
    canvas.drawLine(frame.pelvis, frame.chest, _stroke);

    // Joint dots.
    _fill.color = outline;
    canvas.drawCircle(frame.pelvis, math.max(1.5, torsoW * 0.55), _fill);
    canvas.drawCircle(frame.chest, math.max(1.5, torsoW * 0.55), _fill);
  }

  // ── Torso rim light ──────────────────────────────────────────────────────────

  static void _drawTorsoRim(Canvas canvas, StickFrame frame, StickStyle style,
      double torsoW, double a) {
    if (style.rimAlpha <= 0.005) return;
    // Rim runs along the lit side (facing direction).
    final delta = frame.chest - frame.pelvis;
    final len = delta.distance;
    if (len < 1) return;
    final px = -delta.dy / len * torsoW * 0.28 * frame.facing;
    final py = delta.dx / len * torsoW * 0.28 * frame.facing;
    final rimCol = _lerp(style.outline, const Color(0xFFFFFFFF), 0.5)
        .withValues(alpha: (a * style.rimAlpha * 0.55).clamp(0.0, 1.0));
    _stroke
      ..color = rimCol
      ..strokeWidth = math.max(0.7, torsoW * 0.18)
      ..maskFilter = null;
    canvas.drawLine(
      Offset(frame.pelvis.dx + px, frame.pelvis.dy + py),
      Offset(frame.chest.dx + px, frame.chest.dy + py),
      _stroke,
    );
  }

  // ── Head ────────────────────────────────────────────────────────────────────

  static void _drawHead(Canvas canvas, StickFrame frame, StickStyle style,
      Color outline, double a) {
    final r = frame.headRadius;

    // Filled circle.
    _fill.color = _withAlpha(style.fill, a);
    canvas.drawCircle(frame.headCenter, r, _fill);

    // Neon ring.
    _stroke
      ..color = outline
      ..strokeWidth = math.max(1.5, frame.limbWidth * style.lineWidth * 0.65)
      ..maskFilter = null;
    canvas.drawCircle(frame.headCenter, r, _stroke);

    // Bright eye dot (facing side) — primary.
    final eye = frame.headCenter + Offset(frame.facing * r * 0.4, -r * 0.15);
    _fill.color = _withAlpha(style.outline, a);
    canvas.drawCircle(eye, math.max(1.2, r * 0.19), _fill);

    // Faint secondary dot slightly behind eye — makes direction pop.
    final brow = frame.headCenter + Offset(frame.facing * r * 0.18, -r * 0.38);
    _fill.color = _withAlpha(style.outline, a * 0.35);
    canvas.drawCircle(brow, math.max(0.7, r * 0.09), _fill);
  }

  // ── Per-style flourish ──────────────────────────────────────────────────────

  static void _drawFlourish(Canvas canvas, StickFrame frame, StickStyle style,
      Color outline, double limbW, double torsoW, double a) {
    // Boss: two shoulder spikes + small brow horn.
    // Shadow: two wispy foot trails.
    // Distinguish by checking outline color hue proxy (boss = magenta, shadow varies).
    // Simpler: use fill darkness + outline brightness ratio heuristic.
    // Actually: let callers handle via separate style fields in future. For now
    // we check glowSigma: boss ≥ 8, shadow = 6.
    if (style.glowSigma >= 8) {
      // Boss flourish — shoulder spikes.
      final spColor = _withAlpha(style.outline, a * 0.55);
      _stroke
        ..color = spColor
        ..strokeWidth = math.max(1.0, limbW * 0.55)
        ..maskFilter = null;
      // Left spike.
      canvas.drawLine(
        frame.chest,
        frame.chest + Offset(-frame.facing * torsoW * 0.8, -torsoW * 1.6),
        _stroke,
      );
      // Right spike.
      canvas.drawLine(
        frame.chest,
        frame.chest + Offset(frame.facing * torsoW * 1.6, -torsoW * 1.0),
        _stroke,
      );
      // Small brow ridge dot above head.
      _fill.color = _withAlpha(style.outline, a * 0.45);
      canvas.drawCircle(
        frame.headCenter + Offset(0, -(frame.headRadius + 2.5)),
        math.max(1.0, frame.headRadius * 0.22),
        _fill,
      );
    } else {
      // Shadow flourish — wisps near feet.
      final wispA = (a * 0.38).clamp(0.0, 1.0);
      _stroke
        ..color = _withAlpha(style.outline, wispA)
        ..strokeWidth = math.max(0.8, limbW * 0.4)
        ..maskFilter = null;
      final fy = math.max(frame.backFoot.dy, frame.frontFoot.dy);
      final cx = (frame.backFoot.dx + frame.frontFoot.dx) * 0.5;
      canvas.drawLine(
        Offset(cx - torsoW * 1.5, fy + 2),
        Offset(cx - torsoW * 3.0, fy + 6),
        _stroke,
      );
      canvas.drawLine(
        Offset(cx + torsoW * 0.8, fy + 1),
        Offset(cx + torsoW * 2.5, fy + 5),
        _stroke,
      );
    }
  }

  // ── Extremity accent (hand / foot oval) ─────────────────────────────────────

  static void _drawExtremity(
      Canvas canvas, Offset pos, Color color, double r) {
    if (r < 0.8) return;
    _fill.color = color;
    canvas.drawCircle(pos, r, _fill);
  }

  // ── Weapon motion-trail arc (no blur) ───────────────────────────────────────

  static void _drawWeaponTrail(Canvas canvas, StickFrame frame,
      StickFrame prev, WeaponVisual w, double a) {
    final hand = frame.frontHand;
    final prevHand = prev.frontHand;
    final dist = (hand - prevHand).distance;
    if (dist < 3.0 || w.length <= 0) return;

    final dir = Offset(math.cos(frame.aimAngle) * frame.facing,
        math.sin(frame.aimAngle));
    final prevDir = Offset(math.cos(prev.aimAngle) * prev.facing,
        math.sin(prev.aimAngle));

    final tip = hand + dir * w.length;
    final prevTip = prevHand + prevDir * w.length;

    final midBase = Offset.lerp(hand, prevHand, 0.5)!;
    final midTip = Offset.lerp(tip, prevTip, 0.5)!;

    // Reuse _trailPath (reset before use).
    _trailPath.reset();
    _trailPath
      ..moveTo(hand.dx, hand.dy)
      ..quadraticBezierTo(midBase.dx, midBase.dy, prevHand.dx, prevHand.dy)
      ..lineTo(prevTip.dx, prevTip.dy)
      ..quadraticBezierTo(midTip.dx, midTip.dy, tip.dx, tip.dy)
      ..close();

    // Translucent sweep fill — no blur (save the budget).
    _fill
      ..color = w.edge.withValues(alpha: (a * 0.22).clamp(0.0, 1.0))
      ..maskFilter = null;
    canvas.drawPath(_trailPath, _fill);

    // Faint stroke along tip arc.
    _stroke
      ..color = w.edge.withValues(alpha: (a * 0.16).clamp(0.0, 1.0))
      ..strokeWidth = 1.2
      ..maskFilter = null;
    _trailPath.reset();
    _trailPath
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(midTip.dx, midTip.dy, prevTip.dx, prevTip.dy);
    canvas.drawPath(_trailPath, _stroke);
  }

  // ── Tapered bone helpers ────────────────────────────────────────────────────

  /// Draws a bone as a tapered filled quad (thick at [a], thin at [b]) plus a
  /// bright inner highlight rim and round joint dots.
  static void _taperedBone(Canvas canvas, Offset a, Offset b, Color color,
      double w, double rimAlpha, double masterAlpha) {
    if ((b - a).distance < 0.5 || w < 0.5) return;

    _drawTaperedBoneColor(canvas, a, b, w, color);

    if (rimAlpha > 0.005) {
      final rimColor = _lerp(color, const Color(0xFFFFFFFF), 0.6 * rimAlpha.clamp(0.0, 1.0))
          .withValues(alpha: (color.a * rimAlpha).clamp(0.0, 1.0));
      _stroke
        ..color = rimColor
        ..strokeWidth = math.max(0.8, w * 0.22)
        ..maskFilter = null;
      canvas.drawLine(
        a + (b - a) * 0.15,
        a + (b - a) * 0.8,
        _stroke,
      );
    }

    _fill.color = color;
    canvas.drawCircle(a, math.max(1.0, w * 0.52), _fill);
    canvas.drawCircle(b, math.max(1.0, w * 0.34), _fill);
  }

  /// Tapered quad with a flat [Color] fill (no shader).
  static void _drawTaperedBoneColor(
      Canvas canvas, Offset a, Offset b, double w, Color color) {
    _buildTaperedQuad(a, b, w, w * 0.52);
    _fill.color = color;
    canvas.drawPath(_quadPath, _fill);
  }

  /// Tapered quad with a [Shader] fill (used for gradient torso).
  static void _drawTaperedBoneGradient(
      Canvas canvas, Offset a, Offset b, double w, Shader shader) {
    _buildTaperedQuad(a, b, w, w * 0.52);
    _fill.shader = shader;
    canvas.drawPath(_quadPath, _fill);
    _fill.shader = null;
  }

  /// Resets [_quadPath] and fills it as a tapered quad from [root] (width
  /// [rootW]) to [tip] (width [tipW]).  The result is in [_quadPath].
  static void _buildTaperedQuad(
      Offset root, Offset tip, double rootW, double tipW) {
    final delta = tip - root;
    final len = delta.distance;
    _quadPath.reset();
    if (len < 0.1) return;

    final px = -delta.dy / len;
    final py = delta.dx / len;
    final rh = rootW * 0.5;
    final th = tipW * 0.5;

    _quadPath
      ..moveTo(root.dx + px * rh, root.dy + py * rh)
      ..lineTo(tip.dx + px * th, tip.dy + py * th)
      ..lineTo(tip.dx - px * th, tip.dy - py * th)
      ..lineTo(root.dx - px * rh, root.dy - py * rh)
      ..close();
  }

  // ── Weapon rendering ─────────────────────────────────────────────────────────

  static void _weapon(Canvas c, StickFrame f, WeaponVisual w, double a) {
    final hand = f.frontHand;
    final dir = Offset(math.cos(f.aimAngle) * f.facing, math.sin(f.aimAngle));
    final tip = hand + dir * w.length;
    final col = _withAlpha(w.color, a);
    final edge = _withAlpha(w.edge, a);

    switch (w.shape) {
      case WeaponShape.none:
        return;
      case WeaponShape.greatsword:
      case WeaponShape.sword:
      case WeaponShape.twin:
        _blade(c, hand, tip, dir, w.width, col, edge);
        _tipSparkle(c, tip, edge, w.width * 0.55, a);
        break;
      case WeaponShape.dagger:
        final dTip = hand + dir * (w.length * 0.55);
        _blade(c, hand, dTip, dir, w.width, col, edge);
        _tipSparkle(c, dTip, edge, w.width * 0.45, a);
        break;
      case WeaponShape.spear:
        _shaft(c, hand, tip, w.width * 0.7, col);
        _fill.color = edge;
        c.drawCircle(tip, w.width * 0.9, _fill);
        _tipSparkle(c, tip, edge, w.width * 0.6, a);
        break;
      case WeaponShape.scythe:
        _shaft(c, hand, tip, w.width * 0.7, col);
        final perp = Offset(-dir.dy, dir.dx);
        _blade(c, tip, tip + perp * (w.length * 0.5), perp, w.width, col, edge);
        _tipSparkle(c, tip + perp * (w.length * 0.5), edge, w.width * 0.5, a);
        break;
      case WeaponShape.hammer:
        _shaft(c, hand, tip, w.width * 0.8, col);
        _stroke
          ..color = edge
          ..strokeWidth = w.width * 2.6
          ..maskFilter = null;
        c.drawLine(tip, tip + dir * 0.1, _stroke);
        break;
      case WeaponShape.gauntlet:
        _fill.color = edge;
        c.drawCircle(hand, w.width * 1.6, _fill);
        break;
      case WeaponShape.whip:
        // Reuse _trailPath for whip curve.
        _trailPath.reset();
        _trailPath.moveTo(hand.dx, hand.dy);
        final perp = Offset(-dir.dy, dir.dx);
        final mid = hand + dir * (w.length * 0.6) + perp * 6;
        _trailPath.quadraticBezierTo(mid.dx, mid.dy, tip.dx, tip.dy);
        _stroke
          ..color = col
          ..strokeWidth = w.width * 0.7
          ..maskFilter = null;
        c.drawPath(_trailPath, _stroke);
        break;
    }
  }

  /// Tiny sparkle circle at blade/spear tip.
  static void _tipSparkle(
      Canvas c, Offset tip, Color edge, double r, double a) {
    if (r < 0.5) return;
    _fill.color = _withAlpha(edge, a * 0.8);
    c.drawCircle(tip, r, _fill);
    _stroke
      ..color = _withAlpha(const Color(0xFFFFFFFF), a * 0.55)
      ..strokeWidth = math.max(0.5, r * 0.35)
      ..maskFilter = null;
    c.drawCircle(tip, r * 0.45, _stroke);
  }

  static void _shaft(Canvas c, Offset a, Offset b, double width, Color col) {
    _stroke
      ..color = col
      ..strokeWidth = width
      ..maskFilter = null;
    c.drawLine(a, b, _stroke);

    final delta = b - a;
    final len = delta.distance;
    if (len > 1 && width > 1.5) {
      final px = -delta.dy / len * width * 0.18;
      final py = delta.dx / len * width * 0.18;
      _stroke
        ..color = col.withValues(alpha: col.a * 0.55)
        ..strokeWidth = math.max(0.8, width * 0.3);
      c.drawLine(
        Offset(a.dx + px, a.dy + py),
        Offset(b.dx + px, b.dy + py),
        _stroke,
      );
    }
  }

  static void _blade(Canvas c, Offset base, Offset tip, Offset dir,
      double width, Color col, Color edge) {
    final perp = Offset(-dir.dy, dir.dx) * (width * 0.5);

    // Reuse _quadPath for blade triangle.
    _quadPath.reset();
    _quadPath
      ..moveTo(base.dx + perp.dx, base.dy + perp.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(base.dx - perp.dx, base.dy - perp.dy)
      ..close();

    _fill.color = col;
    c.drawPath(_quadPath, _fill);

    // Sharp edge highlight stroke.
    _stroke
      ..color = edge
      ..strokeWidth = 2.0
      ..maskFilter = null;
    c.drawPath(_quadPath, _stroke);

    // Inner bright spine — sharper than before (full alpha).
    _stroke
      ..color = edge.withValues(alpha: edge.a * 0.75)
      ..strokeWidth = 0.9;
    c.drawLine(
      base + (tip - base) * 0.12,
      tip,
      _stroke,
    );
  }
}
