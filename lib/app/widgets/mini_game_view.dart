/// The gameplay runner: hosts one [MiniGame], drives its frame loop, routes
/// multitouch input into per-player zones, and paints it efficiently.
///
/// Pure widget — it talks to the engine through [MiniGame]/[MiniGameContext]
/// only and never imports concrete games (it builds them via the registry).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/rng.dart';
import '../../engine/bots.dart';
import '../../engine/input_zones.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../engine/registry.dart';
import 'glass_tokens.dart';
import 'start_cue_overlay.dart';

/// Tuning for the runner shell (no magic numbers at call sites).
class _RunnerTune {
  _RunnerTune._();

  /// Seconds the "3..2..1..GO!" overlay holds before play starts. Input and
  /// `update` are suppressed during this window.
  static const double countdownSec = 2.8;

  /// How long "GO!" lingers after the count reaches zero (part of countdownSec).
  static const double goFlashSec = 0.8;

  /// Maximum simulated step per frame (caps physics blow-ups after a stall).
  static const double maxDt = 1 / 30;

  /// HUD badge corner radius.
  static const double badgeRadius = 10;

  /// Half-width of a HUD badge (used for horizontal centering).
  static const double badgeHalfWidth = 90;
}

/// Drives a single [MiniGame] round to completion.
class MiniGameView extends StatefulWidget {
  const MiniGameView({
    super.key,
    required this.gameId,
    required this.players,
    required this.difficulty,
    required this.onFinish,
    this.onQuit,
    this.showInputHints = true,
    this.seed,
  });

  /// Registry id of the game to run.
  final String gameId;

  /// Roster (slots + mode) for this round.
  final PlayerManager players;

  /// Bot skill tier for all bot slots.
  final BotDifficulty difficulty;

  /// Called exactly once when the round finishes, with the final result.
  final void Function(WinResult result) onFinish;

  /// Optional quit handler for the in-game corner button. Defaults to nothing.
  final VoidCallback? onQuit;

  /// Show per-zone input hints (TAP/HOLD/MASH) during the countdown.
  final bool showInputHints;

  /// Deterministic seed (tests pass a fixed value; play passes null).
  final int? seed;

  @override
  State<MiniGameView> createState() => _MiniGameViewState();
}

