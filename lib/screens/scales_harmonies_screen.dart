import 'dart:math' as math;
import 'dart:ui' show ColorSpace;

import 'package:flutter/foundation.dart' show listEquals;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/studio_cubit.dart';
import '../models/accessibility_utils.dart';
import '../models/color_spaces.dart';
import '../widgets/palette_poster.dart';
import '../widgets/studio_theme.dart';

/// What the picked colour can become: its tonal scale and four harmonies
/// that can replace the palette, each ready to copy as code.
class const ScalesHarmoniesScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StudioCubit, StudioState>(
      buildWhen: (prev, next) =>
          prev.palette != next.palette ||
          prev.selectedIndex != next.selectedIndex ||
          prev.activeSpace != next.activeSpace,
      builder: (context, state) {
        final cubit = context.read<StudioCubit>();
        final active = state.activeColor;
        final ramp = active.tonalRamp(state.activeSpace);
        final chords = _buildHarmonyChords(
          active,
          state.activeSpace,
          state.palette.length,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final isShort = constraints.maxHeight < 520;

            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  title: 'Scale',
                  trailing: _CopyMenu(palette: state.palette, ramp: ramp),
                ),
                SizedBox(
                  height: isShort ? 84 : 128,
                  child: _TonalRampRibbon(
                    ramp: ramp,
                    activeLightness: active
                        .channelsFor(state.activeSpace)[2]
                        .value,
                    onSelectStep: (color) {
                      HapticFeedback.selectionClick();
                      cubit.setActiveColor(StudioColor.fromColor(color));
                    },
                    onScrubStart: cubit.beginScrub,
                    onScrubStep: (color) {
                      HapticFeedback.selectionClick();
                      cubit.setActiveColor(
                        StudioColor.fromColor(color),
                        recordHistory: false,
                      );
                    },
                    onScrubEnd: cubit.endScrub,
                  ),
                ),
                const SizedBox(height: 22),
                _SectionHeader(
                  title: 'Harmonies',
                  trailing: TextButton.icon(
                    onPressed: () =>
                        _chooseStarterPalette(context, state.palette),
                    icon: const Icon(Icons.palette_outlined, size: 16),
                    label: const Text('Starter palettes', maxLines: 1),
                  ),
                ),
                Expanded(
                  child: _HarmonyChordsGrid(
                    chords: chords,
                    space: state.activeSpace,
                    onPourChord: (chord) {
                      HapticFeedback.lightImpact();
                      cubit.applyColorsToPalette(chord.colors);
                    },
                  ),
                ),
              ],
            );
            return CustomScrollView(
              slivers: [
                SliverFillRemaining(hasScrollBody: false, child: content),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _chooseStarterPalette(
    BuildContext context,
    List<StudioColor> current,
  ) async {
    final index = await showDialog<int>(
      context: context,
      builder: (_) => _StarterPaletteDialog(current: current),
    );
    if (!context.mounted || index == null) return;
    HapticFeedback.selectionClick();
    context.read<StudioCubit>().applyColorsToPalette(
      studioStarterPaletteAt(index),
      selectedIndex: 0,
    );
  }

  List<_HarmonyChord> _buildHarmonyChords(
    StudioColor active,
    ColorSpaceMode space,
    int count,
  ) {
    final channels = active.channelsFor(space);
    final baseHue = channels[0].value;
    final saturation = math.max(channels[1].value, 55.0);
    final partnerTone = channels[2].value.clamp(45.0, 68.0);

    StudioColor tint(double hue, double tone, double intensity) =>
        StudioColor.fromSpace(
          space,
          hue: hue,
          saturationPct: math.min(saturation * intensity, 100.0),
          lightnessPct: tone,
        );

    _HarmonyChord harmony(
      String title,
      List<double> offsets,
      PosterStyle style, {
      bool darkGround = false,
    }) {
      final first = baseHue + offsets.first;
      final second = baseHue + offsets.last;
      final twoHues = offsets.length == 1;
      final swatches = [
        active,
        tint(first, partnerTone, 1),
        tint(
          second,
          twoHues ? partnerTone + 22 : partnerTone + 6,
          twoHues ? 0.75 : 0.9,
        ),
        tint(first, 93, 0.3),
        tint(second, 24, 0.7),
        tint(baseHue, 80, 0.55),
        tint(baseHue, 30, 0.8),
        tint(second, 86, 0.4),
      ];
      return _HarmonyChord(
        title: title,
        hues: [baseHue, for (final offset in offsets) baseHue + offset],
        style: style,
        darkGround: darkGround,
        // Every colour comes from the harmony's own hues, so no two
        // harmonies share anything but the picked colour.
        colors: swatches.take(count).toList(),
        dots: [
          for (final swatch in swatches.take(offsets.length + 1)) swatch.color,
        ],
      );
    }

    return [
      harmony('Analogous', [-30, 30], PosterStyle.arches),
      harmony('Complementary', [180], PosterStyle.sun, darkGround: true),
      harmony('Triadic', [120, 240], PosterStyle.grid),
      harmony(
        'Split complementary',
        [150, 210],
        PosterStyle.overprint,
        darkGround: true,
      ),
    ];
  }
}

class const _StarterPaletteDialog({required final List<StudioColor> current})
    extends StatelessWidget {
  static const _posterStyles = {
    'Riso Club': PosterStyle.overprint,
    'Cutouts': PosterStyle.arches,
    'Neon Arcade': PosterStyle.sun,
    'Bauhaus': PosterStyle.grid,
    'Citrus Stand': PosterStyle.sun,
    'Bubblegum': PosterStyle.grid,
    'Wildflower': PosterStyle.overprint,
    'Deep Sea': PosterStyle.arches,
    'Matcha': PosterStyle.arches,
    'Harvest': PosterStyle.sun,
    'Signal': PosterStyle.grid,
    'Fjord': PosterStyle.overprint,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentHexes = current.map((c) => c.color.toARGB32()).toList();
    final shelves = <String, List<int>>{};
    for (final (index, starter) in studioStarterPalettes.indexed) {
      (shelves[starter.shelf] ??= []).add(index);
    }

    return Dialog(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Starter palettes',
                            style: studioDisplayStyle(
                              context,
                              fontSize: 30,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Each one replaces your palette. Undo brings yours back.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(4, 0, 12, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 14.0;
                      final width = constraints.maxWidth;
                      final columns = width >= 600 ? 4 : 2;
                      final tileWidth = (width - gap * (columns - 1)) / columns;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, MapEntry(key: shelf, value: indexes))
                              in shelves.entries.indexed) ...[
                            if (i > 0) const SizedBox(height: 22),
                            Text(
                              shelf.toUpperCase(),
                              style: studioMonoStyle(
                                context,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ).copyWith(letterSpacing: 1.4),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: gap,
                              runSpacing: 18,
                              children: [
                                for (final index in indexes)
                                  SizedBox(
                                    width: tileWidth,
                                    child: _starterCard(
                                      context,
                                      index,
                                      currentHexes,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _starterCard(BuildContext context, int index, List<int> current) {
    final starter = studioStarterPalettes[index];
    return _PosterCard(
      name: starter.name,
      selected: _matches(starter.colors, current),
      semanticLabel:
          'Use the ${starter.name} palette, ${starter.colors.length} colours',
      onTap: () => Navigator.of(context).pop(index),
      poster: PalettePoster(
        colors: starter.colors,
        background: starter.background,
        style:
            _posterStyles[starter.name] ??
            PosterStyle.values[index % PosterStyle.values.length],
      ),
    );
  }

  static bool _matches(List<Color> colors, List<int> current) =>
      colors.length == current.length &&
      colors.indexed.every((entry) => entry.$2.toARGB32() == current[entry.$1]);
}

/// A palette as a poster with its name underneath; no frame, so the colours
/// do the talking.
class const _PosterCard({
  required final String name,
  required final Widget poster,
  required final String semanticLabel,
  required final VoidCallback onTap,
  final bool selected = false,

  /// Shown after the name, unless the card is [selected].
  final Widget? trailing,

  /// Width over height of the poster; null fills the height the card gets.
  final double? aspectRatio = 1.5,
}) extends StatefulWidget {
  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  static const _radius = 18.0;
  static const _ringGap = 3.0;

  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = widget.selected
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: _hovered ? 0.14 : 0);
    final frame = AnimatedScale(
      scale: _pressed
          ? 0.97
          : _hovered
          ? 1.015
          : 1.0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(_ringGap),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius + _ringGap),
          border: Border.all(color: ring, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: widget.poster,
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.aspectRatio case final aspectRatio?)
                AspectRatio(aspectRatio: aspectRatio, child: frame)
              else
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 72),
                    child: frame,
                  ),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.name,
                          maxLines: 1,
                          style: studioDisplayStyle(
                            context,
                            fontSize: 19,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    if (widget.selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: scheme.onSurface,
                      )
                    else
                      ?widget.trailing,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tonal scale as a strip of paint, drawn like the palette tray: the
/// steps touch, except the picked one, which stands apart as its own chip.
///
/// Tapping a step picks it; sliding across the strip scrubs through the
/// steps as one undoable change.
class const _TonalRampRibbon({
  required final List<({int token, Color color, double lightness})> ramp,
  required final double activeLightness,
  required final ValueChanged<Color> onSelectStep,
  required final VoidCallback onScrubStart,
  required final ValueChanged<Color> onScrubStep,
  required final VoidCallback onScrubEnd,
}) extends StatefulWidget {
  @override
  State<_TonalRampRibbon> createState() => _TonalRampRibbonState();
}

class _TonalRampRibbonState extends State<_TonalRampRibbon> {
  static const Duration _glide = Duration(milliseconds: 220);

  int? _scrubbedIndex;

  int _indexAt(double dx, double width) {
    final fraction = (dx / width).clamp(0.0, 0.9999);
    return (fraction * widget.ramp.length).floor();
  }

  void _scrubTo(double dx, double width) {
    final index = _indexAt(dx, width);
    if (index == _scrubbedIndex) return;
    _scrubbedIndex = index;
    widget.onScrubStep(widget.ramp[index].color);
  }

  void _endScrub() {
    if (_scrubbedIndex == null) return;
    _scrubbedIndex = null;
    widget.onScrubEnd();
  }

  @override
  Widget build(BuildContext context) {
    final ramp = widget.ramp;
    var closestIdx = 0;
    var bestDiff = double.infinity;
    for (int i = 0; i < ramp.length; i++) {
      final diff = (ramp[i].lightness - widget.activeLightness).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        closestIdx = i;
      }
    }
    final glide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _glide;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final narrow = width / ramp.length < 52;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => widget.onSelectStep(
              ramp[_indexAt(details.localPosition.dx, width)].color,
            ),
            onHorizontalDragStart: (details) {
              widget.onScrubStart();
              _scrubbedIndex = closestIdx;
              _scrubTo(details.localPosition.dx, width);
            },
            onHorizontalDragUpdate: (details) =>
                _scrubTo(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) => _endScrub(),
            onHorizontalDragCancel: _endScrub,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < ramp.length; i++)
                  Expanded(
                    child: _TonalBand(
                      token: ramp[i].token,
                      color: ramp[i].color,
                      isClosest: i == closestIdx,
                      gapBefore:
                          i > 0 && (i == closestIdx || i - 1 == closestIdx),
                      gapAfter:
                          i < ramp.length - 1 &&
                          (i == closestIdx || i + 1 == closestIdx),
                      halfGap: narrow ? 2 : 3,
                      duration: glide,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One step of the tonal scale.
///
/// A gap opens on each side that borders the picked step, and the corners
/// beside a gap are rounded.
class const _TonalBand({
  required final int token,
  required final Color color,
  required final bool isClosest,
  required final bool gapBefore,
  required final bool gapAfter,
  required final double halfGap,
  required final Duration duration,
}) extends StatefulWidget {
  @override
  State<_TonalBand> createState() => _TonalBandState();
}

class _TonalBandState extends State<_TonalBand> {
  static const Radius _chipCorner = Radius.circular(16);
  static const Radius _neighbourCorner = Radius.circular(7);

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ink = contrastingTextColor(widget.color);
    final corner = widget.isClosest ? _chipCorner : _neighbourCorner;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.only(
          left: widget.gapBefore ? widget.halfGap : 0,
          right: widget.gapAfter ? widget.halfGap : 0,
        ),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.horizontal(
            left: widget.gapBefore || widget.isClosest ? corner : Radius.zero,
            right: widget.gapAfter || widget.isClosest ? corner : Radius.zero,
          ),
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedDefaultTextStyle(
            duration: widget.duration,
            style: studioMonoStyle(
              context,
              fontSize: 10.5,
              fontWeight: widget.isClosest ? FontWeight.w700 : FontWeight.w600,
              color: ink.withValues(
                alpha: widget.isClosest || _hovered ? 0.98 : 0.72,
              ),
            ),
            child: Text('${widget.token}', maxLines: 1),
          ),
        ),
      ),
    );
  }
}

class const _HarmonyChord({
  required final String title,
  required final List<StudioColor> colors,

  /// The picked hue first, then the hues the harmony adds to it.
  required final List<double> hues,
  required final PosterStyle style,

  /// The colour shown for each of [hues] on the hue ring.
  required final List<Color> dots,
  final bool darkGround = false,
}) {
  /// The poster leads with the partners, so the picked colour (already on
  /// screen everywhere else) is not the biggest shape.
  List<Color> get posterColors {
    final swatches = [for (final swatch in colors) swatch.color];
    if (swatches.length < 3) return swatches;
    return [swatches[1], swatches[2], swatches[0], ...swatches.skip(3)];
  }

  int posterBackground(List<Color> swatches) {
    var best = swatches.length - 1;
    for (var i = 1; i < swatches.length; i++) {
      final luminance = swatches[i].computeLuminance();
      final current = swatches[best].computeLuminance();
      if (darkGround ? luminance < current : luminance > current) best = i;
    }
    return best;
  }
}

class const _HarmonyChordsGrid({
  required final List<_HarmonyChord> chords,
  required final ColorSpaceMode space,
  required final ValueChanged<_HarmonyChord> onPourChord,
}) extends StatelessWidget {
  Widget _chordCard(_HarmonyChord chord) {
    final swatches = chord.posterColors;
    return _PosterCard(
      name: chord.title,
      aspectRatio: null,
      semanticLabel: 'Fill the palette with ${chord.title} colours',
      onTap: () => onPourChord(chord),
      trailing: _HueRing(space: space, hues: chord.hues, colors: chord.dots),
      poster: PalettePoster(
        colors: swatches,
        background: chord.posterBackground(swatches),
        style: chord.style,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _chordCard(chords[0])),
              const SizedBox(width: 14),
              Expanded(child: _chordCard(chords[1])),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _chordCard(chords[2])),
              const SizedBox(width: 14),
              Expanded(child: _chordCard(chords[3])),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where a harmony's hues sit on the colour wheel: a dot for each, the
/// picked hue ringed.
class const _HueRing({
  required final ColorSpaceMode space,
  required final List<double> hues,
  required final List<Color> colors,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 40,
        child: CustomPaint(
          painter: _HueRingPainter(
            space: space,
            hues: hues,
            colors: colors,
            ink: scheme.onSurface,
            paper: scheme.surface,
          ),
        ),
      ),
    );
  }
}

class _HueRingPainter({
  required final ColorSpaceMode space,
  required final List<double> hues,
  required final List<Color> colors,
  required final Color ink,
  required final Color paper,
}) extends CustomPainter {
  static const int _segments = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 6;
    Offset at(double hue) {
      final angle = hue * math.pi / 180;
      return centre + Offset(math.sin(angle), -math.cos(angle)) * radius;
    }

    final rim = Rect.fromCircle(center: centre, radius: radius);
    const sweep = 2 * math.pi / _segments;
    for (var i = 0; i < _segments; i++) {
      final hue = i * 360 / _segments;
      canvas.drawArc(
        rim,
        -math.pi / 2 + i * sweep - sweep / 2,
        sweep + 0.02,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = Color.lerp(
            paper,
            StudioColor.fromSpace(
              space,
              hue: hue,
              saturationPct: 80,
              lightnessPct: 66,
            ).color,
            0.7,
          )!,
      );
    }

    final chord = Path()..addPolygon([for (final hue in hues) at(hue)], true);
    canvas.drawPath(
      chord,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ink.withValues(alpha: 0.35),
    );

    for (final (i, hue) in hues.indexed.toList().reversed) {
      final picked = i == 0;
      final dot = at(hue);
      canvas
        ..drawCircle(dot, picked ? 6.5 : 5, Paint()..color = paper)
        ..drawCircle(dot, picked ? 4.8 : 3.8, Paint()..color = colors[i]);
      if (picked) {
        canvas.drawCircle(
          dot,
          6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HueRingPainter oldDelegate) =>
      oldDelegate.space != space ||
      oldDelegate.ink != ink ||
      oldDelegate.paper != paper ||
      !listEquals(oldDelegate.hues, hues) ||
      !listEquals(oldDelegate.colors, colors);
}

class const _SectionHeader({
  required final String title,
  required final Widget trailing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            Text(
              title,
              maxLines: 1,
              style: studioDisplayStyle(context, fontSize: 24, height: 1.0),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything the tab can hand over as code, behind one quiet menu: the
/// palette in each format, and the picked colour's scale.
class const _CopyMenu({
  required final List<StudioColor> palette,
  required final List<({int token, Color color, double lightness})> ramp,
}) extends StatelessWidget {
  String get _hexList => palette.map((c) => c.hex).join(', ');

  String _cssVariables({required bool displayP3}) {
    String format(StudioColor swatch) {
      if (!displayP3) return swatch.oklchDisplay;
      final p3 = swatch.color.withValues(colorSpace: ColorSpace.displayP3);
      final components = [
        p3.r,
        p3.g,
        p3.b,
      ].map((component) => component.clamp(0, 1).toStringAsFixed(6)).join(' ');
      return 'color(display-p3 $components)';
    }

    final lines = [
      for (int i = 0; i < palette.length; i++)
        '  --color-${i + 1}: ${format(palette[i])};',
    ].join('\n');
    return ':root {\n$lines\n}';
  }

  String get _flutterList {
    final entries = [
      for (final c in palette) '  Color(0xFF${c.hex.substring(1)}),',
    ].join('\n');
    return 'const palette = <Color>[\n$entries\n];';
  }

  String get _tailwindScale {
    final entries = [
      for (final stop in ramp)
        "  '${stop.token}': '${StudioColor.fromColor(stop.color).hex}',",
    ].join('\n');
    return 'primary: {\n$entries\n}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sampleStyle = studioMonoStyle(
      context,
      fontSize: 11.5,
      color: scheme.onSurfaceVariant,
    );

    Widget group(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        label.toUpperCase(),
        style: studioMonoStyle(
          context,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ).copyWith(letterSpacing: 1.4),
      ),
    );

    Widget format(String name, String sample, String Function() code) =>
        MenuItemButton(
          onPressed: () => copyWithFeedback(context, code(), label: name),
          trailingIcon: Text(sample, style: sampleStyle),
          child: SizedBox(width: 132, child: Text(name)),
        );

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        group('Palette'),
        format('Hex', palette.first.hex, () => _hexList),
        format('CSS · OKLCH', 'oklch()', () => _cssVariables(displayP3: false)),
        format(
          'CSS · Display P3',
          'color()',
          () => _cssVariables(displayP3: true),
        ),
        format('Flutter', 'Color()', () => _flutterList),
        const Divider(height: 13, indent: 14, endIndent: 14),
        group('Scale'),
        format('Tailwind', '50 – 950', () => _tailwindScale),
      ],
      builder: (context, controller, _) => TextButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.copy_rounded, size: 16),
        label: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Copy', maxLines: 1),
            SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}
