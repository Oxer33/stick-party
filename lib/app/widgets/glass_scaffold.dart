/// A consistent screen shell for every Stick Party screen: an animated
/// [MeshGradientBackground] at the root, a [SafeArea], an optional frosted top
/// bar (with a gradient-text title, leading + actions), then the body.
///
/// The body can be scrollable (default) or fixed. The whole thing is the single
/// wrapper screens use so the glass look is uniform without each screen
/// re-wiring a Scaffold/AppBar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import 'glass_kit.dart';
import 'glass_tokens.dart';
import 'mesh_background.dart';

/// Height of the frosted top bar's content row.
const double _kTopBarHeight = 56;

/// Glass screen scaffold. Background is transparent (the mesh provides it).
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    this.title,
    this.leading,
    this.actions,
    required this.body,
    this.scroll = true,
    this.padding = const EdgeInsets.all(GlassTokens.pagePadding),
    this.showBack = true,
  });

  /// Optional top-bar title (rendered as gradient text). When null and there is
  /// no [leading]/[actions]/back button, no top bar is shown.
  final String? title;

  /// Optional leading widget (overrides the automatic back button).
  final Widget? leading;

  /// Optional trailing actions in the top bar.
  final List<Widget>? actions;

  /// Screen content below the top bar.
  final Widget body;

  /// When true the body is wrapped in a scroll view with [padding].
  final bool scroll;

  /// Padding applied to the body.
  final EdgeInsets padding;

  /// Show an automatic back button when the route can pop and no [leading] is
  /// provided. Set false on root-style screens (e.g. home).
  final bool showBack;

  bool get _hasTopBar =>
      title != null ||
      leading != null ||
      (actions != null && actions!.isNotEmpty) ||
      showBack;

  @override
  Widget build(BuildContext context) {
    final Widget content = scroll
        ? SingleChildScrollView(padding: padding, child: body)
        : Padding(padding: padding, child: body);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MeshGradientBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              if (_hasTopBar)
                _GlassTopBar(
                  title: title,
                  leading: leading,
                  actions: actions,
                  showBack: showBack,
                ),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}

/// The frosted top bar: optional back/leading, gradient title, trailing actions.
class _GlassTopBar extends StatelessWidget {
  const _GlassTopBar({
    required this.title,
    required this.leading,
    required this.actions,
    required this.showBack,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final bool canPop = context.canPop();
    final Widget? lead = leading ??
        (showBack && canPop ? _BackButton(onTap: () => context.pop()) : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GlassTokens.pagePadding,
        GlassTokens.gapSmall,
        GlassTokens.pagePadding,
        0,
      ),
      child: SizedBox(
        height: _kTopBarHeight,
        child: Row(
          children: <Widget>[
            if (lead != null) ...<Widget>[
              lead,
              const SizedBox(width: GlassTokens.gapSmall),
            ],
            if (title != null)
              Expanded(
                child: gradientText(
                  title!,
                  style: GlassText.title,
                ),
              )
            else
              const Spacer(),
            if (actions != null)
              for (final Widget action in actions!) ...<Widget>[
                const SizedBox(width: GlassTokens.gapSmall),
                action,
              ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: GlassTokens.entrance).slideY(
          begin: -0.3,
          end: 0,
          curve: Curves.easeOutCubic,
          duration: GlassTokens.entrance,
        );
  }
}

/// A frosted circular back button used by the top bar.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassPanel(
        radius: GlassTokens.radiusSmall,
        blur: GlassTokens.blurChip,
        shadow: false,
        padding: const EdgeInsets.all(10),
        child: const Icon(
          Icons.arrow_back_ios_new,
          color: GlassColors.text,
          size: 18,
        ),
      ),
    );
  }
}
