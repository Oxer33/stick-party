import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../art/fx/particles.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/area_fill_grid.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'paint_render.dart';

/// Numeric tuning — no magic numbers inline. Times in seconds; positions and
/// speeds are in normalized 0..1 arena space unless noted.
class _Tuning {
  static const int cols = 30;
  static const int rows = 38;
  static const double timeLimit = 30;

  // ── Steering (purely repositioning) ───────────────────────────────────────
  // Dragging moves the cursor toward the finger with a frame-rate-independent
  // ease so a drag reads as a fluid reposition between taps. The cursor NEVER
  // paints on its own — only a TAP lays a splat.
  static const double followPerSec = 18.0; // cursor → touch chase speed

  // Bot cursor travel (norm units/sec). Fast enough to reach its next (near)
  // target between taps so travel never bottlenecks the cadence; the actual
  // tap-throughput governor is [botTapIntervalMin]/[botTapIntervalMax] below, NOT
  // travel speed. (A previous build made travel the throughput knob, which let a
  // brisk bot out-TAP the fixed-cadence human and bury it — the human couldn't
  // win even on easy. Cadence is now explicit and difficulty-scaled.)
  static const double botMoveSpeed = 3.0;

  // ── THE MECHANIC: tap-to-splat CHAIN COMBOS ───────────────────────────────
  // Every TAP (a down event) lays ONE big splat at the cursor. Splats CHAIN:
  //  * Tap that CLAIMS fresh/rival turf (gained cells) AND lands on a different
  //    grid cell than your last tap, soon enough after it → chain += 1, and the
  //    next splat is bigger ([chainRadiusStep] per link, capped).
  //  * Tap your OWN cells, or mash the SAME cell, or let the window lapse →
  //    the chain BREAKS to 0 and the splat shrinks to a feeble dud.
  // So the skill is rapidly claiming contested/fresh turf in a chain, reading
  // where to go next — NOT holding/mashing one spot.
  static const double chainWindowSec = 0.62; // max gap between links
  static const int chainMax = 9; // cap the counter (and the size bonus)
  static const double chainMinGainFrac = 0.18; // gained/touched needed to extend
  static const int chainMoveCells = 2; // taps must move ≥ this many cells

  // ── Splat sizing (escalates STEEPLY with the chain) ────────────────────────
  // A cold tap (chain 0) lays a SMALL splat; each chain link fattens it hard by
  // [chainRadiusStep] up to [splatRadiusMax] — a maxed chain paints an order of
  // magnitude more area than a cold tap. A broken/dud tap collapses to
  // [dudRadius] and paints almost nothing. So coverage is won by the SIZE the
  // chain unlocks, not by raw tap volume: a scattershot tapper sprays little
  // cold dots, while a sustained chainer drops fat board-eating splats.
  static const double splatRadiusBase = 0.040; // a cold (chain-0) tap: small
  static const double chainRadiusStep = 0.013; // radius add per chain link
  static const double splatRadiusMax = 0.150; // hard cap so it stays readable
  static const double dudRadius = 0.016; // a broken-chain / empty-can dud

  // ── INK: the sub-gate that bounds raw tap-spam ─────────────────────────────
  // Each tap spends [inkPerTap]; the can refills at [inkRechargePerSec]. Tapping
  // faster than the refill drains it and taps SPUTTER (dud radius, no grid
  // paint, and the chain breaks). A measured chainer taps a steady cadence that
  // stays above the floor; a frantic masher/spam-tapper empties the can and
  // dud-spams, so even moving all over the board it self-throttles to a few
  // cold dots. Ink is the floor under the chain, not the headline.
  // [inkRechargePerSec] is tuned so a measured ~0.33s tap cadence stays
  // net-positive (never sputters) while frame-rate mashing drains and throttles
  // to a few cold dots — so the steady chainer keeps a clean combo and the
  // spammer cannot.
  static const double inkPerTap = 0.2; // ink one tap spends (~5 taps drains it)
  static const double inkRechargePerSec = 0.62; // refill rate (always on)
  static const double inkSputterFloor = 0.18; // below this a tap only sputters
  static const double inkLowWarn = 0.34; // ring shows a low-ink warning here

  // ── Climax: the GOLD RUSH finale (the unmistakable peak) ───────────────────
  // For the last [goldRushSec] the economy is supercharged: taps cost no ink,
  // the can stays full, the chain window widens so combos are easier to hold,
  // and every splat is fattened ([goldRushRadiusBonus], capped above the normal
  // max) and throws extra droplets — so a trailing kid can chain-flip the board
  // in a shouting finish. A one-shot banner + flash + shake announces it.
  static const double goldRushSec = 6.0; // length of the finale
  static const double goldRushRadiusBonus = 0.045; // extra radius during finale
  static const double goldRushRadiusMax = 0.20; // raised cap during the burst
  static const double goldRushWindowSec = 0.95; // widened chain window
  static const int goldRushExtraDroplets = 8; // bonus droplets per splat

  // Decisive-flip cue: when the lead changes hands during the finale we punch a
  // slow-mo + flash + popup so the moment the board flips reads as huge. Re-arms
  // after a short cooldown so a frantic back-and-forth keeps popping.
  static const double leadFlipSlowMoSec = 0.5;
  static const double leadFlipSlowScale = 0.45;
  static const double leadFlipCooldownSec = 0.7;
  static const double leadFlipMinFrac = 0.02; // ignore dead-heat jitter

