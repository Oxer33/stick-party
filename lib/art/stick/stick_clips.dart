import '../../core/math2.dart';
import 'stick_pose.dart';

/// A single keyframe: a [pose] sampled at time [t] (seconds) along the clip.
class StickKeyframe {
  final double t;
  final StickPose pose;
  const StickKeyframe(this.t, this.pose);
}

/// A keyframed animation clip. [loop] clips wrap on [duration]; one-shot clips
/// hold the last frame when sampled past the end.
class StickClip {
  final String name;
  final double duration;
  final bool loop;
  final List<StickKeyframe> frames;

  const StickClip(this.name, this.duration, this.frames, {this.loop = false});

  /// Sample the pose at [time] (seconds). Interpolates between bracketing
  /// keyframes with smooth easing.
  StickPose sample(double time) {
    if (frames.isEmpty) return StickPose.rest;
    if (frames.length == 1) return frames.first.pose;
    var t = time;
    if (loop) {
      t = duration <= 0 ? 0 : time % duration;
    } else if (t >= duration) {
      return frames.last.pose;
    }
    for (var i = 0; i < frames.length - 1; i++) {
      final a = frames[i];
      final b = frames[i + 1];
      if (t >= a.t && t <= b.t) {
        final span = b.t - a.t;
        final local = span <= 0 ? 0.0 : (t - a.t) / span;
        return a.pose.lerp(b.pose, easeInOut(local));
      }
    }
    return frames.last.pose;
  }
}

/// Library of procedurally-authored clips. Built once at load.
class StickClips {
  StickClips._();

  static final StickPose _rest = StickPose.rest;

  // ---- Locomotion -----------------------------------------------------------

  /// Idle: breathing cycle with weapon-arm micro-sway and a subtle weight shift.
  /// Three layers: slow chest rise, front-arm weapon sway, gentle hip micro-lean.
  static final StickClip idle = StickClip(
    'idle',
    3.0,
    [
      // Start: standing tall, slight forward guard
      StickKeyframe(
        0.0,
        _rest.copyWith(
          rootDy: 0,
          spine: rad(-90),
          neck: rad(-91),
          armFrontUpper: rad(76),
          armFrontFore: rad(80),
          armBackUpper: rad(102),
          armBackFore: rad(108),
          legFrontThigh: rad(83),
          legFrontShin: rad(90),
          legBackThigh: rad(97),
          legBackShin: rad(92),
        ),
      ),
      // Inhale: chest rises, spine extends, front arm drifts up (weapon sway)
      StickKeyframe(
        0.7,
        _rest.copyWith(
          rootDy: -2.0,
          spine: rad(-93),
          neck: rad(-95),
          armFrontUpper: rad(68),
          armFrontFore: rad(72),
          armBackUpper: rad(106),
          armBackFore: rad(112),
          legFrontThigh: rad(82),
          legFrontShin: rad(89),
        ),
      ),
      // Inhale peak: maximum breath, weight shifts subtly onto front foot
      StickKeyframe(
        1.2,
        _rest.copyWith(
          rootDy: -2.5,
          spine: rad(-94),
          neck: rad(-96),
          armFrontUpper: rad(65),
          armFrontFore: rad(68),
          armBackUpper: rad(108),
          armBackFore: rad(115),
          legFrontThigh: rad(80),
          legFrontShin: rad(88),
          legBackThigh: rad(100),
          legBackShin: rad(93),
        ),
      ),
      // Exhale: body settles, slight forward lean, arms drop with gravity
      StickKeyframe(
        2.0,
        _rest.copyWith(
          rootDy: 3.0,
          spine: rad(-88),
          neck: rad(-87),
          armFrontUpper: rad(82),
          armFrontFore: rad(88),
          armBackUpper: rad(100),
          armBackFore: rad(106),
          legFrontThigh: rad(84),
          legFrontShin: rad(91),
        ),
      ),
      // Exhale dip: deepest settle, micro weight-shift to back foot
      StickKeyframe(
        2.4,
        _rest.copyWith(
          rootDy: 3.5,
          spine: rad(-87),
          neck: rad(-86),
          armFrontUpper: rad(84),
          armFrontFore: rad(90),
          armBackUpper: rad(99),
          armBackFore: rad(105),
          legFrontThigh: rad(85),
          legFrontShin: rad(92),
          legBackThigh: rad(95),
          legBackShin: rad(91),
        ),
      ),
      // Return to start
      StickKeyframe(
        3.0,
        _rest.copyWith(
          rootDy: 0,
          spine: rad(-90),
          neck: rad(-91),
          armFrontUpper: rad(76),
          armFrontFore: rad(80),
          armBackUpper: rad(102),
          armBackFore: rad(108),
          legFrontThigh: rad(83),
          legFrontShin: rad(90),
          legBackThigh: rad(97),
          legBackShin: rad(92),
        ),
      ),
    ],
    loop: true,
  );

