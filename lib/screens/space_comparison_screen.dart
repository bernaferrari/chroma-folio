import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsluv/hsluv.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/studio_cubit.dart';
import '../models/color_spaces.dart';
import '../widgets/reel.dart';
import '../widgets/studio_theme.dart';

/// The same hue wheel through four colour spaces, spun together.
///
/// Every strip uses the same hue, saturation and lightness numbers, so how
/// evenly a strip reads shows how well its space keeps lightness steady
/// across hues. The strip of the active colour space is the one being picked
/// from: the colour in its lens is the active colour. Touching another strip
/// makes its space the active one.
class const SpaceComparisonScreen({super.key}) extends StatefulWidget {
  @override
  State<SpaceComparisonScreen> createState() => _SpaceComparisonScreenState();
}

class _SpaceComparisonScreenState extends State<SpaceComparisonScreen>
    with SingleTickerProviderStateMixin {
  static const _modes = <ColorSpaceMode>[
    ColorSpaceMode.hsluv,
    ColorSpaceMode.oklch,
    ColorSpaceMode.hct,
    ColorSpaceMode.hsl,
  ];
  static const double _hueStep = 20;
  static const double _bandsInView = 13;

  late final ReelMotion _motion;
  bool _pressed = false;

  /// The space whose strip is being picked from.
  ColorSpaceMode get _source {
    final active = context.read<StudioCubit>().state.activeSpace;
    return _modes.contains(active) ? active : _modes.first;
  }

  @override
  void initState() {
    super.initState();
    final cubit = context.read<StudioCubit>();
    _motion =
        ReelMotion(
            vsync: this,
            onStart: cubit.beginScrub,
            onChanged: _pickHue,
            onEnd: cubit.endScrub,
          )
          ..min = 0
          ..max = 360
          ..wraps = true
          ..step = _hueStep;
  }

  /// Picks the colour at [hue] on the strip being picked from.
  void _pickHue(double hue) {
    final cubit = context.read<StudioCubit>();
    final channels = cubit.state.activeColor.channelsFor(_source);
    cubit.setActiveColor(
      StudioColor.fromSpace(
        _source,
        hue: hue,
        saturationPct: channels[1].value,
        lightnessPct: channels[2].value,
      ),
      recordHistory: false,
    );
  }

  /// Makes [mode] the strip being picked from, taking the colour in its lens.
  void _pickFrom(ColorSpaceMode mode) {
    if (mode == _source) return;
    final cubit = context.read<StudioCubit>();
    final channels = cubit.state.activeColor.channelsFor(_source);
    cubit.setSpaceMode(mode);
    cubit.setActiveColor(
      StudioColor.fromSpace(
        mode,
        hue: _motion.position,
        saturationPct: channels[1].value,
        lightnessPct: channels[2].value,
      ),
      recordHistory: !_motion.isEngaged,
    );
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StudioCubit, StudioState>(
      buildWhen: (prev, next) =>
          prev.activeColor != next.activeColor ||
          prev.activeSpace != next.activeSpace,
      builder: (context, state) {
        final source = _source;
        final channels = state.activeColor.channelsFor(source);
        final hue = channels[0].value;
        final saturation = channels[1].value;
        final lightness = channels[2].value;
        _motion.sync(hue);

        Color sample(ColorSpaceMode mode, double atHue) => sampleAcrossSpace(
          mode,
          hue: atHue,
          saturationPct: saturation,
          lightnessPct: lightness,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final bandLength = (constraints.maxWidth / _bandsInView).clamp(
              40.0,
              84.0,
            );
            _motion.pixelsPerUnit = bandLength / _hueStep;

            return ReelSurface(
              key: const ValueKey<String>('spectrum_gesture_canvas'),
              motion: _motion,
              axis: Axis.horizontal,
              onPressedChanged: (pressed) => setState(() => _pressed = pressed),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final mode in _modes) ...[
                    if (mode != _modes.first) const SizedBox(height: 14),
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) => _pickFrom(mode),
                        onPointerSignal: (_) => _pickFrom(mode),
                        child: _SpectrumStrip(
                          mode: mode,
                          motion: _motion,
                          bandLength: bandLength,
                          picking: mode == source,
                          pressed: _pressed && mode == source,
                          paletteKey: (saturation, lightness),
                          colorAt: (atHue) => sample(mode, atHue),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class const _SpectrumStrip({
  required final ColorSpaceMode mode,
  required final ReelMotion motion,
  required final double bandLength,

  /// Whether the colour in this strip's lens is the active colour.
  required final bool picking,
  required final bool pressed,
  required final Object paletteKey,
  required final Color Function(double hue) colorAt,
}) extends StatelessWidget {
  static const double _lensOverhang = 7;
  static const double _lensInset = 7;

  /// Darkest and lightest perceived lightness around the whole strip.
  (int, int) _lightnessRange() {
    var darkest = 100;
    var lightest = 0;
    for (var hue = 0.0; hue < 360; hue += motion.step) {
      final perceived = Hsluv.yToL(colorAt(hue).computeLuminance()).round();
      darkest = math.min(darkest, perceived);
      lightest = math.max(lightest, perceived);
    }
    return (darkest, lightest);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (darkest, lightest) = _lightnessRange();
    final range = darkest == lightest ? '$darkest' : '$darkest to $lightest';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                mode.label,
                style: studioDisplayStyle(
                  context,
                  fontSize: 24,
                  height: 1.0,
                  color: picking ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                'lightness $range',
                style: studioMonoStyle(
                  context,
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: ReelStripPainter(
                      motion: motion,
                      axis: Axis.horizontal,
                      paletteKey: (mode, paletteKey, bandLength),
                      colorAt: colorAt,
                    ),
                  ),
                ),
                Positioned(
                  top: _lensInset,
                  bottom: _lensInset,
                  width: bandLength + _lensOverhang * 2,
                  child: ListenableBuilder(
                    listenable: motion,
                    builder: (context, _) => ReelLens(
                      color: colorAt(motion.position),
                      pressed: pressed,
                      quiet: !picking,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
