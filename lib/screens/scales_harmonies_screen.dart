import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/studio_cubit.dart';
import '../models/accessibility_utils.dart';
import '../models/color_spaces.dart';
import '../widgets/studio_theme.dart';

/// What the picked colour can become: its tonal scale and four harmonies
/// that can replace the palette, each ready to copy as code.
class ScalesHarmoniesScreen extends StatelessWidget {
  const ScalesHarmoniesScreen({super.key});

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
    final baseSat = math.max(active.hsluv.saturation, 58.0).clamp(0.0, 96.0);
    final baseLight = channels[2].value.clamp(28.0, 74.0);

    List<StudioColor> sampleChord(
      List<double> hueOffsets,
      List<double> lightOffsets,
      List<double> satScales,
    ) {
      return [
        for (int i = 0; i < 8; i++)
          StudioColor.fromColor(
            sampleAcrossSpace(
              space,
              hue: baseHue + hueOffsets[i],
              saturationPct: (baseSat * satScales[i]).clamp(14.0, 98.0),
              lightnessPct: (baseLight + lightOffsets[i]).clamp(12.0, 92.0),
            ),
          ),
      ];
    }

    return [
      _HarmonyChord(
        title: 'Analogous',
        angleLabel: '±22°',
        colors: sampleChord(
          const [0, 22, 44, -22, -44, 14, -14, 30],
          const [0, 8, -10, 10, -8, 20, -18, 26],
          const [1.0, 0.95, 0.92, 0.96, 0.88, 0.65, 0.78, 0.42],
        ),
      ),
      _HarmonyChord(
        title: 'Complementary',
        angleLabel: '180°',
        colors: sampleChord(
          const [0, 180, 14, 194, -14, 166, 0, 180],
          const [0, 0, 14, -12, -14, 16, 28, -22],
          const [1.0, 0.96, 0.85, 0.92, 0.88, 0.82, 0.42, 0.76],
        ),
      ),
      _HarmonyChord(
        title: 'Triadic',
        angleLabel: '120°',
        colors: sampleChord(
          const [0, 120, 240, 18, 138, 258, 0, 240],
          const [0, 4, -4, 16, -14, 14, 28, -24],
          const [1.0, 0.94, 0.94, 0.82, 0.85, 0.8, 0.4, 0.75],
        ),
      ),
      _HarmonyChord(
        title: 'Split',
        angleLabel: '150° · 210°',
        colors: sampleChord(
          const [0, 150, 210, 12, 162, 198, 0, 180],
          const [0, 6, -6, 16, -14, 14, 26, -24],
          const [1.0, 0.94, 0.94, 0.84, 0.86, 0.84, 0.42, 0.72],
        ),
      ),
    ];
  }
}

class _TonalRampRibbon extends StatelessWidget {
  const _TonalRampRibbon({
    required this.ramp,
    required this.activeLightness,
    required this.onSelectStep,
  });

  final List<({int token, Color color, double lightness})> ramp;
  final double activeLightness;
  final ValueChanged<Color> onSelectStep;

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

class _TonalBand extends StatelessWidget {
  const _TonalBand({
    required this.token,
    required this.color,
    required this.isClosest,
    required this.onTap,
  });

  final int token;
  final Color color;
  final bool isClosest;
  final VoidCallback onTap;

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

class _HarmonyChord {
  const _HarmonyChord({
    required this.title,
    required this.angleLabel,
    required this.colors,
  });

  final String title;
  final String angleLabel;
  final List<StudioColor> colors;
}

class _HarmonyChordsGrid extends StatelessWidget {
  const _HarmonyChordsGrid({required this.chords, required this.onPourChord});

  final List<_HarmonyChord> chords;
  final ValueChanged<_HarmonyChord> onPourChord;

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

class _HarmonyChordCard extends StatefulWidget {
  const _HarmonyChordCard({required this.chord, required this.onTap});

  final _HarmonyChord chord;
  final VoidCallback onTap;

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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          chord.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: studioDisplayStyle(
                            context,
                            fontSize: 22,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        chord.angleLabel,
                        maxLines: 1,
                        style: studioMonoStyle(
                          context,
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final swatch in chord.colors)
                            Expanded(child: ColoredBox(color: swatch.color)),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

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
class _CopyPaletteBar extends StatelessWidget {
  const _CopyPaletteBar({required this.palette});

  final List<StudioColor> palette;

  String get _hexList => palette.map((c) => c.hex).join(', ');

  String get _cssVariables {
    final lines = [
      for (int i = 0; i < palette.length; i++)
        '  --color-${i + 1}: ${palette[i].oklchDisplay};',
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
          _CopyChip(
            label: 'CSS',
            onTap: () => copyWithFeedback(
              context,
              _cssVariables,
              label: 'CSS variables',
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

class _CopyChip extends StatefulWidget {
  const _CopyChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

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