  // ── Bots ───────────────────────────────────────────────────────────────────
  // Bots stay passive for a beat so they never out-paint an idle human at the
  // gun; then they engage on a beatable cadence governed by [BotProfile].
  static const double botWarmupSec = 1.5;

  // A bot's tap cadence: it taps when it ARRIVES at a fresh target cell. The
  // reaction clock gates how fast it re-picks/arrives, so faster bots chain
  // quicker. Aim jitter (scaled by 1-accuracy) keeps weak bots off the optimum.
  static const double botAimJitter = 0.045;

  // Bot chain DISCIPLINE (the skill gradient): a disciplined bot
  // (accuracy ≥ [botChainAcc]) always hops to a fresh, contested cell, so it
  // BUILDS chains. A sloppy bot frequently re-taps near its own turf or mashes,
  // BREAKING its own chain and painting little — exactly what makes easy bots
  // beatable. [botSloppyRetapChance] is the per-pick odds a sloppy bot wastes a
  // tap on home turf instead of chaining out.
  static const double botChainAcc = 0.7;
  static const double botSloppyRetapChance = 0.55;

  // Shared-canvas raiding: a trailing bot is biased to hunt cells the LEADER
  // owns (chain over them to steal turf). The chance ramps with how far behind.
  static const double botRaidChanceMax = 0.7; // max odds a goal targets leader
  static const double botRaidRefGap = 0.18; // coverage gap (frac) for full odds
  static const double botLeaderCellWeight = 1.5; // pull toward a leader's cell

  // Bot TAP CADENCE (the real difficulty dial). A bot may lay a tap only when
  // its per-bot cooldown elapses, scaled by [BotProfile.accuracy] from
  // [botTapIntervalMin] (hard, ~0.40s — a touch slower than a skilled human's
  // ~0.33s) to [botTapIntervalMax] (easy, slow). Throughput is therefore explicit
  // and capped: even a hard bot taps a hair slower than a good human, so a human
  // who keeps a clean chain stays ahead of it; an easy bot taps lazily AND (being
  // sloppy) breaks its own chains, so it is comfortably out-painted. This is what
  // makes EASY clearly beatable and HARD tough-but-beatable (measured ~0.25 human
  // win-rate, 12+ seeds) rather than a board-burying spammer.
  static const double botTapIntervalMin = 0.40; // hard-bot gap between taps
  static const double botTapIntervalMax = 0.62; // easy-bot gap between taps
  // ±jitter fraction on the cadence so bots don't tick like metronomes (keeps
  // outcomes varied across seeds; no two contests play identically).
  static const double botTapIntervalJitter = 0.18;

  // Bot ink discipline: a sloppy (easy) bot mashes through empty and sputters
  // cold duds; a disciplined bot paces (via its cadence above) so its can stays
  // above the sputter floor. We DON'T idle-wait a disciplined bot for ink (that
  // starved it below a sloppy bot's output, inverting the dial).

  // Bot target selection PROXIMITY bias. The bot taps on ARRIVAL, so to chain it
  // must keep consecutive targets CLOSE (short hops land inside the chain window
  // and keep the cursor on a tight, board-eating sweep). We pick the nearest
  // high-value fresh/rival cell by scoring weight / (dist + [botTargetDistBias])
  // — the SMALLER this bias, the more sharply the bot prefers near cells. (Was a
  // weight * (0.4 + dist) bias that rewarded FAR cells, so the bot crossed the
  // whole board between taps, never chained, and painted almost nothing.) A
  // [chainMoveCells]-cell minimum hop is still enforced at tap time, so "nearest"
  // never collapses to mashing one spot.
  static const double botTargetDistBias = 0.06;

  // Visual stamp budget: only the most recent stamps are drawn crisply on top
  // of the baked coverage tint, which protects render cost in long games.
  static const int maxStamps = 80;

  // Particle feel.
  static const int dropletCountBase = 7;
  static const double dropletSpeed = 320; // px/s
  static const double dropletGravity = 520;
  static const double dropletLife = 0.5;
  static const double dropletSizeBase = 5;
  static const double dropletSizePerRadius = 26; // size add / normalized radius
  static const int chainDroplets = 2; // extra droplets per chain link

  // Stamp sheen dry-out time.
  static const double sheenDrySec = 1.2;

  // Cursor flash (recent-tap) decay time.
  static const double tapFlashSec = 0.18;

  // A tiny hit-stop punched on a high chain link so the escalation is felt.
  static const int chainHitStopAt = 6; // chain length that earns a hit-stop
  static const double chainHitStopSec = 0.04;
  static const int chainShakeAt = 3; // chain length that earns a light shake

  // Bot target search: sample stride over the grid's cells when hunting the
  // best target (every cell is overkill for a coarse target).
  static const int botSampleStride = 1;

  // Mascot: per-frame brush travel (norm units) above which the rider runs.
  static const double mascotMoveThreshold = 0.0015;
}

/// A player's paint cursor. Driven entirely by the player: it eases toward the
/// finger while dragging (purely repositioning — it does NOT paint), and every
/// TAP lays one big splat at the cursor that CHAINS with the previous tap.
/// Position is in normalized 0..1 arena space. Mutable, round-scoped value.
class _Cursor {
  final int playerId;
  final Color color;
  final bool isRoller; // visual tool variety (odd ids use a roller)
  final Rect zone; // this player's home region (normalized arena space)
  final ReactionClock? clock; // bots re-pick a target on this cadence

  /// The painter mascot riding this brush (purely visual; reacts to motion +
  /// taps + win). Owns its own pose/anim clock, advanced each frame.
  final StickFigure figure;

