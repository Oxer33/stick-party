import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Pure-Canvas rendering for [ReactionDuel] (QUICK-DRAW DUEL) — a samurai
/// standoff at dusk. Holds NO game state and never mutates the simulation:
/// callers pass plain value snapshots. Kept in its own file so the gameplay
/// module stays lean and the drawing stays cohesive (mirrors the sumo_smash /
/// tug_of_war split).
///
/// The signal states it paints are a LEARNABLE read — deliberately distinct so a
/// sharp player can tell fake from real at a glance: WAIT (red wash + "WAIT…"
/// halo), FEINT (a dim, jittery AMBER "FAKE?" bluff — never the GO-green, no
/// ping), and the real GO/DRAW (a SUSTAINED green flash + "GO!" punch + a rising
/// "ping" of expanding rings the feint never fires). On a clean winning tap it
/// also paints the VISIBLE REWARD: the reaction time (ms) + a "READ x2 ▲" streak.
/// Per player it draws a ready stance (with a breathing sway, owned by the game),
/// a gentle false-start mark, a draw-win pose, and the "first to N" draw tally.
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class ReactionRenderer {
  ReactionRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _skyTop = Color(0xFF1A1030); // deep dusk violet
  static const Color _skyMid = Color(0xFF59264A); // plum band
  static const Color _skyHot = Color(0xFFC8523A); // sunset ember
  static const Color _skyWarm = Color(0xFFE07A45); // warm sub-band (ember→haze)
  static const Color _skyHaze = Color(0xFFF2A65A); // low haze near horizon
  static const Color _sunCore = Color(0xFFFFE3A0);
  static const Color _sunEdge = Color(0xFFFF7A3C);
  static const Color _bambooDark = Color(0xFF120A1C);
  static const Color _bambooMid = Color(0xFF20122E);
  static const Color _groundTop = Color(0xFF241634);
  static const Color _groundBottom = Color(0xFF0B0712);
  static const Color _groundLine = Color(0x22FFFFFF);
  static const Color _vignette = Color(0xAA050208);
  static const Color _waitRed = Color(0xFFE23B3B);
  static const Color _waitDeep = Color(0xFF7A1414);
  static const Color _goGreen = Color(0xFF24D16A); // GO! word + halo (matches zone)
  static const Color _goGreenDeep = Color(0xFF12A653); // halo edge
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _tooSoon = Color(0xFFFF5466);

  // FEINT palette — the bluff is AMBER, never the GO-green. A dim, off-color,
  // jittery blip the player learns to read as "fake": no white core, no ping,
  // no full wash. Deliberately a different hue + shape from the real signal so
  // the read is learnable, not random.
  static const Color _feintAmber = Color(0xFFE6A23C); // bluff blip core
  static const Color _feintAmberDeep = Color(0xFF8A5A12); // bluff halo edge
  static const Color _streakGold = Color(0xFFFFE45C); // streak ▲ accent

  // ── Tuning (fractions; no inline magic numbers) ────────────────────────────
  static const double _horizonFrac = 0.46; // sky/ground split height
  static const double _sunCenterFrac = 0.355; // sun height (frac of height)
  static const double _sunRadiusFrac = 0.125; // sun radius / width
  static const int _groundLineCount = 5;
  static const int _bambooCount = 9;
  static const int _moteCount = 26; // drifting dust glints in the lit haze
  static const int _shimmerBands = 3; // heat/dust ripple bands near horizon
  static const double _bambooWidthFrac = 0.018; // stalk width / width
  static const double _vignInnerFrac = 0.46;
  static const double _vignOuterFrac = 0.78;

  // Center cue tuning.
  static const double _waitFontFrac = 0.085; // WAIT font / width
  static const double _strikeFontFrac = 0.135; // STRIKE font / width

  // Duelist marker tuning (fractions of body scale unit `u`).
  static const double _shadowWFactor = 2.6;
  static const double _shadowHFactor = 0.55;
  static const double _shadowReachFactor = 5.2; // long cast-shadow streak length
  static const double _readoutFontU = 0.6;

  // ── Background: dusk gradient sky + sinking sun + bamboo silhouettes ────────
  static void drawBackground(Canvas canvas, Size size, double t) {
    final horizon = size.height * _horizonFrac;

    // Vertical dusk gradient: violet → plum → ember → haze at the horizon, with
    // an extra warm sub-band so the ember→haze transition glows instead of
    // banding hard.
    final sky = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, horizon),
        const [_skyTop, _skyMid, _skyHot, _skyWarm, _skyHaze],
        const [0.0, 0.42, 0.74, 0.90, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, horizon), sky);

    _drawSun(canvas, size, horizon);
    _drawSunFlare(canvas, size, t);
    _drawDustMotes(canvas, size, horizon, t);
    _drawBamboo(canvas, size, horizon, t);
  }

  /// A soft anamorphic lens flare off the low sun: a faint horizontal streak
  /// plus a couple of drifting ghost discs along the sun→centre axis. Stacked
  /// translucent fills (no blur), gently breathing on the clock [t] so it reads
  /// as a living glare rather than a static decal.
  static void _drawSunFlare(Canvas canvas, Size size, double t) {
    final center = Offset(size.width * 0.5, size.height * _sunCenterFrac);
    final r = size.width * _sunRadiusFrac;
    if (r <= 1) return;
    final breathe = 0.85 + 0.15 * math.sin(t * 0.9);

    // Horizontal anamorphic streak through the sun — three stacked widths so it
    // tapers from a hot core to a soft glare.
    final streakHalf = size.width * 0.5;
    for (final layer in const [
      [1.0, 0.16, 0.018],
      [0.62, 0.22, 0.045],
      [0.30, 0.20, 0.10],
    ]) {
      final hw = streakHalf * layer[0];
      final hh = r * layer[2] * 6.0;
      canvas.drawRect(
        Rect.fromCenter(center: center, width: hw * 2, height: hh),
        Paint()
          ..shader = Gradient.linear(
            Offset(center.dx - hw, center.dy),
            Offset(center.dx + hw, center.dy),
            [
              const Color(0x00000000),
              _sunCore.withValues(alpha: layer[1] * breathe),
              const Color(0x00000000),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
    }

    // Ghost discs marching from the sun toward the frame centre.
    final axis = Offset(size.width * 0.5, size.height * 0.5) - center;
    for (final g in const [
      [0.55, 0.42, 0.10],
      [1.05, 0.26, 0.07],
      [1.55, 0.62, 0.05],
    ]) {
      final gc = center + axis * g[0];
      canvas.drawCircle(
        gc,
        r * g[1],
        Paint()
          ..shader = Gradient.radial(
            gc,
            r * g[1],
            [
              _sunCore.withValues(alpha: g[2] * breathe),
              const Color(0x00000000),
            ],
          ),
      );
    }
  }

  /// Slow warm dust-mote drift in the lit haze above the horizon — tiny glints
  /// that rise and fade, their positions a deterministic function of index and
  /// clock [t] (no Random/DateTime). Sells warm evening air without touching the
  /// signal layer.
  static void _drawDustMotes(
      Canvas canvas, Size size, double horizon, double t) {
    final glint = Paint();
    for (var i = 0; i < _moteCount; i++) {
      final fx = (i * 0.61803398875) % 1.0; // golden-ratio spread, stable
      final x = fx * size.width;
      // Each mote drifts upward on its own slow loop, wrapping 0..1.
      final phase = ((t * (0.018 + 0.012 * (i % 5) / 4) + i * 0.137) % 1.0);
      final y = horizon - phase * (size.height * 0.30);
      final wob = math.sin(t * 0.7 + i) * size.width * 0.004;
      // Fade in at the bottom, out at the top → soft twinkle.
      final fade = math.sin(phase * math.pi);
      final twinkle = 0.45 + 0.55 * math.sin(t * 2.0 + i * 1.7).abs();
      final a = 0.5 * fade * twinkle;
      if (a <= 0.01) continue;
      final rad = size.width * (0.0016 + 0.0014 * (i % 3) / 2);
      glint.color = _sunCore.withValues(alpha: a);
      canvas.drawCircle(Offset(x + wob, y), rad, glint);
    }
  }

  /// The sinking sun: a soft outer halo + a bright gradient disc resting on the
  /// haze line, anchored behind the bamboo.
  static void _drawSun(Canvas canvas, Size size, double horizon) {
    final center = Offset(size.width * 0.5, size.height * _sunCenterFrac);
    final r = size.width * _sunRadiusFrac;
    if (r <= 1) return;

    // Wide warm halo.
    canvas.drawCircle(
      center,
      r * 2.4,
      Paint()
        ..shader = Gradient.radial(
          center,
          r * 2.4,
          [
            _sunEdge.withValues(alpha: 0.34),
            const Color(0x00000000),
          ],
        ),
    );
    // Sun disc.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = Gradient.radial(
          center.translate(0, -r * 0.15),
          r,
          const [_sunCore, _sunEdge],
          const [0.0, 1.0],
        ),
    );
    // A couple of dark "atmosphere" bands across the disc for the classic
    // low-sun look.
    final band = Paint()
      ..color = _skyHot.withValues(alpha: 0.4)
      ..strokeWidth = r * 0.10
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx - r * 0.8, center.dy + r * 0.18),
        Offset(center.dx + r * 0.8, center.dy + r * 0.18), band);
    canvas.drawLine(Offset(center.dx - r * 0.6, center.dy + r * 0.5),
        Offset(center.dx + r * 0.6, center.dy + r * 0.5), band);
  }

  /// A row of bamboo stalk silhouettes swaying gently with the clock [t],
  /// fading from the horizon for depth.
  static void _drawBamboo(Canvas canvas, Size size, double horizon, double t) {
    final w = size.width * _bambooWidthFrac;
    final top = horizon - size.height * 0.34;
    for (var i = 0; i < _bambooCount; i++) {
      final f = (i + 0.5) / _bambooCount;
      final baseX = f * size.width;
      final sway = math.sin(t * 0.8 + i * 1.3) * w * 1.2;
      final far = (i.isEven) ? 0.0 : 1.0; // alternate two depth layers
      final color = Color.lerp(_bambooDark, _bambooMid, far)!
          .withValues(alpha: 0.85 - 0.25 * far);
      final stalk = Path()
        ..moveTo(baseX - w * 0.5, horizon)
        ..lineTo(baseX - w * 0.4 + sway, top)
        ..lineTo(baseX + w * 0.4 + sway, top)
        ..lineTo(baseX + w * 0.5, horizon)
        ..close();
      canvas.drawPath(stalk, Paint()..color = color);

      // Node ticks up the stalk.
      final node = Paint()
        ..color = _black.withValues(alpha: 0.35 * (1 - far))
        ..strokeWidth = w * 0.5
        ..strokeCap = StrokeCap.round;
      for (var k = 1; k <= 4; k++) {
        final ky = horizon - (horizon - top) * (k / 5);
        final kx = baseX + sway * (k / 5);
        canvas.drawLine(
            Offset(kx - w * 0.5, ky), Offset(kx + w * 0.5, ky), node);
      }
    }
  }

  /// The dueling ground: a warm-dark gradient slab with a few receding lines
  /// for perspective. Pass the clock [t] for a faint heat/dust shimmer banding
  /// near the horizon (default 0 = still, for callers that want a static slab).
  static void drawGround(Canvas canvas, Size size, [double t = 0]) {
    final top = size.height * _horizonFrac;
    final rect = Rect.fromLTWH(0, top, size.width, size.height - top);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(0, top),
          Offset(0, size.height),
          const [_groundTop, _groundBottom],
        ),
    );

    // Warm haze hugging the horizon — the lit air spilling down from the sky,
    // fading out before mid-field so the duelists stay crisp. A single radial
    // fill (no blur), drawn under the perspective lines.
    final hazeH = (size.height - top) * 0.34;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, hazeH),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, top),
          Offset(0, top + hazeH),
          [
            _skyHaze.withValues(alpha: 0.16),
            const Color(0x00000000),
          ],
        ),
    );

    final span = size.height - top;
    // Heat/dust shimmer: a couple of slow horizontal bright bands rippling just
    // above the horizon, their offset a deterministic function of the clock.
    final shimmer = Paint();
    for (var s = 0; s < _shimmerBands; s++) {
      final base = (s + 0.5) / _shimmerBands;
      final drift = math.sin(t * 0.6 + s * 2.1) * 0.04;
      final fr = (base * 0.5 + drift).clamp(0.02, 0.6);
      final y = top + span * fr * fr;
      final wave = 0.5 + 0.5 * math.sin(t * 1.3 + s * 1.7);
      shimmer.color = _skyHaze.withValues(alpha: 0.05 + 0.05 * wave);
      shimmer.strokeWidth = math.max(2.0, span * 0.02);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), shimmer);
    }

    final line = Paint()
      ..color = _groundLine
      ..strokeWidth = 1.5;
    for (var i = 1; i <= _groundLineCount; i++) {
      final fr = i / (_groundLineCount + 1);
      final y = top + span * fr * fr; // bunch toward the horizon
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// Crowd-dark vignette so the action pops (drawn over the field, under the
  /// figures). [pulse] in 0..1 tightens/reddens the frame for rising tension.
  static void drawVignette(Canvas canvas, Size size, double pulse) {
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final outer = diag * _vignOuterFrac;
    final inner = diag * _vignInnerFrac;
    final p = pulse.clamp(0.0, 1.0);
    final edge = Color.lerp(_vignette, const Color(0xCC2A0202), p) ?? _vignette;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.5),
          outer,
          [const Color(0x00000000), edge],
          [(inner / outer).clamp(0.0, 0.99), 1.0],
        ),
    );
  }

  /// Soft contact shadow beneath a duelist at ground level. [u] is the figure
  /// scale unit (≈ torso width). The low dusk sun (high and behind the field)
  /// rakes a long shadow forward toward the viewer: a tapering streak that fades
  /// out, capped by the crisp contact oval at the feet. Stacked translucent
  /// fills only (no per-frame blur).
  static void drawContactShadow(Canvas canvas, Offset feet, double u) {
    // Long cast streak: a quad from a narrow band at the feet to a wider, fully
    // faded far end pulled forward (down-screen) from the low sun behind.
    final reach = u * _shadowReachFactor;
    final nearHalf = u * _shadowWFactor * 0.42;
    final farHalf = u * _shadowWFactor * 0.62;
    final farY = feet.dy + reach;
    final streak = Path()
      ..moveTo(feet.dx - nearHalf, feet.dy)
      ..lineTo(feet.dx + nearHalf, feet.dy)
      ..lineTo(feet.dx + farHalf, farY)
      ..lineTo(feet.dx - farHalf, farY)
      ..close();
    canvas.drawPath(
      streak,
      Paint()
        ..shader = Gradient.linear(
          Offset(feet.dx, feet.dy),
          Offset(feet.dx, farY),
          [
            _black.withValues(alpha: 0.30),
            const Color(0x00000000),
          ],
        ),
    );
    // Crisp contact oval grounds the figure right at the feet.
    canvas.drawOval(
      Rect.fromCenter(
        center: feet,
        width: u * _shadowWFactor,
        height: u * _shadowHFactor,
      ),
      Paint()..color = _black.withValues(alpha: 0.30),
    );
  }

  /// A colored glowing footing ring under a duelist so each player's color reads
  /// in multi-player rounds. Dims when [locked] (false-started) this round. The
  /// [displayNumber] is accepted for API symmetry but kept off the field to keep
  /// the duel clean — identity reads from the player color.
  static void drawNamePlate(
    Canvas canvas,
    Offset feet,
    double u,
    Color color,
    int displayNumber, {
    required bool locked,
  }) {
    final a = locked ? 0.18 : 0.7;
    final rect = Rect.fromCenter(
      center: feet,
      width: u * (_shadowWFactor + 0.2),
      height: u * (_shadowHFactor + 0.15),
    );
    // Soft outer glow ring: a wide faint solid stroke under the crisp core ring
    // (no per-frame blur).
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(3.0, u * 0.3)
        ..color = color.withValues(alpha: a * 0.22),
    );
    // Crisp core ring.
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, u * 0.08)
        ..color = color.withValues(alpha: a),
    );
  }

  /// Per-player reaction readout above a duelist: their result this round
  /// (a slash-time in ms once they react). [waitBreath] in 0..1 is an OPTIONAL
  /// additive cue (default 0 = off, no behavior change): a faint breath puff
  /// drifting up from the duelist's mouth while they hold their nerve through
  /// WAIT. The mouth sits roughly one font-height below the readout anchor; the
  /// caller drives the value off its existing WAIT pulse so no new clock is
  /// needed. Purely visual — never affects the WAIT/feint/GO signal.
  static void drawReadout(
    Canvas canvas,
    Offset above,
    double u,
    String text,
    Color color, {
    double waitBreath = 0.0,
  }) {
    final breath = waitBreath.clamp(0.0, 1.0);
    if (breath > 0.01) {
      // Two small puffs rising from the mouth, the second trailing and fainter,
      // so it reads as a slow exhale. Position/size from [u] only; the pulse
      // value animates the rise + fade.
      final mouth = above.translate(0, u * _readoutFontU + u * 0.9);
      final rise = u * (0.5 + 1.3 * breath);
      for (final p in const [
        [0.0, 1.0, 0.55],
        [0.45, 0.7, 0.34],
      ]) {
        final puffY = mouth.dy - rise * (0.5 + p[0]);
        final pr = u * 0.28 * p[1] * (0.7 + 0.6 * breath);
        final pa = 0.28 * p[2] * (1.0 - breath); // fades as the exhale ages
        if (pa <= 0.01) continue;
        canvas.drawCircle(
          Offset(mouth.dx, puffY),
          pr,
          Paint()
            ..shader = Gradient.radial(
              Offset(mouth.dx, puffY),
              pr,
              [
                _white.withValues(alpha: pa),
                const Color(0x00000000),
              ],
            ),
        );
      }
    }
    if (text.isEmpty) return;
    _drawText(canvas, text, above, u * _readoutFontU, color,
        weight: FontWeight.w800, glow: true);
  }

  /// The big central state cue, placed at [centerFrac] of the height (default
  /// high in the sky so it reads as a title card clear of the duelists).
  /// [strikeFlash] in 0..1 drives the blinding STRIKE burst (brief); [strikeWord]
  /// in 0..1 punches in then fades the "STRIKE!" word so it clears the field for
  /// the KO. When [struck] is false it draws the calm red "WAIT…" pulse;
  /// [waitPulse] in 0..1 throbs it.
  ///
  /// THE LEARNABLE READ. [feint] (default false) marks a BLUFF — and the bluff is
  /// drawn DELIBERATELY DIFFERENT from the real GO so a sharp player can learn to
  /// tell them apart: a dim AMBER "FAKE" blip that jitters (driven by [jitter] in
  /// 0..1, a wobble phase off the game clock), with NO white-hot core, NO ping,
  /// NO green. The real GO is a punchy SUSTAINED green "GO!" with a white-hot
  /// shockwave. So "amber, shaky, brief = fake; green, bright, holds = real."
  static void drawCenterCue(
    Canvas canvas,
    Size size, {
    required bool struck,
    required double strikeFlash,
    required double waitPulse,
    double strikeWord = 1.0,
    double centerFrac = 0.5,
    bool feint = false,
    double jitter = 0.0,
  }) {
    final center = Offset(size.width / 2, size.height * centerFrac);
    if (feint) {
      _drawFeintCue(canvas, size, center, strikeFlash.clamp(0.0, 1.0),
          strikeWord.clamp(0.0, 1.0), jitter.clamp(0.0, 1.0));
    } else if (!struck) {
      _drawWaitCue(canvas, size, center, waitPulse.clamp(0.0, 1.0));
    } else {
      _drawStrikeCue(canvas, size, center, strikeFlash.clamp(0.0, 1.0),
          strikeWord.clamp(0.0, 1.0));
    }
  }

  /// The BLUFF cue — the fake-out a sharp player learns to ignore. AMBER (never
  /// the GO-green), dim, and visibly JITTERY: the word "FAKE" and its halo wobble
  /// by [jitter] so it reads as a nervous flicker, not the clean snap of the real
  /// signal. No white-hot core / shockwave / ping — those belong only to the real
  /// GO. [flash]/[word] fade it like the strike cue so the blip is brief.
  static void _drawFeintCue(Canvas canvas, Size size, Offset center,
      double flash, double word, double jitter) {
    // Nervous wobble: a small, fast shake whose amplitude scales with the blip's
    // own life so it twitches hardest at the peak.
    final amp = size.width * 0.012 * (0.4 + 0.6 * flash);
    final wob = Offset(
      math.sin(jitter * math.pi * 2 * 3) * amp,
      math.cos(jitter * math.pi * 2 * 5) * amp * 0.7,
    );
    final c = center + wob;
    if (flash > 0.01) {
      // A small, dim amber bloom — clearly smaller + cooler than the real GO's.
      final r = size.width * (0.16 + 0.05 * (1 - flash));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = Gradient.radial(
            c,
            r,
            [
              _feintAmber.withValues(alpha: 0.34 * flash),
              _feintAmberDeep.withValues(alpha: 0.16 * flash),
              const Color(0x00000000),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
      // A thin dashed-feel warning ring (broken into ticks) — a different SHAPE
      // from the real GO's clean solid shockwave, reinforcing "this is a fake".
      final ringR = size.width * 0.12;
      final tick = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, size.width * 0.006)
        ..color = _feintAmber.withValues(alpha: 0.55 * flash);
      const ticks = 8;
      for (var i = 0; i < ticks; i++) {
        final a0 = (i / ticks) * math.pi * 2 + jitter * 1.2;
        final a1 = a0 + math.pi / ticks; // half-on, half-off → dashed look
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: ringR),
          a0,
          a1 - a0,
          false,
          tick,
        );
      }
    }
    if (word <= 0.01) return;
    // The word is "FAKE" in amber — a hair smaller than the real GO and shaky, so
    // it never reads as the genuine signal even at a glance.
    final scale = 0.92 + 0.18 * (1 - word);
    _drawText(
      canvas,
      'FAKE',
      c,
      size.width * _strikeFontFrac * 0.62 * scale,
      _feintAmber.withValues(alpha: word),
      weight: FontWeight.w900,
      glow: true,
      glowColor: _feintAmberDeep.withValues(alpha: word),
    );
  }

  static void _drawWaitCue(
      Canvas canvas, Size size, Offset center, double pulse) {
    final r = size.width * 0.20 * (0.9 + 0.12 * pulse);
    // Soft red tension halo behind the word — a tight glowing badge.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = Gradient.radial(
          center,
          r,
          [
            _waitDeep.withValues(alpha: 0.4 + 0.16 * pulse),
            const Color(0x00000000),
          ],
        ),
    );
    // Ring that breathes with the pulse.
    canvas.drawCircle(
      center,
      size.width * 0.155 * (0.95 + 0.08 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, size.width * 0.007)
        ..color = _waitRed.withValues(alpha: 0.5 + 0.3 * pulse),
    );
    _drawText(
      canvas,
      'WAIT…',
      center,
      size.width * _waitFontFrac,
      _waitRed.withValues(alpha: 0.9 + 0.1 * pulse),
      weight: FontWeight.w900,
      glow: true,
    );
  }

  /// The REAL GO cue — always the punchy version (the feint takes a different
  /// path entirely). A tight green bloom + a white-hot shockwave + a blinding
  /// white core behind a big green "GO!" word. This is the snap the player learns
  /// to fire on.
  static void _drawStrikeCue(
      Canvas canvas, Size size, Offset center, double flash, double word) {
    if (flash > 0.01) {
      final r = size.width * (0.28 + 0.12 * (1 - flash));
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = Gradient.radial(
            center,
            r,
            [
              _goGreen.withValues(alpha: 0.6 * flash),
              _goGreenDeep.withValues(alpha: 0.28 * flash),
              const Color(0x00000000),
            ],
            const [0.0, 0.45, 1.0],
          ),
      );

      // A fast white-hot shockwave ring that expands and thins as the flash
      // decays — the "punch" that marks the genuine signal.
      final ringR = size.width * (0.16 + 0.34 * (1 - flash));
      canvas.drawCircle(
        center,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, size.width * 0.012 * flash)
          ..color = _white.withValues(alpha: 0.7 * flash),
      );
      // A tight inner white core bloom at the peak for the blinding kick.
      canvas.drawCircle(
        center,
        size.width * 0.10 * flash,
        Paint()
          ..shader = Gradient.radial(
            center,
            math.max(1.0, size.width * 0.10 * flash),
            [
              _white.withValues(alpha: 0.55 * flash),
              const Color(0x00000000),
            ],
          ),
      );
    }
    // The word punches in big then fades out (alpha + scale from `word`) so it
    // never lingers over the KO that follows. "GO!" in bright green reinforces
    // the per-zone green wash (the "tap now" signal).
    if (word <= 0.01) return;
    final scale = 1.0 + 0.55 * (1 - word);
    _drawText(
      canvas,
      'GO!',
      center,
      size.width * _strikeFontFrac * scale,
      _goGreen.withValues(alpha: word),
      weight: FontWeight.w900,
      glow: true,
      glowColor: _white.withValues(alpha: word),
    );
  }

  /// The RISING GO PING — concentric green rings that bloom outward from
  /// [center] on the real signal, a clean expanding pulse the FEINT never fires.
  /// [progress] in 0..1 drives the expansion (0 = just fired, 1 = faded out); two
  /// staggered rings give the "rising ping" read. Drawn screen-space over the GO
  /// flash. Pure + no-throw; a [progress] outside 0..1 is clamped.
  static void drawGoPing(Canvas canvas, Size size, double progress) {
    final p = progress.clamp(0.0, 1.0);
    if (p >= 1.0 || size.width <= 1) return;
    final center = Offset(size.width / 2, size.height * 0.5);
    final maxR = math.sqrt(size.width * size.width + size.height * size.height) *
        0.42;
    // Two rings, the second trailing the first, so the ping reads as a rising
    // double-pulse rather than a single ring.
    for (final lead in const [0.0, 0.28]) {
      final rp = (p - lead) / (1 - lead);
      if (rp <= 0 || rp >= 1) continue;
      final radius = maxR * _easeOut(rp);
      final fade = (1 - rp) * (1 - rp);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, size.width * 0.014 * fade)
          ..color = _goGreen.withValues(alpha: 0.7 * fade),
      );
      // A fainter white inner edge on the lead ring for a crisp "ping" rim.
      if (lead == 0.0) {
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, size.width * 0.005 * fade)
            ..color = _white.withValues(alpha: 0.5 * fade),
        );
      }
    }
  }

  /// THE VISIBLE REWARD for a sharp read: the winner's reaction time in big
  /// digits ("182 ms") plus, on a run, a streak badge ("READ x2 ▲"). Pops in then
  /// fades via [life] (1 → 0). Placed just under the center cue so it lands on the
  /// moment the read paid off. Screen-space, no-throw; an empty draw when
  /// [reactionMs] <= 0 or [life] <= 0.
  static void drawReadReward(
    Canvas canvas,
    Size size, {
    required int reactionMs,
    required int streak,
    required Color color,
    required double life,
    double centerFrac = 0.5,
  }) {
    final a = life.clamp(0.0, 1.0);
    if (a <= 0.01 || reactionMs <= 0 || size.width <= 1) return;
    // Rise + settle: drifts up a touch as it fades so it reads as an earned pop.
    final rise = size.height * 0.05 * (1 - a);
    final cy = size.height * centerFrac + size.width * 0.16 - rise;
    final cx = size.width / 2;

    // Reaction time — the proof the tap was fast.
    _drawText(
      canvas,
      '$reactionMs ms',
      Offset(cx, cy),
      size.width * 0.072,
      _white.withValues(alpha: a),
      weight: FontWeight.w900,
      glow: true,
      glowColor: color.withValues(alpha: a),
    );

    // Streak badge below it — the running tally a sharp player builds up.
    if (streak >= 2) {
      _drawText(
        canvas,
        'READ x$streak  ▲',
        Offset(cx, cy + size.width * 0.075),
        size.width * 0.05,
        _streakGold.withValues(alpha: a),
        weight: FontWeight.w900,
        glow: true,
        glowColor: _black.withValues(alpha: a),
      );
    }
  }

  /// Cheap ease-out (quadratic) for the ping expansion. Local helper so the
  /// renderer keeps its no-Flutter-widgets purity (no `package:flutter` Curves).
  static double _easeOut(double t) {
    final x = t.clamp(0.0, 1.0);
    return 1 - (1 - x) * (1 - x);
  }

  /// A lightning slash arc sweeping from [from] toward [to] (the loser), with a
  /// bright core, soft glow and a sparkle at the tip. [strength] 0..1 fades it.
  static void drawSlashArc(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color,
    double strength,
  ) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final delta = to - from;
    final len = delta.distance;
    if (len < 1) return;
    final n = delta / len;
    final perp = Offset(-n.dy, n.dx);
    // Bow the slash so it reads as an arc, not a straight line.
    final bow = perp * (len * 0.18);
    final mid = Offset.lerp(from, to, 0.5)! + bow;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);

    // Soft outer glow: a wide faint solid stroke under the white-hot core
    // (no per-frame blur).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (12 + 18 * s)
        ..color = color.withValues(alpha: 0.18 * s),
    );
    // White-hot core.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (2.5 + 5 * s)
        ..color = _white.withValues(alpha: 0.9 * s),
    );
    // Tip sparkle.
    canvas.drawCircle(
        to, (4 + 5 * s), Paint()..color = _white.withValues(alpha: 0.8 * s));
  }

  /// Speed lines radiating from the slasher to sell the burst of motion.
  static void drawSpeedLines(
    Canvas canvas,
    Offset origin,
    Offset toward,
    Color color,
    double strength,
  ) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final delta = toward - origin;
    final baseAngle = math.atan2(delta.dy, delta.dx);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.5 * s);
    const count = 6;
    for (var i = 0; i < count; i++) {
      final spread = (i - (count - 1) / 2) * 0.18;
      final a = baseAngle + spread;
      final dir = Offset(math.cos(a), math.sin(a));
      final inner = origin + dir * (18 + 10 * s);
      final outer = origin + dir * (60 + 70 * s);
      paint.strokeWidth = 2.0 + 2.0 * s;
      canvas.drawLine(inner, outer, paint);
    }
  }

  /// A gentle "X" over a false-starter (the soft "too early" gesture), fading as
  /// [strength] → 0. No text — the big per-zone "TOO EARLY!" word names it; this
  /// is just a soft visual mark so it never reads as harsh.
  static void drawEarlyX(Canvas canvas, Offset at, double u, double strength) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final half = u * 1.4;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, u * 0.18)
      ..color = _tooSoon.withValues(alpha: 0.7 * s);
    canvas.drawLine(
        at.translate(-half, -half), at.translate(half, half), paint);
    canvas.drawLine(
        at.translate(half, -half), at.translate(-half, half), paint);
  }

  /// Wash a whole player zone with its signal [color] at [alpha] — the dominant
  /// RED-wait / GREEN-go cue. A rounded fill with a slightly brighter inner rim
  /// so the colored ground reads clearly under the figures.
  static void drawZoneWash(Canvas canvas, Rect rect, Color color, double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    if (a <= 0.01 || rect.width <= 1 || rect.height <= 1) return;
    final pad = math.min(rect.width, rect.height) * 0.04;
    final r = rect.deflate(pad);
    final radius = Radius.circular(math.min(r.width, r.height) * 0.06);
    final rr = RRect.fromRectAndRadius(r, radius);
    canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: a));
    // Brighter rim so each zone reads as its own lit panel.
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, math.min(r.width, r.height) * 0.012)
        ..color = (Color.lerp(color, _white, 0.4) ?? color)
            .withValues(alpha: (a + 0.2).clamp(0.0, 1.0)),
    );
  }

  /// A big readable word centered in a player [rect], rotated by
  /// [rotationQuarters] quarter-turns so it faces that seat (top-edge players
  /// read it upside-up). Sits near the top of the zone so it never hides the
  /// figure. [color] is the text color (always glows for contrast).
  static void drawZoneLabel(
    Canvas canvas,
    Rect rect,
    String text,
    Color color,
    int rotationQuarters,
  ) {
    if (text.isEmpty || rect.width <= 1 || rect.height <= 1) return;
    final font = math.min(rect.width, rect.height) * 0.16;
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate((rotationQuarters % 4) * math.pi / 2);
    // Place the word toward the upper part of the (rotated) zone.
    final up = -rect.height * 0.26;
    _drawText(canvas, text, Offset(0, up), font, color,
        weight: FontWeight.w900, glow: true, glowColor: _black);
    canvas.restore();
  }

  /// The "FIRST TO N" draw-tally HUD: a compact title plus one short row per
  /// duelist, each row a player-color dot followed by [target] pips — filled
  /// (won) in [onColor], hollow for the rest. So the objective ("first to N
  /// draws") and the live standings read at a glance, and a duelist who is one
  /// pip from the target is obvious. Centered along the top, screen-space, sized
  /// off the arena so it stays readable for 1–4 players. No-throw; an empty
  /// [rows] or non-positive [target] draws nothing.
  static void drawDrawTally(
    Canvas canvas,
    Size size, {
    required List<DrawTallyRow> rows,
    required int target,
    Color onColor = const Color(0xFFFFE45C),
  }) {
    if (rows.isEmpty || target <= 0 || size.width <= 1) return;

    final pip = math.max(3.0, size.width * 0.013); // pip radius
    final pipGap = pip * 2.6; // pip center spacing
    final dot = pip * 1.15; // player-color dot radius
    final dotGap = dot * 2.2; // gap from dot to first pip
    final rowH = pip * 3.0; // vertical row pitch
    final titleSize = math.max(9.0, size.width * 0.026);

    // Width of one row = color dot + the run of pips. Center the block.
    final rowW = dotGap + pipGap * (target - 1) + pip * 2;
    final cx = size.width / 2;
    final left = cx - rowW / 2;

    // "FIRST TO N" title above the rows.
    final topY = size.height * 0.045;
    _drawText(canvas, 'FIRST TO $target', Offset(cx, topY), titleSize,
        _white.withValues(alpha: 0.92),
        weight: FontWeight.w900, glow: true, glowColor: _black);

    var rowY = topY + titleSize * 0.9 + rowH * 0.5;
    for (final row in rows) {
      // Player-color dot anchoring the row.
      canvas.drawCircle(
          Offset(left + dot, rowY), dot, Paint()..color = row.color);
      canvas.drawCircle(
        Offset(left + dot, rowY),
        dot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, dot * 0.22)
          ..color = _white.withValues(alpha: 0.6),
      );

      final won = row.won.clamp(0, target);
      for (var i = 0; i < target; i++) {
        final px = left + dot + dotGap + pipGap * i;
        final center = Offset(px, rowY);
        if (i < won) {
          canvas.drawCircle(center, pip, Paint()..color = onColor);
          canvas.drawCircle(
            center,
            pip,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.0, pip * 0.3)
              ..color = _white.withValues(alpha: 0.85),
          );
        } else {
          canvas.drawCircle(
            center,
            pip,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.0, pip * 0.3)
              ..color = _white.withValues(alpha: 0.38),
          );
        }
      }
      rowY += rowH;
    }
  }

  /// A full-screen white screen-flash overlay. [a] in 0..1 is the opacity.
  static void drawScreenFlash(Canvas canvas, Size size, double a) {
    final v = a.clamp(0.0, 1.0);
    if (v <= 0.01) return;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = _white.withValues(alpha: v));
  }

  /// A persistent golden edge-wash that marks the LIGHTNING (double-points)
  /// final round, so the climax reads at a glance for the whole round. [cuePeak]
  /// (1 → 0) adds a brief brighter bloom right at the round start; [pulse] (0..1)
  /// gently breathes the resting tint. A radial gradient (no blur) keeps the
  /// centre clear so the action stays legible.
  static void drawLightningAmbience(
    Canvas canvas,
    Size size,
    double cuePeak,
    double pulse, {
    Color gold = const Color(0xFFFFE45C),
  }) {
    final peak = cuePeak.clamp(0.0, 1.0);
    final breathe = 0.5 + 0.5 * pulse.clamp(0.0, 1.0);
    final edgeAlpha = (0.10 + 0.06 * breathe + 0.30 * peak).clamp(0.0, 1.0);
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.45),
          diag * 0.62,
          [const Color(0x00000000), gold.withValues(alpha: edgeAlpha)],
          const [0.45, 1.0],
        ),
    );
  }

  /// Render the stick duelist itself. Kept here so the painter call lives with
  /// the rest of the visuals; [figure] owns its own pose/ragdoll state.
  static void drawDuelist(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  /// Centered text with an optional cheap glow halo (offset copies). Never
  /// throws; degenerate sizes are ignored.
  static void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w800,
    bool glow = false,
    Color? glowColor,
  }) {
    if (fontSize <= 0 || text.isEmpty) return;
    final width = fontSize * (text.length + 2);
    if (glow) {
      final gb = ParagraphBuilder(ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: fontSize,
        fontWeight: weight,
      ))
        ..pushStyle(
            TextStyle(color: (glowColor ?? color).withValues(alpha: 0.5)))
        ..addText(text);
      final gp = gb.build()..layout(ParagraphConstraints(width: width));
      for (final o in const [
        Offset(0, 2.5),
        Offset(2.5, 0),
        Offset(-2.5, 0),
        Offset(0, -2.5),
      ]) {
        canvas.drawParagraph(gp,
            Offset(center.dx - width / 2 + o.dx, center.dy - fontSize + o.dy));
      }
    }
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: weight,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: width));
    canvas.drawParagraph(
        paragraph, Offset(center.dx - width / 2, center.dy - fontSize));
  }
}

/// One row of the "first to N" draw tally: a duelist's [color] and how many
/// draws they have [won] so far. A plain value snapshot the game hands to
/// [ReactionRenderer.drawDrawTally] (no game state leaks into the renderer).
class DrawTallyRow {
  final Color color;
  final int won;
  const DrawTallyRow({required this.color, required this.won});
}