class _MiniGameViewState extends State<MiniGameView>
    with SingleTickerProviderStateMixin {
  /// The live game. Rebuilt whenever the play-area size first becomes known.
  MiniGame? _game;
  late MiniGameMeta _meta;
  ZoneLayout _zones = ZoneLayout.forPlayers(1);
  Size _arena = Size.zero;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  bool _hasLast = false;

  double _countdown = _RunnerTune.countdownSec;
  bool _finished = false;

  /// Repaint signal for the CustomPaint — bumped each frame so we never call
  /// setState on the whole widget for the canvas.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  /// Drives countdown / HUD text (rebuilds only the lightweight overlay).
  final ValueNotifier<int> _hudTick = ValueNotifier<int>(0);

  /// Active pointers → the player zone they landed in (for move/up routing).
  final Map<int, int> _pointerToPlayer = <int, int>{};

  @override
  void initState() {
    super.initState();
    _meta = createMiniGame(widget.gameId).meta;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _game?.dispose();
    _frame.dispose();
    _hudTick.dispose();
    super.dispose();
  }

  /// (Re)build the game once we know the real play-area [size].
  void _ensureGame(Size size) {
    if (_game != null && size == _arena) return;
    _game?.dispose();
    _arena = size;
    _zones =
        ZoneLayout.forPlayers(widget.players.count, mode: widget.players.mode);
    final MiniGameContext ctx = MiniGameContext(
      players: widget.players.slots,
      arena: size,
      rng: SeededRng(widget.seed),
      zones: _zones,
      mode: widget.players.mode,
      difficulty: widget.difficulty,
    );
    final MiniGame game = createMiniGame(widget.gameId)..init(ctx);
    _game = game;
    _meta = game.meta;
    _pointerToPlayer.clear();
  }

  bool get _countdownDone => _countdown <= 0;

  void _onTick(Duration now) {
    if (!mounted) return;
    if (!_hasLast) {
      _lastTick = now;
      _hasLast = true;
      return;
    }
    double dt =
        (now - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = now;
    if (dt <= 0) return;
    if (dt > _RunnerTune.maxDt) dt = _RunnerTune.maxDt;

    final MiniGame? game = _game;
    if (game == null) {
      // Size not measured yet; just paint so LayoutBuilder can run.
      _frame.value++;
      return;
    }

    if (!_countdownDone) {
      _countdown -= dt;
      _hudTick.value++; // refresh the count overlay
      _frame.value++; // keep painting the (static) field underneath
      return;
    }

    if (!_finished) {
      _feedHeldPointers(dt);
      game.update(dt);
      final WinResult? result = game.winResult;
      if (result != null && game.status == MiniGameStatus.finished) {
        _finished = true;
        _ticker?.stop();
        widget.onFinish(result);
      }
    }
    _frame.value++;
    _hudTick.value++; // refresh live scores
  }

  /// Synthesizes per-frame [InputPhase.holdTick] events for any pointer still
  /// pressed, so hold/charge games keep charging without extra move events.
  void _feedHeldPointers(double dt) {
    final MiniGame? game = _game;
    if (game == null || _pointerToPlayer.isEmpty) return;
    _pointerToPlayer.forEach((int _, int playerId) {
      game.onInput(PlayerInput(
        playerId: playerId,
        phase: InputPhase.holdTick,
        dt: dt,
      ));
    });
  }

  Offset _norm(Offset local) {
    if (_arena.width <= 0 || _arena.height <= 0) return Offset.zero;
    return Offset(
      (local.dx / _arena.width).clamp(0.0, 1.0),
      (local.dy / _arena.height).clamp(0.0, 1.0),
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    final MiniGame? game = _game;
    if (game == null || !_countdownDone || _finished) return;
    final Offset norm = _norm(e.localPosition);
    final int? id = _zones.playerAt(norm);
    if (id == null) return;
    _pointerToPlayer[e.pointer] = id;
    game.onInput(
        PlayerInput(playerId: id, phase: InputPhase.down, normPos: norm));
  }

  void _onPointerMove(PointerMoveEvent e) {
    final MiniGame? game = _game;
    if (game == null || !_countdownDone || _finished) return;
    final int? id = _pointerToPlayer[e.pointer];
    if (id == null) return;
    final Offset norm = _norm(e.localPosition);
    // A move is a hold sample at the new position (games that track drag read
    // normPos; pure tappers ignore holdTick).
    game.onInput(PlayerInput(
      playerId: id,
      phase: InputPhase.holdTick,
      normPos: norm,
    ));
  }

  void _onPointerUp(PointerEvent e) {
    final MiniGame? game = _game;
    final int? id = _pointerToPlayer.remove(e.pointer);
    if (game == null || id == null || !_countdownDone || _finished) return;
    final Offset norm = _norm(e.localPosition);
    game.onInput(PlayerInput(playerId: id, phase: InputPhase.up, normPos: norm));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.width > 0 && size.height > 0) {
          _ensureGame(size);
        }
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: GlassColors.base),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _GamePainter(
                    gameRef: () => _game,
                    repaint: _frame,
                  ),
                  size: size,
                ),
              ),
              _ZoneDividers(zones: _zones),
              _HudLayer(
                hudTick: _hudTick,
                zones: _zones,
                players: widget.players,
                meta: _meta,
                gameRef: () => _game,
                showHints: widget.showInputHints,
                showHintsNow: () => !_countdownDone,
              ),
              if (widget.showInputHints)
                StartCueOverlay(
                  hudTick: _hudTick,
                  zones: _zones,
                  players: widget.players,
                  inputHint: _meta.inputHint,
                  remaining: () => _countdown,
                  total: _RunnerTune.countdownSec,
                  showNow: () => !_countdownDone,
                ),
              _CountdownOverlay(
                hudTick: _hudTick,
                remaining: () => _countdown,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: _QuitButton(onQuit: widget.onQuit),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// CustomPainter that defers to the live game's [MiniGame.render].
class _GamePainter extends CustomPainter {
  _GamePainter({required this.gameRef, required Listenable repaint})
      : super(repaint: repaint);

  final MiniGame? Function() gameRef;

  @override
  void paint(Canvas canvas, Size size) {
    final MiniGame? game = gameRef();
    if (game == null) return;
    game.render(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => false;
}

/// Faint lines along the zone boundaries so players see their slice of screen.
class _ZoneDividers extends StatelessWidget {
  const _ZoneDividers({required this.zones});

  final ZoneLayout zones;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _DividerPainter(zones),
      ),
    );
  }
}

class _DividerPainter extends CustomPainter {
  _DividerPainter(this.zones);

  final ZoneLayout zones;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = GlassColors.textMuted.withValues(alpha: 0.18)
      ..strokeWidth = 1.5;
    // Draw each zone's edges; shared edges are de-duplicated by [drawn].
    final Set<String> drawn = <String>{};
    for (final PlayerZone z in zones.zones) {
      final Rect r = Rect.fromLTRB(
        z.normRect.left * size.width,
        z.normRect.top * size.height,
        z.normRect.right * size.width,
        z.normRect.bottom * size.height,
      );
      _maybeLine(canvas, p, drawn, r.topLeft, r.topRight);
      _maybeLine(canvas, p, drawn, r.topRight, r.bottomRight);
      _maybeLine(canvas, p, drawn, r.bottomLeft, r.bottomRight);
      _maybeLine(canvas, p, drawn, r.topLeft, r.bottomLeft);
    }
  }

  void _maybeLine(
    Canvas canvas,
    Paint p,
    Set<String> drawn,
    Offset a,
    Offset b,
  ) {
    final String key =
        '${a.dx.round()},${a.dy.round()}-${b.dx.round()},${b.dy.round()}';
    if (!drawn.add(key)) return;
    canvas.drawLine(a, b, p);
  }

  @override
  bool shouldRepaint(covariant _DividerPainter oldDelegate) =>
      oldDelegate.zones != zones;
}