  Offset pos; // where the brush currently is
  Offset target; // where it is steering toward (clamped into arena)
  double ink = 1.0; // 0..1 remaining paint reserve

  // ── Chain state (the visible skill) ──
  int chain = 0; // current combo length (0 = cold)
  double sinceTap = 1e9; // seconds since the last tap (drives the window)
  int _lastCol = -999; // grid cell of the last tap (mash detection)
  int _lastRow = -999;
  bool brokeChain = false; // last tap broke the chain (drives the ▼ dud cue)
  bool sputter = false; // last tap fired on empty (a feeble dud)
  double chainPulse = 0; // 0..1 flare when the chain just grew (visual)

  double flash = 0; // recent-tap flash timer (visual)
  Offset _botGoal; // bot's current coverage goal (normalized)
  double botTapCooldown = 0; // bot: seconds until it may lay its next tap
  Offset _prevPos; // last frame's position, to read motion for the mascot loco
  bool _facingRight = true; // mascot facing, flipped by horizontal travel

  /// Active chain window in seconds — the max gap a tap may follow the previous
  /// one and still extend the combo. Set each frame by the game (widens during
  /// the GOLD RUSH finale). Public so the game can retune it live.
  double chainWindow = _Tuning.chainWindowSec;

  _Cursor({
    required this.playerId,
    required this.color,
    required this.isRoller,
    required this.zone,
    required this.pos,
    required this.figure,
    this.clock,
  })  : target = pos,
        _botGoal = pos,
        _prevPos = pos;

  /// Drive the mascot's locomotion + facing from how far the brush moved this
  /// frame, and advance its animation clock. Purely visual — no sim effect.
  void updateMascot(double dt, double moveNormThreshold) {
    final delta = pos - _prevPos;
    final moved = delta.distance;
    if (moved > moveNormThreshold) {
      figure.setLoco(LocoState.run);
      if (delta.dx.abs() > moveNormThreshold * 0.5) {
        _facingRight = delta.dx >= 0;
      }
    } else {
      figure.setLoco(LocoState.idle);
    }
    _prevPos = pos;
    figure.update(dt);
  }

  bool get facingRight => _facingRight;

  bool get isBot => clock != null;

  /// Clamp a normalized point into the SHARED arena `[inset, 1-inset]^2`.
  ///
  /// Brushes are NOT walled into their [zone] — every cursor roams the whole
  /// canvas, so chaining a splat OVER a rival's cells (last-writer-wins in
  /// [AreaFillGrid.paintCircleDelta]) STEALS them. Each player STARTS in their
  /// own corner; [zone] is now only a starting/home hint and a faint label.
  Offset clampToZone(Offset p) {
    const inset = 0.005;
    return Offset(
      p.dx.clamp(inset, 1 - inset),
      p.dy.clamp(inset, 1 - inset),
    );
  }

  /// Steer the brush toward [target] with a frame-rate-independent ease. [dt] is
  /// sim seconds. Repositioning only — no paint is laid here.
  void steer(double dt) {
    final follow = (1.0 - math.exp(-_Tuning.followPerSec * dt)).clamp(0.0, 1.0);
    pos = Offset(
      pos.dx + (target.dx - pos.dx) * follow,
      pos.dy + (target.dy - pos.dy) * follow,
    );
  }

  /// Advance timers (flash + chain window + pulse). [dt] is real seconds.
  void tickTimers(double dt) {
    if (flash > 0) flash = math.max(0, flash - dt);
    if (chainPulse > 0) chainPulse = math.max(0, chainPulse - dt * 4);
    sinceTap += dt;
    // The chain only lives inside the window; once it lapses, it goes cold so
    // the counter visibly resets and the next splat starts small again.
    if (chain > 0 && sinceTap > chainWindow) chain = 0;
  }

  /// Refill the can every frame. During the finale the can stays full so the
  /// climax can chain freely. [dt] is sim seconds.
  void rechargeInk(double dt, {required bool freeFlow}) {
    if (freeFlow) {
      ink = 1.0;
      return;
    }
    ink = math.min(1.0, ink + _Tuning.inkRechargePerSec * dt);
  }

  /// Spend ink for one tap. During the finale ink is free. Clamped at 0.
  void spendInk({required bool freeFlow}) {
    if (freeFlow) return;
    ink = math.max(0.0, ink - _Tuning.inkPerTap);
  }

  /// True when the can is too low to lay a real splat (a tap only sputters).
  bool get isEmpty => ink < _Tuning.inkSputterFloor;

  Offset get botGoal => _botGoal;
  set botGoal(Offset g) => _botGoal = clampToZone(g);

  /// 0..1 "charge" readout for the cursor ring — the remaining ink, so the
  /// brush shows how much paint is left before a tap sputters.
  double get charge => ink.clamp(0.0, 1.0);

  /// Record where this tap landed (grid cell) for mash detection next tap.
  void rememberTapCell(int col, int row) {
    _lastCol = col;
    _lastRow = row;
  }

  /// True if a tap at ([col],[row]) is far enough from the last tap's cell to
  /// count as moving to fresh ground (not mashing the same spot).
  bool movedFrom(int col, int row) {
    final dc = (col - _lastCol).abs();
    final dr = (row - _lastRow).abs();
    return math.max(dc, dr) >= _Tuning.chainMoveCells;
  }
}