  /// Idle variant A: weight-shift + weapon micro-raise.
  /// Different rhythm from base idle — avoids freeze during long wait.
  static final StickClip idleVariant = StickClip(
    'idleVariant',
    3.8,
    [
      StickKeyframe(
        0.0,
        _rest.copyWith(
          rootDy: 0,
          spine: rad(-90),
          neck: rad(-90),
          armFrontUpper: rad(76),
          armFrontFore: rad(83),
          legFrontThigh: rad(83),
          legFrontShin: rad(90),
          legBackThigh: rad(97),
          legBackShin: rad(92),
        ),
      ),
      // Weight shifts to front leg — hip tilts, spine compensates
      StickKeyframe(
        0.8,
        _rest.copyWith(
          rootDy: 2.0,
          spine: rad(-88),
          neck: rad(-87),
          armFrontUpper: rad(74),
          armFrontFore: rad(68),
          legFrontThigh: rad(79),
          legFrontShin: rad(87),
          legBackThigh: rad(102),
          legBackShin: rad(96),
        ),
      ),
      // Weapon micro-raise — front arm lifts as if checking grip
      StickKeyframe(
        1.6,
        _rest.copyWith(
          rootDy: -1.5,
          spine: rad(-93),
          neck: rad(-95),
          armFrontUpper: rad(54),
          armFrontFore: rad(46),
          armBackUpper: rad(114),
          armBackFore: rad(120),
          legFrontThigh: rad(82),
          legFrontShin: rad(89),
        ),
      ),
      // Weapon lowers back, body settles
      StickKeyframe(
        2.6,
        _rest.copyWith(
          rootDy: 2.5,
          spine: rad(-89),
          neck: rad(-88),
          armFrontUpper: rad(80),
          armFrontFore: rad(86),
          armBackUpper: rad(100),
          armBackFore: rad(107),
        ),
      ),
      StickKeyframe(
        3.8,
        _rest.copyWith(
          rootDy: 0,
          spine: rad(-90),
          neck: rad(-90),
          armFrontUpper: rad(76),
          armFrontFore: rad(83),
          legFrontThigh: rad(83),
          legFrontShin: rad(90),
          legBackThigh: rad(97),
          legBackShin: rad(92),
        ),
      ),
    ],
    loop: true,
  );

  /// Idle variant B: nervous combat readiness — quick weight shuffle, head scan.
  /// Faster, more tense rhythm for combat-active states.
  static final StickClip idleVariantB = StickClip(
    'idleVariantB',
    2.2,
    [
      StickKeyframe(
        0.0,
        _rest.copyWith(
          rootDy: 0,
          spine: rad(-91),
          neck: rad(-89),
          armFrontUpper: rad(72),
          armFrontFore: rad(66),
          armBackUpper: rad(104),
          armBackFore: rad(110),
          legFrontThigh: rad(82),
          legFrontShin: rad(88),
          legBackThigh: rad(98),
          legBackShin: rad(94),
        ),
      ),
      // Quick step in place — back foot lifts slightly
      StickKeyframe(
        0.25,
        _rest.copyWith(
          rootDy: -1.5,
          spine: rad(-92),
          neck: rad(-86),  // head turns slightly (scan)
          armFrontUpper: rad(68),
          armFrontFore: rad(62),
          legBackThigh: rad(94),
          legBackShin: rad(86),
        ),
      ),
      // Plant back foot, weight rocks forward
      StickKeyframe(
        0.55,
        _rest.copyWith(
          rootDy: 2.5,
          spine: rad(-89),
          neck: rad(-92),
          armFrontUpper: rad(74),
          armFrontFore: rad(70),
          legFrontThigh: rad(79),
          legFrontShin: rad(86),
          legBackThigh: rad(100),
          legBackShin: rad(95),
        ),
      ),
      // Quick step other side
      StickKeyframe(
        0.85,
        _rest.copyWith(
          rootDy: -1.0,
          spine: rad(-92),
          neck: rad(-94),
          armFrontUpper: rad(70),
          armFrontFore: rad(64),
          legFrontThigh: rad(81),
          legFrontShin: rad(87),
        ),
      ),
      // Settle with slight forward lean — ready stance
      StickKeyframe(
        1.5,
        _rest.copyWith(
          rootDy: 1.5,
          spine: rad(-88),
          neck: rad(-90),
          armFrontUpper: rad(72),
          armFrontFore: rad(66),
          legFrontThigh: rad(82),
          legFrontShin: rad(88),
          legBackThigh: rad(98),
          legBackShin: rad(94),
        ),
      ),
      StickKeyframe(
        2.2,
        _rest.copyWith(
          rootDy: 0,
          spine: rad(-91),
          neck: rad(-89),
          armFrontUpper: rad(72),
          armFrontFore: rad(66),
          armBackUpper: rad(104),
          armBackFore: rad(110),
          legFrontThigh: rad(82),
          legFrontShin: rad(88),
          legBackThigh: rad(98),
          legBackShin: rad(94),
        ),
      ),
    ],
    loop: true,
  );

