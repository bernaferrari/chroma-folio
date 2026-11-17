import 'dart:ui' show ColorSpace;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/studio_cubit.dart';
import '../models/accessibility_utils.dart';
import '../models/color_spaces.dart';
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
        final chords = _buildHarmonyChords(active, state.activeSpace);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isShort = constraints.maxHeight < 520;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  title: 'Scale',
                  trailing: _CopyChip(
                    label: 'Tailwind',
                    onTap: () => copyWithFeedback(
                      context,
                      _tailwindScale(ramp),
                      label: 'Tailwind scale',
                    ),
                  ),
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
                  ),
                ),
                const SizedBox(height: 22),
                _SectionHeader(
                  title: 'Harmonies',
                  trailing: Text(
                    'Tap one to fill the palette',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: _HarmonyChordsGrid(
                    chords: chords,
                    onPourChord: (chord) {
                      HapticFeedback.lightImpact();
                      cubit.applyColorsToPalette(chord.colors);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _CopyPaletteBar(palette: state.palette),
              ],
            );
          },
        );
      },
    );
  }

  String _tailwindScale(
    List<({int token, Color color, double lightness})> ramp,
  ) {
    final entries = [
      for (final stop in ramp)
        "  '${stop.token}': '${StudioColor.fromColor(stop.color).hex}',",
    ].join('\n');
    return 'primary: {\n$entries\n}';
  }

  List<_HarmonyChord> _buildHarmonyChords(
    StudioColor active,
    ColorSpaceMode space,
  ) {
    final channels = active.channelsFor(space);
    final baseHue = channels[0].value;
    final saturation = channels[1].value;
    final lightness = channels[2].value.clamp(28.0, 74.0);

    StudioColor mix(double hueOffset, double tone, double intensity) =>
        StudioColor.fromSpace(
          space,
          hue: baseHue + hueOffset,
          saturationPct: saturation * intensity,
          lightnessPct: tone,
        );

    _HarmonyChord harmony(String title, double first, double second) =>
        _HarmonyChord(
          title: title,
          colors: [
            active,
            mix(first, lightness + 10, 0.72),
            mix(second, lightness - 4, 0.60),
            mix(second, 27, 0.35),
            mix(0, 42, 0.48),
            mix(0, 68, 0.40),
            mix(first, 83, 0.28),
            mix(0, 94, 0.16),
          ],
        );

    return [
      harmony('Analogous', 28, -28),
      harmony('Complementary', 180, 180),
      harmony('Triadic', 120, 240),
      harmony('Split complementary', 150, 210),
    ];
  }
}

class const _TonalRampRibbon({
  required final List<({int token, Color color, double lightness})> ramp,
  required final double activeLightness,
  required final ValueChanged<Color> onSelectStep,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var closestIdx = 0;
    var bestDiff = double.infinity;
    for (int i = 0; i < ramp.length; i++) {
      final diff = (ramp[i].lightness - activeLightness).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        closestIdx = i;
      }
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < ramp.length; i++)
            Expanded(
              child: _TonalBand(
                token: ramp[i].token,
                color: ramp[i].color,
                isClosest: i == closestIdx,
                onTap: () => onSelectStep(ramp[i].color),
              ),
            ),
        ],
      ),
    );
  }
}

class const _TonalBand({
  required final int token,
  required final Color color,
  required final bool isClosest,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ink = contrastingTextColor(color);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ColoredBox(
          color: color,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isClosest) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    '$token',
                    maxLines: 1,
                    style: studioMonoStyle(
                      context,
                      fontSize: 10.5,
                      fontWeight: isClosest ? FontWeight.w700 : FontWeight.w600,
                      color: ink.withValues(alpha: isClosest ? 0.98 : 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _HarmonyChord({
  required final String title,
  required final List<StudioColor> colors,
});

class const _HarmonyChordsGrid({
  required final List<_HarmonyChord> chords,
  required final ValueChanged<_HarmonyChord> onPourChord,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _HarmonyChordCard(
                  chord: chords[0],
                  onTap: () => onPourChord(chords[0]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HarmonyChordCard(
                  chord: chords[1],
                  onTap: () => onPourChord(chords[1]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _HarmonyChordCard(
                  chord: chords[2],
                  onTap: () => onPourChord(chords[2]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HarmonyChordCard(
                  chord: chords[3],
                  onTap: () => onPourChord(chords[3]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class const _HarmonyChordCard({
  required final _HarmonyChord chord,
  required final VoidCallback onTap,
}) extends StatefulWidget {
  @override
  State<_HarmonyChordCard> createState() => _HarmonyChordCardState();
}

class _HarmonyChordCardState extends State<_HarmonyChordCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chord = widget.chord;

    return Semantics(
      button: true,
      label: 'Fill the palette with ${chord.title} colours',
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
          child: AnimatedScale(
            scale: _pressed ? 0.975 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.onSurface.withValues(
                    alpha: _hovered ? 0.16 : 0.07,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    chord.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: studioDisplayStyle(context, fontSize: 21, height: 1),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: ColoredBox(
                                    color: chord.colors[0].color,
                                  ),
                                ),
                                for (final swatch
                                    in chord.colors.skip(1).take(2))
                                  Expanded(
                                    child: ColoredBox(color: swatch.color),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final swatch in chord.colors.skip(3))
                                  Expanded(
                                    child: ColoredBox(color: swatch.color),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _SectionHeader({
  required final String title,
  required final Widget trailing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: SizedBox(
        height: 32,
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

/// One quiet row offering the palette in each code format.
class const _CopyPaletteBar({required final List<StudioColor> palette})
    extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Copy palette',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          _CopyChip(
            label: 'Hex',
            onTap: () => copyWithFeedback(context, _hexList, label: 'hex'),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<bool>(
            tooltip: 'Copy CSS palette',
            onSelected: (displayP3) => copyWithFeedback(
              context,
              _cssVariables(displayP3: displayP3),
              label: displayP3 ? 'Display P3 CSS' : 'OKLCH CSS',
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(value: false, child: Text('OKLCH')),
              PopupMenuItem(value: true, child: Text('Display P3')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('CSS'),
            ),
          ),
          const SizedBox(width: 6),
          _CopyChip(
            label: 'Flutter',
            onTap: () => copyWithFeedback(
              context,
              _flutterList,
              label: 'Flutter colours',
            ),
          ),
        ],
      ),
    );
  }
}

class const _CopyChip({
  required final String label,
  required final VoidCallback onTap,
}) extends StatefulWidget {
  @override
  State<_CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<_CopyChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Copy ${widget.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: _hovered ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.copy_rounded,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