/// A drawn paint stamp recorded when a splat lands, so the renderer can paint a
/// crisp irregular blob (with drips/droplets) on top of the baked coverage
/// tint. Round-scoped; capped to [_Tuning.maxStamps].
class _Stamp {
  final Offset pos; // normalized 0..1
  final double radius; // normalized
  final Color color;
  final int seed; // deterministic visual variation
  double age = 0; // seconds since it landed (drives sheen/droplet fade)

  _Stamp({
    required this.pos,
    required this.radius,
    required this.color,
    required this.seed,
  });
}

/// Paint Splash — a splatter-paint turf war on ONE SHARED [AreaFillGrid].
///
/// OBJECTIVE (obvious, kid-readable): own the most canvas when the timer ends.
/// Score is the live owned-cell count, resolved via [finishByScore].
///
/// CONTROL (tap-to-splat chain combos, ONE shared canvas):
///  * Every player drives a paint cursor over the WHOLE arena. DRAG to move the
///    brush anywhere — dragging only repositions, it lays no paint.
///  * Each TAP lays ONE big splat at the cursor. Because paint is
///    last-writer-wins, a splat over a rival's color FLIPS those cells to you.
///
/// THE VISIBLE SKILL — CHAIN COMBOS (why mashing LOSES): tapping FRESH or RIVAL
/// cells in quick succession, each on a NEW spot, builds a CHAIN — and each link
/// fattens the next splat (a visible counter rides the cursor and the splats
/// swell). Tapping your OWN turf, mashing one spot, or letting the window lapse
/// BREAKS the chain: the splat collapses to a feeble dud. A measured chainer who
/// reads where the fresh/contested turf is dominates coverage; a one-spot masher
/// breaks their own chain on every tap and paints almost nothing. (An ink can
/// under it all caps raw tap-spam: tap faster than it refills and taps sputter.)
///
/// Bots roam the shared canvas hunting the freshest contested cell and, when
/// behind, RAID the leader's turf. A SKILLED bot hops cleanly between fresh
/// cells so it BUILDS chains; a sloppy bot re-taps home turf and breaks its own
/// chain. [BotProfile] accuracy decides discipline + aim, so easy bots leave
/// coverage a human can out-chain. A short warmup keeps them passive at the gun.
class PaintSplash extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'paint_splash',
        name: 'Paint Splash',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  late Juice _juice;
  late AreaFillGrid _grid;
  final List<_Cursor> _cursors = <_Cursor>[];
  final List<_Stamp> _stamps = <_Stamp>[];
  double _elapsed = 0;
  int _splatSeq = 0; // monotonically increasing seed source for stamps
  bool _goldRushAnnounced = false; // the GOLD RUSH cue fired once
  int? _lastLeaderId; // leader tracked frame-to-frame for the flip cue
  double _flipCooldown = 0; // re-arm timer for the decisive-flip punch
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _grid = AreaFillGrid(cols: _Tuning.cols, rows: _Tuning.rows);
    _spawnCursors();
    begin();
  }

  void _spawnCursors() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final zone = ctx.zones.forPlayer(p.id)?.normRect ??
          _fallbackZone(i, count); // robustness if zones are missing
      final start = zone.center;
      final color = Color(p.colorArgb);
      _cursors.add(_Cursor(
        playerId: p.id,
        color: color,
        isRoller: p.id.isOdd,
        zone: zone,
        pos: start,
        figure: StickFigure(style: _mascotStyle(color))
          ..setLoco(LocoState.idle),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
  }

  /// Bright painter-mascot style in the player's color: color fill, brightened
  /// neon outline, soft glow. Mirrors the sprinter style in tap_sprint so the
  /// cast reads consistently across games.
  StickStyle _mascotStyle(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 4,
        lineWidth: 1.0,
        rimAlpha: 0.28,
        shadowAlpha: 0.0, // the renderer draws its own contact shadow
        gradientBottom: 0.55,
      );

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  /// Horizontal-strip fallback so the game still works if a context arrives
  /// without a matching zone for a player id.
  Rect _fallbackZone(int index, int count) {
    final h = 1.0 / count;
    return Rect.fromLTRB(0, index * h, 1, (index + 1) * h);
  }

  // ── Input: drag repositions; a tap lays one chaining splat ──────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final c = _cursorOf(input.playerId);
    if (c == null) return;

    switch (input.phase) {
      case InputPhase.down:
        // A TAP. Steer to the touch point and snap the cursor there so the
        // splat lands exactly where the player tapped (a tap should feel
        // precise, not lag behind a drag ease).
        if (input.normPos != Offset.zero) {
          c.target = c.clampToZone(input.normPos);
          c.pos = c.target;
        }
        _tap(c);
      case InputPhase.holdTick:
        // Dragging the finger only REPOSITIONS the cursor — no paint. A pure
        // per-frame held tick (normPos == Offset.zero) does nothing at all.
        if (input.normPos != Offset.zero) {
          c.target = c.clampToZone(input.normPos);
        }
      case InputPhase.up:
        // Lifting the finger does nothing — taps are discrete.
        break;
    }
  }

  /// Lay one splat for [c] at its current position — the whole mechanic.
  ///
  ///  * Empty can → SPUTTER: a feeble dud, no grid paint, chain BREAKS.
  ///  * Otherwise paint the grid (last-writer-wins). If the splat CLAIMED fresh/
  ///    rival turf (a real gain) and landed on a NEW cell within the chain
  ///    window, the chain GROWS and the next splat is bigger; if it merely
  ///    re-coated owned cells, mashed the same cell, or the window lapsed, the
  ///    chain BREAKS to 0 and the splat is a dud.
  /// Records a visual stamp and fires juice scaled by the chain + what it won.
  void _tap(_Cursor c) {
    final at = c.pos;
    if (!at.dx.isFinite || !at.dy.isFinite) return;
    final freeFlow = _inGoldRush;
    final col = (at.dx * _Tuning.cols).floor().clamp(0, _Tuning.cols - 1);
    final row = (at.dy * _Tuning.rows).floor().clamp(0, _Tuning.rows - 1);

    // Empty can → sputter dud: breaks the chain, paints nothing.
    if (!freeFlow && c.isEmpty) {
      c.sputter = true;
      c.brokeChain = c.chain > 0;
      c.chain = 0;
      c.sinceTap = 0;
      c.flash = _Tuning.tapFlashSec;
      c.rememberTapCell(col, row);
      _recordStamp(at, _Tuning.dudRadius, c.color);
      _juice.particles.burst(
        at: _toPixels(at),
        count: 3,
        color: c.color,
        speed: _Tuning.dropletSpeed * 0.4,
        size: _Tuning.dropletSizeBase * 0.6,
        gravity: _Tuning.dropletGravity,
        life: _Tuning.dropletLife * 0.6,
        shape: ParticleShape.circle,
      );
      return;
    }

    // Decide whether this tap EXTENDS the chain or BREAKS it. Read the window +
    // mash state BEFORE painting, then paint and check the gain.
    final inWindow = c.sinceTap <= c.chainWindow;
    final moved = c.movedFrom(col, row);

    final radius = _splatRadius(c); // sized from the CURRENT chain
    final result = _grid.paintCircleDelta(c.playerId, at, radius);
    c.spendInk(freeFlow: freeFlow);

    final gainFrac =
        result.touched == 0 ? 0.0 : result.gained / result.touched;
    final claimedFresh = gainFrac >= _Tuning.chainMinGainFrac;

    c.sputter = false;
    c.sinceTap = 0;
    c.flash = _Tuning.tapFlashSec;
    c.rememberTapCell(col, row);

    if (claimedFresh && moved && (inWindow || c.chain == 0)) {
      // CHAIN LINK: a clean grab on fresh ground. Grow the combo (capped).
      c.chain = math.min(_Tuning.chainMax, c.chain + 1);
      c.brokeChain = false;
      c.chainPulse = 1.0;
    } else {
      // BREAK: mashed the same cell, re-coated owned turf, or window lapsed.
      c.brokeChain = c.chain > 0;
      c.chain = 0;
    }

    _recordStamp(at, radius, c.color);
    _burstDroplets(at, radius, c.color, result.stolen, c.chain);
    // The mascot swings its arm on each tap so it visibly paints.
    c.figure.attack(c.chain);
    // A growing chain pops the brush so the escalation is felt.
    if (c.chain >= _Tuning.chainShakeAt) _juice.shake.light();
    if (c.chain >= _Tuning.chainHitStopAt) {
      _juice.hitStop.trigger(_Tuning.chainHitStopSec);
    }
  }

  /// True once the round enters its final GOLD RUSH burst window.
  bool get _inGoldRush => _elapsed >= _Tuning.timeLimit - _Tuning.goldRushSec;

  /// Splat radius for a tap, sized from the CURRENT chain: base + a step per
  /// link, capped. During GOLD RUSH every splat gets a bonus and a raised cap.
  double _splatRadius(_Cursor c) {
    var r = _Tuning.splatRadiusBase + c.chain * _Tuning.chainRadiusStep;
    if (_inGoldRush) {
      r += _Tuning.goldRushRadiusBonus;
      return r.clamp(_Tuning.splatRadiusBase, _Tuning.goldRushRadiusMax);
    }
    return r.clamp(_Tuning.splatRadiusBase, _Tuning.splatRadiusMax);
  }

  void _recordStamp(Offset at, double radius, Color color) {
    _stamps.add(_Stamp(
      pos: at,
      radius: radius,
      color: color,
      seed: _splatSeq++,
    ));
    // Keep only the most recent stamps drawn crisply (the rest live on as the
    // baked coverage tint), protecting render cost in long games.
    if (_stamps.length > _Tuning.maxStamps) {
      _stamps.removeRange(0, _stamps.length - _Tuning.maxStamps);
    }
  }

  /// A burst of paint droplets + impact feel. A splat that STEALS rival cells
  /// or extends a CHAIN throws more droplets — the satisfying combo feedback.
  void _burstDroplets(
      Offset at, double radius, Color color, int stolen, int chain) {
    final px = _toPixels(at);
    final stealKick = math.min(stolen, 10);
    final count = _Tuning.dropletCountBase +
        stealKick +
        chain * _Tuning.chainDroplets +
        (_inGoldRush ? _Tuning.goldRushExtraDroplets : 0);
    _juice.particles.burst(
      at: px,
      count: count,
      color: color,
      speed: _Tuning.dropletSpeed *
          (0.8 + 0.2 * (radius / _Tuning.splatRadiusMax)),
      size: _Tuning.dropletSizeBase + radius * _Tuning.dropletSizePerRadius,
      gravity: _Tuning.dropletGravity,
      life: _Tuning.dropletLife,
      shape: ParticleShape.circle,
    );
    if (stolen > 4) _juice.shake.light();
  }

  /// Fire the one-shot GOLD RUSH cue the instant the finale window opens: a big
  /// banner, a screen flash, a shake and a bright burst so every kid knows the
  /// paint just went huge and unlimited — time to chain for the win.
  void _maybeAnnounceGoldRush() {
    if (_goldRushAnnounced || !_inGoldRush) return;
    _goldRushAnnounced = true;
    final center = Offset(_lastSize.width / 2, _lastSize.height * 0.5);
    _juice.bigBanner('GOLD RUSH!', color: const Color(0xFFFFFFFF));
    _juice.flashScreen(const Color(0xFFFFFFFF), strength: 0.45);
    _juice.shake.medium();
    _juice.particles.burst(
      at: center,
      count: 24,
      color: const Color(0xFFFFFFFF),
      speed: 360,
      size: 7,
      life: 0.7,
    );
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);
    if (_flipCooldown > 0) _flipCooldown = math.max(0, _flipCooldown - dt);

    _maybeAnnounceGoldRush();

    final freeFlow = _inGoldRush;
    final window =
        freeFlow ? _Tuning.goldRushWindowSec : _Tuning.chainWindowSec;
    _driveBots(sdt);

    for (final c in _cursors) {
      c.chainWindow = window;
      c.steer(sdt);
      c.tickTimers(dt);
      c.rechargeInk(sdt, freeFlow: freeFlow);
      // Advance the painter mascot: run while the brush travels, idle when still.
      c.updateMascot(sdt, _Tuning.mascotMoveThreshold);
    }
    for (final s in _stamps) {
      s.age += dt;
    }

    _maybeAnnounceLeadFlip();

    if (_elapsed >= _Tuning.timeLimit) _finish();
  }

  /// Watch for the lead changing hands during the GOLD RUSH finale and punch a
  /// slow-mo + flash + popup on the decisive flip so the moment the board turns
  /// over reads as the climax it is.
  void _maybeAnnounceLeadFlip() {
    final leader = _leaderId();
    final prev = _lastLeaderId;
    _lastLeaderId = leader;
    if (!_inGoldRush || leader == null || prev == null || leader == prev) {
      return;
    }
    if (_flipCooldown > 0) return;
    final margin = _grid.fractionOf(leader) - _grid.fractionOf(prev);
    if (margin < _Tuning.leadFlipMinFrac) return;

    _flipCooldown = _Tuning.leadFlipCooldownSec;
    final color = _cursorOf(leader)?.color ?? const Color(0xFFFFFFFF);
    _juice.slowMo(
        dur: _Tuning.leadFlipSlowMoSec, scale: _Tuning.leadFlipSlowScale);
    _juice.flashScreen(color, strength: 0.4);
    _juice.shake.medium();
    final center = Offset(_lastSize.width / 2, _lastSize.height * 0.42);
    _juice.popup(center, 'LEAD FLIP!', color, size: 40);
  }

  /// Bots roam the SHARED canvas hunting the freshest contested cell and (when
  /// behind) raiding the leader's turf. They re-pick a goal on their reaction
  /// clock; when they ARRIVE at a goal they TAP. [BotProfile] accuracy decides
  /// chain discipline + aim. A warmup keeps them passive at the gun.
  void _driveBots(double dt) {
    final engaged = _elapsed >= _Tuning.botWarmupSec;
    for (final c in _cursors) {
      final clock = c.clock;
      if (clock == null) continue;
      if (!engaged) continue;
      if (c.botTapCooldown > 0) c.botTapCooldown -= dt;
      if (clock.tick(dt)) {
        clock.arm(ctx.botProfile, ctx.rng);
        _repickBotGoal(c);
      }
      _stepBotCursor(c, dt);
    }
  }

  /// Cadence-gated bot tap interval (seconds), scaled by accuracy from
  /// [_Tuning.botTapIntervalMax] (easy, slow) to [botTapIntervalMin] (hard, ≈ a
  /// skilled human). A small ±jitter keeps bots off a metronome so seeds vary.
  double _botTapInterval() {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final base = _Tuning.botTapIntervalMax +
        (_Tuning.botTapIntervalMin - _Tuning.botTapIntervalMax) * acc;
    final j = base * _Tuning.botTapIntervalJitter;
    return (base + ctx.rng.jitter(j)).clamp(0.1, 1.2);
  }

  /// Choose a fresh coverage goal for a bot on the SHARED canvas. A DISCIPLINED
  /// bot (accuracy ≥ [_Tuning.botChainAcc]) always heads for the best fresh/
  /// contested cell so it chains; a SLOPPY bot rolls
  /// [_Tuning.botSloppyRetapChance] to instead pick a spot near its OWN turf
  /// (breaking its chain on arrival) or a random point (a deliberate error), so
  /// it paints little. Aim jitter scaled by 1-accuracy keeps weak bots off the
  /// optimum.
  void _repickBotGoal(_Cursor c) {
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final disciplined = acc >= _Tuning.botChainAcc;
    Offset goal;

    if (ctx.rng.chance(ctx.botProfile.errorRate)) {
      // Deliberate error: drift anywhere on the shared arena.
      goal = Offset(ctx.rng.next(), ctx.rng.next());
    } else if (!disciplined && ctx.rng.chance(_Tuning.botSloppyRetapChance)) {
      // Sloppy: re-tap near its own turf, breaking its own chain (a cell it
      // already owns near the cursor, or home if it owns nothing yet).
      goal = _ownTurfSpot(c) ?? c.zone.center;
    } else {
      goal = _bestTargetSpot(c) ?? c.zone.center;
    }

    final jitter = _Tuning.botAimJitter * (1.0 - acc);
    if (jitter > 0) {
      goal = goal.translate(ctx.rng.jitter(jitter), ctx.rng.jitter(jitter));
    }
    c.botGoal = goal;
  }

  /// A spot on the bot's OWN turf (so a sloppy bot can waste a tap re-coating
  /// it, breaking its chain). Returns the centre of an owned cell near the
  /// cursor, or null if it owns nothing.
  Offset? _ownTurfSpot(_Cursor c) {
    Offset? best;
    var bestDist = double.infinity;
    for (var row = 0; row < _Tuning.rows; row += _Tuning.botSampleStride) {
      for (var col = 0; col < _Tuning.cols; col += _Tuning.botSampleStride) {
        if (_grid.ownerAt(col, row) != c.playerId) continue;
        final cx = (col + 0.5) / _Tuning.cols;
        final cy = (row + 0.5) / _Tuning.rows;
        final d = (Offset(cx, cy) - c.pos).distanceSquared;
        if (d < bestDist) {
          bestDist = d;
          best = Offset(cx, cy);
        }
      }
    }
    return best;
  }

  /// Pick the best cell on the WHOLE shared grid for bot [c] to head toward and
  /// chain on. Cells the bot already owns are skipped (re-coating breaks the
  /// chain), so bots chase FRESH ground. Empty cells are the staple target;
  /// rival cells are worth stealing. When BEHIND the leader, a raid roll
  /// (odds scaling with the gap) weights the LEADER's cells highest. A mild
  /// distance term keeps it sweeping outward. Returns null only if the bot
  /// already owns every cell.
  Offset? _bestTargetSpot(_Cursor c) {
    final leaderId = _leaderId();
    final behind = _coverageGapBehindLeader(c.playerId, leaderId);
    final raidT = (behind / _Tuning.botRaidRefGap).clamp(0.0, 1.0);
    final raiding = leaderId != null &&
        leaderId != c.playerId &&
        ctx.rng.chance(_Tuning.botRaidChanceMax * raidT);

    Offset? best;
    var bestScore = -1.0;
    for (var row = 0; row < _Tuning.rows; row += _Tuning.botSampleStride) {
      final cy = (row + 0.5) / _Tuning.rows;
      for (var col = 0; col < _Tuning.cols; col += _Tuning.botSampleStride) {
        final owner = _grid.ownerAt(col, row);
        if (owner == c.playerId) continue; // already mine — skip (breaks chain)
        var weight = owner == kEmptyCell ? 1.0 : 0.6;
        if (raiding && owner == leaderId) weight *= _Tuning.botLeaderCellWeight;
        final cx = (col + 0.5) / _Tuning.cols;
        final dist = (Offset(cx, cy) - c.pos).distance;
        // Prefer the NEAREST high-value cell (short hops keep the chain alive and
        // the cursor on a tight board-eating sweep); raids still bias toward the
        // leader's turf through [weight].
        final score = weight / (dist + _Tuning.botTargetDistBias);
        if (score > bestScore) {
          bestScore = score;
          best = Offset(cx, cy);
        }
      }
    }
    return best;
  }

  /// Id of the player currently owning the most cells, or null if nobody has
  /// painted yet (used to pick a raid target + drive the lead-flip cue).
  int? _leaderId() {
    int? leader;
    var bestCount = 0;
    for (final c in _cursors) {
      final n = _grid.coverageOf(c.playerId);
      if (n > bestCount) {
        bestCount = n;
        leader = c.playerId;
      }
    }
    return leader;
  }

  /// How far (coverage fraction) [playerId] trails [leaderId]; 0 if they ARE the
  /// leader or there is no leader yet.
  double _coverageGapBehindLeader(int playerId, int? leaderId) {
    if (leaderId == null || leaderId == playerId) return 0;
    final gap = _grid.fractionOf(leaderId) - _grid.fractionOf(playerId);
    return gap < 0 ? 0 : gap;
  }

  /// Move a bot's steering target toward its goal; when it ARRIVES it TAPS (only
  /// once its cadence cooldown has elapsed) and re-picks a fresh goal so it keeps
  /// hopping between fresh cells, building a chain. While the cooldown is still
  /// counting down it DWELLS on the arrived goal (no tap, no re-pick), so its tap
  /// rate is capped by [_botTapInterval] — NOT by travel speed.
  void _stepBotCursor(_Cursor c, double dt) {
    final to = c.botGoal - c.target;
    final step = _Tuning.botMoveSpeed * dt;
    final arrived = to.distance <= step || to.distance < 1e-4;
    if (!arrived) {
      c.target = c.clampToZone(c.target + to / to.distance * step);
      return;
    }
    c.target = c.botGoal;
    c.pos = c.botGoal; // snap so the tap lands exactly on the target cell
    if (c.botTapCooldown > 0) return; // cadence gate: dwell until the can is ready
    _botTap(c);
    c.botTapCooldown = _botTapInterval();
    _repickBotGoal(c);
  }

  /// A bot lays a tap on arrival once its cadence cooldown elapses. A SLOPPY
  /// (easy) bot still picks home-turf targets that break its own chain and taps
  /// lazily; a disciplined bot hops fresh and taps near a skilled human's cadence.
  /// We do NOT idle-wait a disciplined bot for ink — that starved it below a
  /// sloppy bot's output, inverting the difficulty dial.
  void _botTap(_Cursor c) => _tap(c);

  /// Score = covered cell count, then rank highest-first.
  void _finish() {
    if (status == MiniGameStatus.finished) return;
    for (final p in ctx.players) {
      setScore(p.id, _grid.coverageOf(p.id));
    }
    // Signature coverage-reveal beat on the winner's brush.
    final winnerId = _leaderId();
    final winnerColor = _leaderColor();
    final winnerPos = winnerId == null
        ? _lastSize.center(Offset.zero)
        : _toPixels(_cursorOf(winnerId)!.pos);
    _juice.bigMoment(winnerPos, winnerColor, banner: 'WINNER!');
    _juice.confetti(_lastSize, colors: [winnerColor]);
    if (winnerId != null) _cursorOf(winnerId)?.figure.victory();
    finishByScore();
  }

  /// The current leader's color for the win reveal, or white if nobody painted.
  Color _leaderColor() {
    final id = _leaderId();
    if (id == null) return const Color(0xFFFFFFFF);
    return _cursorOf(id)?.color ?? const Color(0xFFFFFFFF);
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    _juice.applyWorldTransform(canvas);

    PaintRenderer.drawBackground(canvas, size);
    _drawHomeCorners(canvas, size);
    _drawCoverage(canvas, size);
    _drawStamps(canvas, size);
    _drawCursors(canvas, size);
    _drawCoverageBars(canvas, size);

    _juice.render(canvas);
    canvas.restore();

    // Screen-space cinematic overlays (flash + WINNER! banner) after the world
    // transform is restored, so they are not shaken or zoomed.
    _juice.renderOverlay(canvas, size);
  }

  /// Faint player-tinted "home corner" washes (NOT walls): the canvas is shared
  /// and every brush roams it freely, so we only hint where each player starts.
  void _drawHomeCorners(Canvas canvas, Size size) {
    PaintRenderer.drawZoneBorders(canvas, size, [
      for (final c in _cursors) (rect: c.zone, color: c.color),
    ]);
  }

  /// Baked coverage under-layer (a soft tint per owned cell) so total territory
  /// reads clearly behind the crisp stamps.
  void _drawCoverage(Canvas canvas, Size size) {
    final colorById = <int, Color>{
      for (final p in ctx.players) p.id: Color(p.colorArgb),
    };
    PaintRenderer.drawCoverageTint(
      canvas,
      size,
      _Tuning.cols,
      _Tuning.rows,
      (col, row) {
        final owner = _grid.ownerAt(col, row);
        if (owner == kEmptyCell) return null;
        return colorById[owner];
      },
    );
  }

  /// The recent crisp blobs on top, oldest first so newer paint overlaps older.
  void _drawStamps(Canvas canvas, Size size) {
    if (_stamps.isEmpty) return;
    final minSide = math.min(size.width, size.height);
    for (final s in _stamps) {
      final center = _toPixelsIn(s.pos, size);
      final radiusPx = s.radius * minSide;
      final wet = (1.0 - s.age / _Tuning.sheenDrySec).clamp(0.0, 1.0);
      final age01 = (s.age / _Tuning.timeLimit).clamp(0.0, 1.0);
      PaintRenderer.drawSplat(
        canvas,
        center,
        radiusPx,
        s.color,
        seed: s.seed,
        wet: wet,
        age01: age01,
      );
    }
  }

  void _drawCursors(Canvas canvas, Size size) {
    for (final c in _cursors) {
      final pulse =
          c.flash <= 0 ? 0.0 : (c.flash / _Tuning.tapFlashSec).clamp(0.0, 1.0);
      final center = _toPixelsIn(c.pos, size);
      // The ring reads as an INK GAUGE; the chain counter + dud cue ride above.
      PaintRenderer.drawReticle(
        canvas,
        size,
        center,
        c.color,
        charge: c.charge,
        isRoller: c.isRoller,
        pulse: pulse,
        spraying: false,
        lowInk: c.ink < _Tuning.inkLowWarn,
      );
      // The painter mascot rides on top of the reticle, showing WHO is painting.
      PaintRenderer.drawMascot(
        canvas,
        size,
        center,
        c.figure,
        facingRight: c.facingRight,
      );
      // The UNMISSABLE chain counter / dud cue floats above the cursor.
      PaintRenderer.drawChainBadge(
        canvas,
        size,
        center,
        c.color,
        chain: c.chain,
        pulse: c.chainPulse.clamp(0.0, 1.0),
        broke: c.brokeChain && c.flash > 0,
        maxChain: _Tuning.chainMax,
      );
    }
  }

  /// Live coverage % bars; the current leader's bar glows.
  void _drawCoverageBars(Canvas canvas, Size size) {
    if (_cursors.isEmpty) return;
    var leaderId = _cursors.first.playerId;
    var leaderFrac = -1.0;
    for (final c in _cursors) {
      final f = _grid.fractionOf(c.playerId);
      if (f > leaderFrac) {
        leaderFrac = f;
        leaderId = c.playerId;
      }
    }
    final entries = <({Color color, double fraction, bool isLeader})>[
      for (final c in _cursors)
        (
          color: c.color,
          fraction: _grid.fractionOf(c.playerId),
          isLeader: c.playerId == leaderId && leaderFrac > 0,
        ),
    ];
    PaintRenderer.drawCoverageBars(canvas, size, entries);
  }

  // ── Small helpers ────────────────────────────────────────────────────────────

  _Cursor? _cursorOf(int id) {
    for (final c in _cursors) {
      if (c.playerId == id) return c;
    }
    return null;
  }

  Offset _toPixels(Offset norm) => _toPixelsIn(norm, _lastSize);

  Offset _toPixelsIn(Offset norm, Size size) =>
      Offset(norm.dx * size.width, norm.dy * size.height);
}