  /// Run: strong push-off → airborne float → heel-strike. Weight reads clearly.
  /// 5-frame cycle: push-off peak → float → heel-strike → ground → push-off.
  static final StickClip run = StickClip(
    'run',
    0.48,
    [
      // Push-off (0): rear leg drives hard, front leg swings forward. Body leans.
      // Arms in full counter-pump. TOP of bounce — maximum height.
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-73),
          neck: rad(-76),
          legFrontThigh: rad(112),   // rear leg extending back (push phase)
          legFrontShin: rad(145),    // shin trails — follow-through
          legBackThigh: rad(50),     // swing leg forward high
          legBackShin: rad(58),      // knee bent, foot coming through
          armFrontUpper: rad(36),    // front arm punches fwd-up
          armFrontFore: rad(25),
          armBackUpper: rad(135),    // back arm drives back-down
          armBackFore: rad(160),
          rootDy: -6,                // airborne peak
        ),
      ),
      // Float (0.10): brief airborne suspension — limbs at extremes
      StickKeyframe(
        0.10,
        _rest.copyWith(
          spine: rad(-75),
          neck: rad(-78),
          legFrontThigh: rad(105),
          legFrontShin: rad(130),
          legBackThigh: rad(55),
          legBackShin: rad(62),
          armFrontUpper: rad(40),
          armFrontFore: rad(30),
          armBackUpper: rad(130),
          armBackFore: rad(155),
          rootDy: -4,                // still airborne
        ),
      ),
      // Heel-strike (0.18): leading foot contacts ground, shock absorption begins.
      // Arms cross neutral, body pitches slightly forward on landing.
      StickKeyframe(
        0.18,
        _rest.copyWith(
          spine: rad(-76),
          neck: rad(-79),
          legFrontThigh: rad(68),    // heel-striking leg — thigh forward
          legFrontShin: rad(85),     // shin nearly vertical at strike
          legBackThigh: rad(102),    // push leg coming back through
          legBackShin: rad(95),
          armFrontUpper: rad(88),    // arms at neutral crossing
          armFrontFore: rad(92),
          armBackUpper: rad(88),
          armBackFore: rad(98),
          rootDy: 0,
        ),
      ),
      // Ground contact (0.28): deepest compression — knee absorbs load, trunk sinks
      StickKeyframe(
        0.28,
        _rest.copyWith(
          spine: rad(-78),
          neck: rad(-81),
          legFrontThigh: rad(75),    // stance leg under body
          legFrontShin: rad(95),     // knee bent — absorbing impact
          legBackThigh: rad(98),     // back leg recovering forward
          legBackShin: rad(90),
          armFrontUpper: rad(95),
          armFrontFore: rad(102),
          armBackUpper: rad(80),
          armBackFore: rad(88),
          rootDy: 4,                 // compressed — maximum ground contact
        ),
      ),
      // Mirror push-off (0.36): now right foot drives
      StickKeyframe(
        0.36,
        _rest.copyWith(
          spine: rad(-73),
          neck: rad(-76),
          legFrontThigh: rad(50),
          legFrontShin: rad(58),
          legBackThigh: rad(112),
          legBackShin: rad(145),
          armFrontUpper: rad(135),
          armFrontFore: rad(160),
          armBackUpper: rad(36),
          armBackFore: rad(25),
          rootDy: -6,
        ),
      ),
      // Mirror float (0.40)
      StickKeyframe(
        0.40,
        _rest.copyWith(
          spine: rad(-75),
          neck: rad(-78),
          legFrontThigh: rad(55),
          legFrontShin: rad(62),
          legBackThigh: rad(105),
          legBackShin: rad(130),
          armFrontUpper: rad(130),
          armFrontFore: rad(155),
          armBackUpper: rad(40),
          armBackFore: rad(30),
          rootDy: -4,
        ),
      ),
      // Loop close = frame 0
      StickKeyframe(
        0.48,
        _rest.copyWith(
          spine: rad(-73),
          neck: rad(-76),
          legFrontThigh: rad(112),
          legFrontShin: rad(145),
          legBackThigh: rad(50),
          legBackShin: rad(58),
          armFrontUpper: rad(36),
          armFrontFore: rad(25),
          armBackUpper: rad(135),
          armBackFore: rad(160),
          rootDy: -6,
        ),
      ),
    ],
    loop: true,
  );

  /// Run-fast / sprint: near-horizontal lean, tight arm-pump, short cycle.
  static final StickClip runFast = StickClip(
    'runFast',
    0.34,
    [
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-62),
          neck: rad(-65),
          legFrontThigh: rad(108),
          legFrontShin: rad(155),
          legBackThigh: rad(44),
          legBackShin: rad(52),
          armFrontUpper: rad(26),
          armFrontFore: rad(12),
          armBackUpper: rad(144),
          armBackFore: rad(168),
          rootDy: -8,
        ),
      ),
      StickKeyframe(
        0.08,
        _rest.copyWith(
          spine: rad(-64),
          neck: rad(-67),
          legFrontThigh: rad(86),
          legFrontShin: rad(92),
          legBackThigh: rad(90),
          legBackShin: rad(88),
          armFrontUpper: rad(88),
          armFrontFore: rad(94),
          armBackUpper: rad(90),
          armBackFore: rad(96),
          rootDy: 5,
        ),
      ),
      StickKeyframe(
        0.17,
        _rest.copyWith(
          spine: rad(-62),
          neck: rad(-65),
          legFrontThigh: rad(44),
          legFrontShin: rad(52),
          legBackThigh: rad(108),
          legBackShin: rad(155),
          armFrontUpper: rad(144),
          armFrontFore: rad(168),
          armBackUpper: rad(26),
          armBackFore: rad(12),
          rootDy: -8,
        ),
      ),
      StickKeyframe(
        0.25,
        _rest.copyWith(
          spine: rad(-64),
          neck: rad(-67),
          legFrontThigh: rad(90),
          legFrontShin: rad(88),
          legBackThigh: rad(86),
          legBackShin: rad(92),
          armFrontUpper: rad(90),
          armFrontFore: rad(96),
          armBackUpper: rad(88),
          armBackFore: rad(94),
          rootDy: 5,
        ),
      ),
      StickKeyframe(
        0.34,
        _rest.copyWith(
          spine: rad(-62),
          neck: rad(-65),
          legFrontThigh: rad(108),
          legFrontShin: rad(155),
          legBackThigh: rad(44),
          legBackShin: rad(52),
          armFrontUpper: rad(26),
          armFrontFore: rad(12),
          armBackUpper: rad(144),
          armBackFore: rad(168),
          rootDy: -8,
        ),
      ),
    ],
    loop: true,
  );

  /// Jump (ascending): anticipation squat → explosive launch → air tuck.
  static final StickClip jump = StickClip(
    'jump',
    0.40,
    [
      // Pre-jump anticipation squat — deep bend, arms drop to load
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-80),
          neck: rad(-82),
          legFrontThigh: rad(68),    // knees bent deep
          legFrontShin: rad(122),
          legBackThigh: rad(106),
          legBackShin: rad(130),
          armFrontUpper: rad(62),    // arms swing down to load
          armFrontFore: rad(75),
          armBackUpper: rad(112),
          armBackFore: rad(122),
          rootDy: 10,                // squash — body low
        ),
      ),
      // Maximum squat: deepest point of anticipation
      StickKeyframe(
        0.08,
        _rest.copyWith(
          spine: rad(-78),
          neck: rad(-80),
          legFrontThigh: rad(62),
          legFrontShin: rad(130),
          legBackThigh: rad(112),
          legBackShin: rad(138),
          armFrontUpper: rad(70),
          armFrontFore: rad(82),
          armBackUpper: rad(108),
          armBackFore: rad(118),
          rootDy: 13,
        ),
      ),
      // Launch burst: legs fire, arms punch upward, spine stretches
      StickKeyframe(
        0.16,
        _rest.copyWith(
          spine: rad(-96),
          neck: rad(-100),
          legFrontThigh: rad(80),    // legs extending rapidly
          legFrontShin: rad(88),
          legBackThigh: rad(88),
          legBackShin: rad(86),
          armFrontUpper: rad(-58),   // arms fly upward
          armFrontFore: rad(-48),
          armBackUpper: rad(-72),
          armBackFore: rad(-58),
          rootDy: -8,                // stretch — body launches up
        ),
      ),
      // Air tuck: knees pull to chest, body compact for height
      StickKeyframe(
        0.40,
        _rest.copyWith(
          spine: rad(-87),
          neck: rad(-90),
          legFrontThigh: rad(52),    // knees pulled up
          legFrontShin: rad(32),
          legBackThigh: rad(62),
          legBackShin: rad(38),
          armFrontUpper: rad(-52),
          armFrontFore: rad(-40),
          armBackUpper: rad(-65),
          armBackFore: rad(-50),
          rootDy: -5,
        ),
      ),
    ],
  );

  /// Fall (descending): arms flare, legs reach for ground, head looks down.
  static final StickClip fall = StickClip(
    'fall',
    0.32,
    [
      // Initial fall: arms flung wide, legs starting to extend
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-85),
          neck: rad(-78),
          legFrontThigh: rad(80),
          legFrontShin: rad(92),
          legBackThigh: rad(95),
          legBackShin: rad(110),
          armFrontUpper: rad(12),    // arms wide for balance
          armFrontFore: rad(-8),
          armBackUpper: rad(170),
          armBackFore: rad(180),
          rootDy: -2,
        ),
      ),
      // Terminal fall: legs fully extend reaching for ground
      StickKeyframe(
        0.32,
        _rest.copyWith(
          spine: rad(-82),
          neck: rad(-75),            // head tilts — looking down at ground
          legFrontThigh: rad(74),
          legFrontShin: rad(108),
          legBackThigh: rad(100),
          legBackShin: rad(114),
          armFrontUpper: rad(20),
          armFrontFore: rad(2),
          armBackUpper: rad(164),
          armBackFore: rad(176),
          rootDy: 2,
        ),
      ),
    ],
  );

  /// Land (squash-stretch): violent impact absorption → overshoot spring → settle.
  static final StickClip land = StickClip(
    'land',
    0.32,
    [
      // Impact squash: maximum compression. Knees near 90°, trunk pitches fwd.
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-73),
          neck: rad(-70),
          legFrontThigh: rad(60),
          legFrontShin: rad(128),    // deep knee bend
          legBackThigh: rad(120),
          legBackShin: rad(78),
          armFrontUpper: rad(52),    // arms thrown back as counterweight
          armFrontFore: rad(65),
          armBackUpper: rad(128),
          armBackFore: rad(142),
          rootDy: 14,                // maximum squash
        ),
      ),
      // Rebound: legs push off ground slightly, body springs upward
      StickKeyframe(
        0.12,
        _rest.copyWith(
          spine: rad(-88),
          neck: rad(-92),
          legFrontThigh: rad(76),
          legFrontShin: rad(100),
          legBackThigh: rad(100),
          legBackShin: rad(88),
          armFrontUpper: rad(68),
          armFrontFore: rad(75),
          armBackUpper: rad(110),
          armBackFore: rad(118),
          rootDy: 2,
        ),
      ),
      // Overshoot spring: tiny upward bounce past neutral
      StickKeyframe(
        0.20,
        _rest.copyWith(
          spine: rad(-95),
          neck: rad(-98),
          legFrontThigh: rad(84),
          legFrontShin: rad(90),
          legBackThigh: rad(94),
          legBackShin: rad(88),
          armFrontUpper: rad(74),
          armFrontFore: rad(80),
          armBackUpper: rad(104),
          armBackFore: rad(110),
          rootDy: -4,                // stretch — slight upward overshoot
        ),
      ),
      // Settle: return to ready stance
      StickKeyframe(0.32, _rest),
    ],
  );

  // ---- Upper-body actions (layered over locomotion) -------------------------

  /// Build an upper-body-only pose (leaves legs/rootDy at rest values).
  static StickPose _upper({
    required double spine,
    required double neck,
    required double fU,
    required double fF,
    required double bU,
    required double bF,
  }) =>
      _rest.copyWith(
        spine: spine,
        neck: neck,
        armFrontUpper: fU,
        armFrontFore: fF,
        armBackUpper: bU,
        armBackFore: bF,
      );

  /// Attack 1 — horizontal slash (right-to-left arc, dominant arm leads):
  /// long anticipation → explosive whip → overshoot → crisp recovery.
  static final StickClip attack1 = StickClip(
    'attack1',
    0.38,
    [
      // Pre-coil: body turns away, weapon arm pulled back high, off-arm balances
      StickKeyframe(
        0.0,
        _upper(
          spine: rad(-102), neck: rad(-106),
          fU: rad(-48), fF: rad(-78),    // weapon arm swung back-and-up
          bU: rad(110), bF: rad(128),
        ),
      ),
      // Anticipation peak: deepest coil — held one beat to sell the tension
      StickKeyframe(
        0.09,
        _upper(
          spine: rad(-110), neck: rad(-116),
          fU: rad(-75), fF: rad(-105),   // maximum pull-back
          bU: rad(118), bF: rad(138),
        ),
      ),
      // STRIKE: body snaps forward, arm whips through hit zone — fastest frame
      StickKeyframe(
        0.19,
        _upper(
          spine: rad(-64), neck: rad(-70),
          fU: rad(65), fF: rad(48),      // arm at full extension through target
          bU: rad(148), bF: rad(115),
        ),
      ),
      // Overshoot: momentum carries arm past — torso overshoots forward
      StickKeyframe(
        0.26,
        _upper(
          spine: rad(-56), neck: rad(-63),
          fU: rad(90), fF: rad(72),
          bU: rad(158), bF: rad(108),
        ),
      ),
      // Micro-rebound: arm bounces slightly back from overshoot
      StickKeyframe(
        0.30,
        _upper(
          spine: rad(-60), neck: rad(-66),
          fU: rad(82), fF: rad(65),
          bU: rad(152), bF: rad(112),
        ),
      ),
      // Recovery: crisp snap back to guard position
      StickKeyframe(
        0.38,
        _upper(
          spine: rad(-88), neck: rad(-90),
          fU: rad(74), fF: rad(80),
          bU: rad(103), bF: rad(108),
        ),
      ),
    ],
  );

  /// Attack 2 — overhead chop: both arms raise → hammer down with body weight.
  /// Visually distinct from attack1 — full vertical arc, two-handed feel.
  static final StickClip attack2 = StickClip(
    'attack2',
    0.44,
    [
      // Wind-up phase 1: arms begin to sweep up, body starts tilting back
      StickKeyframe(
        0.0,
        _upper(
          spine: rad(-98), neck: rad(-104),
          fU: rad(-85), fF: rad(-110),
          bU: rad(-78), bF: rad(-102),
        ),
      ),
      // Overhead peak: arms at maximum height, spine arched back hard
      StickKeyframe(
        0.14,
        _upper(
          spine: rad(-118), neck: rad(-124),
          fU: rad(-122), fF: rad(-150),  // arms flung back overhead
          bU: rad(-108), bF: rad(-135),
        ),
      ),
      // CHOP: body snaps forward violently, arms hammer through target
      StickKeyframe(
        0.26,
        _upper(
          spine: rad(-50), neck: rad(-56),
          fU: rad(75), fF: rad(98),      // arms driven past horizontal
          bU: rad(132), bF: rad(150),
        ),
      ),
      // Follow-through: arms carried low, body bent far forward
      StickKeyframe(
        0.34,
        _upper(
          spine: rad(-44), neck: rad(-50),
          fU: rad(92), fF: rad(115),
          bU: rad(142), bF: rad(162),
        ),
      ),
      // Rebound: slight bounce-back from the deep follow-through
      StickKeyframe(
        0.38,
        _upper(
          spine: rad(-52), neck: rad(-58),
          fU: rad(85), fF: rad(105),
          bU: rad(135), bF: rad(155),
        ),
      ),
      // Recovery to guard
      StickKeyframe(
        0.44,
        _upper(
          spine: rad(-88), neck: rad(-90),
          fU: rad(74), fF: rad(80),
          bU: rad(103), bF: rad(108),
        ),
      ),
    ],
  );

  /// Attack 3 — spinning finisher: deep body-torque wind → explosive 360° release.
  /// Most dramatic of the three: full rotation arc, arms at maximum extension.
  static final StickClip attack3 = StickClip(
    'attack3',
    0.56,
    [
      // Pre-spin: body compresses inward, weapon arm crosses behind
      StickKeyframe(
        0.0,
        _upper(
          spine: rad(-83), neck: rad(-82),
          fU: rad(132), fF: rad(158),    // weapon arm tucked behind body
          bU: rad(48), bF: rad(32),
        ),
      ),
      // Torque load: spine winds hard opposite direction, arms sweep through back
      StickKeyframe(
        0.10,
        _upper(
          spine: rad(-120), neck: rad(-128),
          fU: rad(-118), fF: rad(-145),
          bU: rad(-135), bF: rad(-162),
        ),
      ),
      // Spin apex (mid-rotation): arms flung to full reach at 12 o'clock
      StickKeyframe(
        0.24,
        _upper(
          spine: rad(-55), neck: rad(-58),
          fU: rad(-52), fF: rad(-35),    // arms sweeping through overhead arc
          bU: rad(-45), bF: rad(-28),
        ),
      ),
      // Strike zone: weapon drives forward-outward at maximum velocity
      StickKeyframe(
        0.35,
        _upper(
          spine: rad(-48), neck: rad(-52),
          fU: rad(38), fF: rad(58),
          bU: rad(30), bF: rad(50),
        ),
      ),
      // Overshoot: spin carries body past, arms flung outward wide
      StickKeyframe(
        0.42,
        _upper(
          spine: rad(-58), neck: rad(-62),
          fU: rad(58), fF: rad(42),
          bU: rad(48), bF: rad(65),
        ),
      ),
      // Recovery: arms pull in, spin momentum absorbed, return to guard
      StickKeyframe(
        0.56,
        _upper(
          spine: rad(-88), neck: rad(-90),
          fU: rad(74), fF: rad(80),
          bU: rad(103), bF: rad(108),
        ),
      ),
    ],
  );

  /// Heavy attack wind-up: slow, deliberate two-handed raise with full body coil.
  /// Use as anticipation for a powerful charged attack.
  static final StickClip heavyAttackWindup = StickClip(
    'heavyAttackWindup',
    0.55,
    [
      // Begin coil: arms start pulling in, body braces
      StickKeyframe(
        0.0,
        _upper(
          spine: rad(-90), neck: rad(-90),
          fU: rad(74), fF: rad(80),
          bU: rad(103), bF: rad(108),
        ),
      ),
      // Body rotates back, arms draw in to chest — gathering power
      StickKeyframe(
        0.18,
        _upper(
          spine: rad(-105), neck: rad(-110),
          fU: rad(38), fF: rad(28),     // arms pulling toward chest
          bU: rad(142), bF: rad(152),
        ),
      ),
      // Maximum coil: back arched, both arms dragged back hard
      StickKeyframe(
        0.35,
        _upper(
          spine: rad(-125), neck: rad(-132),
          fU: rad(-80), fF: rad(-110),
          bU: rad(-65), bF: rad(-95),
        ),
      ),
      // Hold: trembling at max — spine over-arched, arms at peak
      StickKeyframe(
        0.45,
        _upper(
          spine: rad(-128), neck: rad(-135),
          fU: rad(-85), fF: rad(-118),
          bU: rad(-70), bF: rad(-102),
        ),
      ),
      // Slight dip before release (sub-frame anticipation)
      StickKeyframe(
        0.55,
        _upper(
          spine: rad(-122), neck: rad(-128),
          fU: rad(-78), fF: rad(-108),
          bU: rad(-62), bF: rad(-90),
        ),
      ),
    ],
  );

  /// Air attack: mid-air downward plunge — tuck → drive arm down.
  /// Designed to layer over the fall pose.
  static final StickClip airAttack = StickClip(
    'airAttack',
    0.30,
    [
      // Raise weapon overhead while airborne
      StickKeyframe(
        0.0,
        _upper(
          spine: rad(-92), neck: rad(-95),
          fU: rad(-90), fF: rad(-115),   // weapon arm raised overhead
          bU: rad(-75), bF: rad(-98),
        ),
      ),
      // DRIVE: slam weapon straight down with full extension
      StickKeyframe(
        0.12,
        _upper(
          spine: rad(-62), neck: rad(-68),
          fU: rad(68), fF: rad(90),      // weapon arm drives downward
          bU: rad(125), bF: rad(145),
        ),
      ),
      // Follow-through: arm carried past horizontal, body bent
      StickKeyframe(
        0.20,
        _upper(
          spine: rad(-55), neck: rad(-60),
          fU: rad(82), fF: rad(108),
          bU: rad(138), bF: rad(158),
        ),
      ),
      // Hold extended pose (land will interrupt this)
      StickKeyframe(
        0.30,
        _upper(
          spine: rad(-58), neck: rad(-63),
          fU: rad(78), fF: rad(102),
          bU: rad(132), bF: rad(152),
        ),
      ),
    ],
  );

  /// Special: charge-up explosion — arms cross over chest → flung back overhead
  /// → explosive full-body snap forward as energy releases.
  static final StickClip special = StickClip(
    'special',
    0.70,
    [
      // Charge phase 1: arms cross over chest, spine compresses inward
      StickKeyframe(
        0.0,
        _upper(
          spine: rad(-100), neck: rad(-106),
          fU: rad(-65), fF: rad(-90),
          bU: rad(-70), bF: rad(-95),
        ),
      ),
      // Charge phase 2: arms pull tighter, body dips low
      StickKeyframe(
        0.10,
        _upper(
          spine: rad(-105), neck: rad(-112),
          fU: rad(-58), fF: rad(-82),
          bU: rad(-62), bF: rad(-88),
        ),
      ),
      // Charge peak: arms flung back overhead — back arched maximally
      StickKeyframe(
        0.24,
        _upper(
          spine: rad(-122), neck: rad(-130),
          fU: rad(-145), fF: rad(-168),
          bU: rad(-135), bF: rad(-160),
        ),
      ),
      // RELEASE: body snaps violently forward, arms hammer down-outward
      StickKeyframe(
        0.38,
        _upper(
          spine: rad(-46), neck: rad(-52),
          fU: rad(40), fF: rad(58),
          bU: rad(36), bF: rad(52),
        ),
      ),
      // Echo: energy reverberates — slight backward bounce
      StickKeyframe(
        0.50,
        _upper(
          spine: rad(-62), neck: rad(-68),
          fU: rad(58), fF: rad(70),
          bU: rad(55), bF: rad(68),
        ),
      ),
      // Second echo: smaller — damping out
      StickKeyframe(
        0.58,
        _upper(
          spine: rad(-58), neck: rad(-64),
          fU: rad(64), fF: rad(76),
          bU: rad(60), bF: rad(72),
        ),
      ),
      // Settle to rest
      StickKeyframe(0.70, _rest),
    ],
  );

  /// Cast: gather → coil back → dual thrust forward → hold → fade.
  /// Dramatic full-body commitment — heavier than a simple arm-wave.
  static final StickClip cast = StickClip(
    'cast',
    0.80,
    [
      // Gather: arms pull inward toward chest, body hunches slightly
      StickKeyframe(
        0.0,
        _upper(
          spine: rad(-94), neck: rad(-98),
          fU: rad(52), fF: rad(50),
          bU: rad(125), bF: rad(128),
        ),
      ),
      // Coil back: spine arches, arms draw in further — maximum coil
      StickKeyframe(
        0.20,
        _upper(
          spine: rad(-110), neck: rad(-116),
          fU: rad(28), fF: rad(18),
          bU: rad(150), bF: rad(162),
        ),
      ),
      // THRUST: both arms drive forward hard, torso snaps forward
      StickKeyframe(
        0.34,
        _upper(
          spine: rad(-66), neck: rad(-70),
          fU: rad(-30), fF: rad(-20),
          bU: rad(-35), bF: rad(-25),
        ),
      ),
      // Hold peak thrust: spell releases — body locked forward, arms trembling
      StickKeyframe(
        0.48,
        _upper(
          spine: rad(-70), neck: rad(-74),
          fU: rad(-22), fF: rad(-12),
          bU: rad(-28), bF: rad(-18),
        ),
      ),
      // Arms begin dropping as spell dissipates
      StickKeyframe(
        0.62,
        _upper(
          spine: rad(-80), neck: rad(-84),
          fU: rad(30), fF: rad(35),
          bU: rad(62), bF: rad(68),
        ),
      ),
      // Fade to rest
      StickKeyframe(0.80, _rest),
    ],
  );

  /// Hurt: violent full-body recoil — sharp hit impulse → stagger → recover.
  static final StickClip hurt = StickClip(
    'hurt',
    0.30,
    [
      // Impact: spine blown backward, head snaps hard, arms fly outward
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-52),      // torso thrown back
          neck: rad(-38),       // head snaps back violently
          armFrontUpper: rad(26),
          armFrontFore: rad(14),
          armBackUpper: rad(152),
          armBackFore: rad(165),
          legFrontThigh: rad(76),
          legFrontShin: rad(86),
          legBackThigh: rad(102),
          legBackShin: rad(97),
          rootDy: -4,           // knock upward
        ),
      ),
      // Stagger peak: arms flail wider, body still reeling
      StickKeyframe(
        0.08,
        _rest.copyWith(
          spine: rad(-58),
          neck: rad(-44),
          armFrontUpper: rad(16),
          armFrontFore: rad(4),
          armBackUpper: rad(165),
          armBackFore: rad(178),
          rootDy: -2,
        ),
      ),
      // Fall-back: center of mass shifting back, knee bends
      StickKeyframe(
        0.14,
        _rest.copyWith(
          spine: rad(-64),
          neck: rad(-52),
          armFrontUpper: rad(22),
          armFrontFore: rad(10),
          armBackUpper: rad(160),
          armBackFore: rad(172),
          legFrontThigh: rad(82),
          legFrontShin: rad(98),
          rootDy: 4,
        ),
      ),
      // Recovery stumble: body comes forward trying to regain balance
      StickKeyframe(0.30, _rest),
    ],
  );

  /// Dash / forward roll: dive → tight tuck → roll-through → exit crouch.
  static final StickClip dash = StickClip(
    'dash',
    0.38,
    [
      // Dive commitment: body pitches hard forward, arms tuck tight
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-30),      // near-horizontal dive
          neck: rad(-16),       // head tucked, chin to chest
          legFrontThigh: rad(60),
          legFrontShin: rad(36),
          legBackThigh: rad(52),
          legBackShin: rad(28),
          armFrontUpper: rad(8),
          armFrontFore: rad(-8),
          armBackUpper: rad(20),
          armBackFore: rad(5),
          rootDy: 3,
        ),
      ),
      // Tuck apex: fully balled — arms crossed under, knees to chest
      StickKeyframe(
        0.10,
        _rest.copyWith(
          spine: rad(-12),      // almost prone
          neck: rad(-2),        // head in line with spine
          legFrontThigh: rad(38),
          legFrontShin: rad(12),
          legBackThigh: rad(32),
          legBackShin: rad(8),
          armFrontUpper: rad(4),
          armFrontFore: rad(-12),
          armBackUpper: rad(10),
          armBackFore: rad(-5),
          rootDy: 9,
        ),
      ),
      // Roll-through: spine rotating through horizontal plane
      StickKeyframe(
        0.20,
        _rest.copyWith(
          spine: rad(-52),
          neck: rad(-42),
          legFrontThigh: rad(52),
          legFrontShin: rad(22),
          legBackThigh: rad(62),
          legBackShin: rad(32),
          armFrontUpper: rad(18),
          armFrontFore: rad(5),
          armBackUpper: rad(32),
          armBackFore: rad(16),
          rootDy: 11,
        ),
      ),
      // Unrolling: legs extend as body comes upright
      StickKeyframe(
        0.28,
        _rest.copyWith(
          spine: rad(-70),
          neck: rad(-65),
          legFrontThigh: rad(70),
          legFrontShin: rad(65),
          legBackThigh: rad(85),
          legBackShin: rad(75),
          armFrontUpper: rad(42),
          armFrontFore: rad(30),
          armBackUpper: rad(78),
          armBackFore: rad(88),
          rootDy: 7,
        ),
      ),
      // Exit crouch: low guard, weapons up, ready to fight
      StickKeyframe(
        0.38,
        _rest.copyWith(
          spine: rad(-79),
          neck: rad(-76),
          legFrontThigh: rad(78),
          legFrontShin: rad(102),
          legBackThigh: rad(96),
          legBackShin: rad(86),
          armFrontUpper: rad(58),
          armFrontFore: rad(50),
          armBackUpper: rad(120),
          armBackFore: rad(128),
          rootDy: 5,
        ),
      ),
    ],
  );

  // ---- NEW CLIPS ------------------------------------------------------------

  /// Guard / block: weapon arm raised in a high cross-block.
  /// Stable loop — use while holding block input.
  static final StickClip guard = StickClip(
    'guard',
    1.6,
    [
      // Block ready: weapon arm raised diagonally, off-arm tight to body
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-92),
          neck: rad(-94),
          armFrontUpper: rad(-22),   // weapon arm up in high guard
          armFrontFore: rad(-12),
          armBackUpper: rad(82),     // off-arm braced
          armBackFore: rad(75),
          legFrontThigh: rad(80),    // slight forward stance
          legFrontShin: rad(88),
          legBackThigh: rad(100),
          legBackShin: rad(94),
          rootDy: 2,
        ),
      ),
      // Micro-breathe in guard: slight settle, arms hold firm
      StickKeyframe(
        0.7,
        _rest.copyWith(
          spine: rad(-90),
          neck: rad(-92),
          armFrontUpper: rad(-20),
          armFrontFore: rad(-10),
          armBackUpper: rad(84),
          armBackFore: rad(78),
          legFrontThigh: rad(80),
          legFrontShin: rad(88),
          legBackThigh: rad(100),
          legBackShin: rad(94),
          rootDy: 3.5,
        ),
      ),
      // Back to guard peak
      StickKeyframe(
        1.6,
        _rest.copyWith(
          spine: rad(-92),
          neck: rad(-94),
          armFrontUpper: rad(-22),
          armFrontFore: rad(-12),
          armBackUpper: rad(82),
          armBackFore: rad(75),
          legFrontThigh: rad(80),
          legFrontShin: rad(88),
          legBackThigh: rad(100),
          legBackShin: rad(94),
          rootDy: 2,
        ),
      ),
    ],
    loop: true,
  );

  /// Victory / combat idle: triumphant relaxed stance after winning.
  /// Weight on one leg, weapon lowered, slight chest-puff.
  static final StickClip victory = StickClip(
    'victory',
    3.2,
    [
      // First beat: weight shifts to back leg, weapon lowered confidently
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-88),
          neck: rad(-86),
          armFrontUpper: rad(85),    // weapon arm at side — relaxed
          armFrontFore: rad(95),
          armBackUpper: rad(98),
          armBackFore: rad(105),
          legFrontThigh: rad(78),    // front leg slightly forward — casual
          legFrontShin: rad(88),
          legBackThigh: rad(105),
          legBackShin: rad(96),
          rootDy: 0,
        ),
      ),
      // Slow chest rise — deep breath after exertion
      StickKeyframe(
        0.9,
        _rest.copyWith(
          spine: rad(-92),
          neck: rad(-90),
          armFrontUpper: rad(80),
          armFrontFore: rad(90),
          armBackUpper: rad(100),
          armBackFore: rad(107),
          legFrontThigh: rad(78),
          legFrontShin: rad(87),
          legBackThigh: rad(105),
          legBackShin: rad(96),
          rootDy: -3,
        ),
      ),
      // Weapon raise — brief show-off flourish
      StickKeyframe(
        1.6,
        _rest.copyWith(
          spine: rad(-94),
          neck: rad(-92),
          armFrontUpper: rad(45),    // weapon raised
          armFrontFore: rad(38),
          armBackUpper: rad(108),
          armBackFore: rad(115),
          legFrontThigh: rad(77),
          legFrontShin: rad(87),
          rootDy: -4,
        ),
      ),
      // Lower weapon back — satisfied
      StickKeyframe(
        2.4,
        _rest.copyWith(
          spine: rad(-89),
          neck: rad(-87),
          armFrontUpper: rad(83),
          armFrontFore: rad(93),
          armBackUpper: rad(100),
          armBackFore: rad(106),
          legFrontThigh: rad(78),
          legFrontShin: rad(88),
          legBackThigh: rad(104),
          legBackShin: rad(95),
          rootDy: 2,
        ),
      ),
      // Return
      StickKeyframe(
        3.2,
        _rest.copyWith(
          spine: rad(-88),
          neck: rad(-86),
          armFrontUpper: rad(85),
          armFrontFore: rad(95),
          armBackUpper: rad(98),
          armBackFore: rad(105),
          legFrontThigh: rad(78),
          legFrontShin: rad(88),
          legBackThigh: rad(105),
          legBackShin: rad(96),
          rootDy: 0,
        ),
      ),
    ],
    loop: true,
  );

  /// Back-step: quick retreating hop — push off front foot, land back.
  /// One-shot: used for defensive movement/dodge-back response.
  static final StickClip backStep = StickClip(
    'backStep',
    0.30,
    [
      // Push: weight transfers back, front foot pushes off ground
      StickKeyframe(
        0.0,
        _rest.copyWith(
          spine: rad(-84),
          neck: rad(-82),
          legFrontThigh: rad(70),    // front leg pushing — extending back
          legFrontShin: rad(88),
          legBackThigh: rad(108),    // back leg absorbing weight transfer
          legBackShin: rad(102),
          armFrontUpper: rad(55),    // arms react to sudden movement
          armFrontFore: rad(45),
          armBackUpper: rad(118),
          armBackFore: rad(130),
          rootDy: 2,
        ),
      ),
      // Airborne: brief hop — both feet off ground momentarily
      StickKeyframe(
        0.10,
        _rest.copyWith(
          spine: rad(-80),
          neck: rad(-78),
          legFrontThigh: rad(75),
          legFrontShin: rad(95),
          legBackThigh: rad(95),
          legBackShin: rad(105),
          armFrontUpper: rad(48),
          armFrontFore: rad(38),
          armBackUpper: rad(125),
          armBackFore: rad(138),
          rootDy: -3,
        ),
      ),
      // Landing back: absorb the back-step landing
      StickKeyframe(
        0.20,
        _rest.copyWith(
          spine: rad(-85),
          neck: rad(-86),
          legFrontThigh: rad(82),
          legFrontShin: rad(92),
          legBackThigh: rad(100),
          legBackShin: rad(96),
          armFrontUpper: rad(62),
          armFrontFore: rad(55),
          armBackUpper: rad(112),
          armBackFore: rad(122),
          rootDy: 4,
        ),
      ),
      // Settle into ready stance
      StickKeyframe(0.30, _rest),
    ],
  );

  // ---- Lookup ---------------------------------------------------------------

  static StickClip? byName(String n) {
    switch (n) {
      case 'idle':
        return idle;
      case 'idleVariant':
        return idleVariant;
      case 'idleVariantB':
        return idleVariantB;
      case 'run':
        return run;
      case 'runFast':
        return runFast;
      case 'jump':
        return jump;
      case 'fall':
        return fall;
      case 'land':
        return land;
      case 'attack1':
        return attack1;
      case 'attack2':
        return attack2;
      case 'attack3':
        return attack3;
      case 'heavyAttackWindup':
        return heavyAttackWindup;
      case 'airAttack':
        return airAttack;
      case 'special':
        return special;
      case 'cast':
        return cast;
      case 'hurt':
        return hurt;
      case 'dash':
        return dash;
      case 'guard':
        return guard;
      case 'victory':
        return victory;
      case 'backStep':
        return backStep;
    }
    return null;
  }
}