/// Per-player HUD badges (color + name + live score + optional input hint),
/// each rotated to face its player.
class _HudLayer extends StatelessWidget {
  const _HudLayer({
    required this.hudTick,
    required this.zones,
    required this.players,
    required this.meta,
    required this.gameRef,
    required this.showHints,
    required this.showHintsNow,
  });

  final ValueNotifier<int> hudTick;
  final ZoneLayout zones;
  final PlayerManager players;
  final MiniGameMeta meta;
  final MiniGame? Function() gameRef;
  final bool showHints;
  final bool Function() showHintsNow;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth;
          final double h = constraints.maxHeight;
          return Stack(
            children: <Widget>[
              for (final PlayerZone zone in zones.zones)
                _badgeFor(context, zone, w, h),
            ],
          );
        },
      ),
    );
  }

  Widget _badgeFor(BuildContext context, PlayerZone zone, double w, double h) {
    final PlayerSlot? slot = _slotForZone(zone.playerId);
    if (slot == null) return const SizedBox.shrink();

    // Anchor near the player's outward edge: for flipped zones (rot 2) the
    // outward edge is the top; otherwise the bottom.
    final bool flipped = zone.rotationQuarters % 4 == 2;
    final Rect r = Rect.fromLTRB(
      zone.normRect.left * w,
      zone.normRect.top * h,
      zone.normRect.right * w,
      zone.normRect.bottom * h,
    );
    final double cx = r.center.dx;
    final double anchorY = flipped ? r.top + 10 : r.bottom - 54;

    return Positioned(
      left: cx - _RunnerTune.badgeHalfWidth,
      top: anchorY,
      width: _RunnerTune.badgeHalfWidth * 2,
      child: Align(
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: zone.rotationQuarters * math.pi / 2,
          child: ValueListenableBuilder<int>(
            valueListenable: hudTick,
            builder: (BuildContext context, int _, Widget? _) {
              final MiniGame? game = gameRef();
              final num score = game?.scores.of(slot.id) ?? 0;
              return _PlayerBadge(
                slot: slot,
                score: score,
                hint: meta.inputHint,
                showHint: showHints && showHintsNow(),
              );
            },
          ),
        ),
      ),
    );
  }

  PlayerSlot? _slotForZone(int playerId) {
    for (final PlayerSlot s in players.slots) {
      if (s.id == playerId) return s;
    }
    return null;
  }
}

class _PlayerBadge extends StatelessWidget {
  const _PlayerBadge({
    required this.slot,
    required this.score,
    required this.hint,
    required this.showHint,
  });

  final PlayerSlot slot;
  final num score;
  final String hint;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(slot.colorArgb);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: GlassColors.base.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(_RunnerTune.badgeRadius),
            border: Border.all(color: color.withValues(alpha: 0.9), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                slot.name,
                style: const TextStyle(
                  color: GlassColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${score.round()}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        if (showHint) ...<Widget>[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              hint,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Center "3..2..1..GO!" overlay shown during the lead-in.
class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.hudTick, required this.remaining});

  final ValueNotifier<int> hudTick;
  final double Function() remaining;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<int>(
        valueListenable: hudTick,
        builder: (BuildContext context, int _, Widget? _) {
          final double rem = remaining();
          if (rem <= 0) return const SizedBox.shrink();
          final String label = _label(rem);
          final bool isGo = label == 'GO!';
          return Center(
            child: ClipOval(
              child: Container(
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isGo ? GlassColors.cyan : GlassColors.violet)
                      .withValues(alpha: 0.3),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: isGo ? 64 : 88,
                    fontWeight: FontWeight.w900,
                    color: isGo ? GlassColors.cyan : Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _label(double rem) {
    if (rem <= _RunnerTune.goFlashSec) return 'GO!';
    // Map the remaining (above the GO window) onto 3..1.
    final double counting = rem - _RunnerTune.goFlashSec;
    final double span = _RunnerTune.countdownSec - _RunnerTune.goFlashSec;
    final int n = (counting / span * 3).ceil().clamp(1, 3);
    return '$n';
  }
}

/// Small pause/quit button drawn in a corner.
class _QuitButton extends StatelessWidget {
  const _QuitButton({required this.onQuit});

  final VoidCallback? onQuit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (onQuit != null) {
          onQuit!();
        } else {
          Navigator.of(context).maybePop();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x99000000),
        ),
        child: const Icon(Icons.close, color: GlassColors.text, size: 22),
      ),
    );
  }
}
