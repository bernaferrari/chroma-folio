import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:hsluv/hsluv.dart';
import 'package:hsluv/hsluvcolor.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

/// Converts sRGB to HSLuv without rounding the editable channels.
HSLuvColor hsluvFromColor(Color color) {
  final channels = Hsluv.rgbToHsluv([
    color.r.clamp(0.0, 1.0),
    color.g.clamp(0.0, 1.0),
    color.b.clamp(0.0, 1.0),
  ]);
  return HSLuvColor.fromHSL(
    channels[0].clamp(0.0, 360.0),
    channels[1].clamp(0.0, 100.0),
    channels[2].clamp(0.0, 100.0),
  );
}

/// Supported color spaces in the Perceptual Color Studio.
enum ColorSpaceMode {
  hsluv,
  oklch,
  hct,
  hsl,
  hsv;

  String get label => switch (this) {
    ColorSpaceMode.hsluv => 'HSLuv',
    ColorSpaceMode.oklch => 'OKLCH',
    ColorSpaceMode.hct => 'HCT',
    ColorSpaceMode.hsl => 'HSL',
    ColorSpaceMode.hsv => 'HSV',
  };

  String get subtitle => switch (this) {
    ColorSpaceMode.hsluv => 'CIELUV perceptual, gamut-normalized S',
    ColorSpaceMode.oklch => 'CSS Color 4 perceptual Oklab polar',
    ColorSpaceMode.hct => 'Material 3 CAM16 + L* tone space',
    ColorSpaceMode.hsl => 'Legacy cylindrical sRGB (non-uniform)',
    ColorSpaceMode.hsv => 'Legacy hexcone sRGB (non-uniform)',
  };

  bool get isPerceptual =>
      this == ColorSpaceMode.hsluv ||
      this == ColorSpaceMode.oklch ||
      this == ColorSpaceMode.hct;

  List<String> get channelNames => switch (this) {
    ColorSpaceMode.hsluv => const ['Hue', 'Saturation', 'Lightness'],
    ColorSpaceMode.oklch => const ['Hue', 'Chroma %', 'Lightness'],
    ColorSpaceMode.hct => const ['Hue', 'Chroma', 'Tone'],
    ColorSpaceMode.hsl => const ['Hue', 'Saturation', 'Lightness'],
    ColorSpaceMode.hsv => const ['Hue', 'Saturation', 'Value'],
  };

  List<String> get channelShortNames => switch (this) {
    ColorSpaceMode.hsluv => const ['H', 'S', 'L'],
    ColorSpaceMode.oklch => const ['h', 'C', 'L'],
    ColorSpaceMode.hct => const ['H', 'C', 'T'],
    ColorSpaceMode.hsl => const ['H', 'S', 'L'],
    ColorSpaceMode.hsv => const ['H', 'S', 'V'],
  };
}

/// Metadata and live value for one channel column in the picker.
class const ChannelDescriptor({
  required final int index,
  required final String name,
  required final String shortName,
  required final double value,
  required final double min,
  required final double max,
  required final String unit,
  required final String formattedValue,
  final String? secondaryLabel,
}) {
  double get normalized =>
      max == min ? 0.0 : ((value - min) / (max - min)).clamp(0.0, 1.0);
}

/// Exact Oklab / OKLCH (CSS Color 4) perceptual color model with sRGB gamut mapping.
class const OklchColor({
  /// Lightness in [0..100]%.
  required final double lightness,

  /// Raw Oklab Chroma in [0..~0.37].
  required final double chroma,

  /// Hue angle in [0..360) degrees.
  required final double hue,

  /// Share of the available chroma that was asked for, kept so it survives
  /// lightness values where no chroma is available.
  final double? relativePercent,
}) extends Equatable {
  factory fromColor(Color color) {
    final rLin = _srgbToLinear(color.r);
    final gLin = _srgbToLinear(color.g);
    final bLin = _srgbToLinear(color.b);

    final l = 0.4122214708 * rLin + 0.5363325363 * gLin + 0.0514459929 * bLin;
    final m = 0.2119034982 * rLin + 0.6806995451 * gLin + 0.1073969566 * bLin;
    final s = 0.0883024619 * rLin + 0.2817188376 * gLin + 0.6299787005 * bLin;

    final l_ = _cbrt(l);
    final m_ = _cbrt(m);
    final s_ = _cbrt(s);

    final okl = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    final oka = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    final okb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

    final c = math.sqrt(oka * oka + okb * okb);
    var h = c < 1e-6 ? 0.0 : math.atan2(okb, oka) * 180.0 / math.pi;
    if (h < 0) h += 360.0;

    return OklchColor(
      lightness: (okl * 100.0).clamp(0.0, 100.0),
      chroma: c,
      hue: h % 360.0,
    );
  }

  factory fromRelative({
    required double hue,
    required double saturationPercent,
    required double lightness,
  }) {
    final normHue = ((hue % 360.0) + 360.0) % 360.0;
    final clampedL = lightness.clamp(0.0, 100.0);
    final maxC = maxChromaForLH(clampedL, normHue);
    final percent = saturationPercent.clamp(0.0, 100.0).toDouble();
    return OklchColor(
      lightness: clampedL,
      chroma: maxC * (percent / 100.0),
      hue: normHue,
      relativePercent: percent,
    );
  }

  /// Maximum in-gamut sRGB Chroma for given OKLCH (lightness %, hue deg).
  static double maxChromaForLH(double lightnessPct, double hueDeg) {
    final l = (lightnessPct / 100.0).clamp(0.0, 1.0);
    if (l <= 1e-5 || l >= 1.0 - 1e-5) return 0.0;

    final hRad = hueDeg * math.pi / 180.0;
    final cosH = math.cos(hRad);
    final sinH = math.sin(hRad);

    var low = 0.0;
    var high = 0.37;
    for (int i = 0; i < 16; i++) {
      final mid = (low + high) * 0.5;
      if (_isLinearSrgbInGamut(l, mid * cosH, mid * sinH)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  double get relativeSaturationPercent {
    final kept = relativePercent;
    if (kept != null) return kept;
    final maxC = maxChromaForLH(lightness, hue);
    if (maxC <= 1e-6) return 0.0;
    return ((chroma / maxC) * 100.0).clamp(0.0, 100.0);
  }

  /// Converts to the closest sRGB [Color], preserving L and H by clamping C
  /// onto the sRGB boundary when out of gamut.
  Color toColor() {
    final l = (lightness / 100.0).clamp(0.0, 1.0);
    if (l <= 1e-5) return const Color(0xFF000000);
    if (l >= 1.0 - 1e-5) return const Color(0xFFFFFFFF);

    final hRad = hue * math.pi / 180.0;
    final cosH = math.cos(hRad);
    final sinH = math.sin(hRad);

    var c = chroma.clamp(0.0, 0.4);
    if (!_isLinearSrgbInGamut(l, c * cosH, c * sinH)) {
      var low = 0.0;
      var high = c;
      for (int i = 0; i < 16; i++) {
        final mid = (low + high) * 0.5;
        if (_isLinearSrgbInGamut(l, mid * cosH, mid * sinH)) {
          low = mid;
        } else {
          high = mid;
        }
      }
      c = low;
    }

    final rgb = _oklabToLinearSrgb(l, c * cosH, c * sinH);
    return Color.fromARGB(
      255,
      (_linearToSrgb(rgb[0]).clamp(0.0, 1.0) * 255.0).round(),
      (_linearToSrgb(rgb[1]).clamp(0.0, 1.0) * 255.0).round(),
      (_linearToSrgb(rgb[2]).clamp(0.0, 1.0) * 255.0).round(),
    );
  }

  OklchColor copyWith({double? lightness, double? chroma, double? hue}) {
    return OklchColor(
      lightness: (lightness ?? this.lightness).clamp(0.0, 100.0),
      chroma: math.max(0.0, chroma ?? this.chroma),
      hue: ((hue ?? this.hue) % 360.0 + 360.0) % 360.0,
    );
  }

  String toCssString() =>
      'oklch(${lightness.toStringAsFixed(1)}% ${chroma.toStringAsFixed(3)} ${hue.toStringAsFixed(1)})';

  static bool _isLinearSrgbInGamut(double l, double a, double b) {
    final rgb = _oklabToLinearSrgb(l, a, b);
    const eps = 1e-9;
    return rgb[0] >= -eps &&
        rgb[0] <= 1.0 + eps &&
        rgb[1] >= -eps &&
        rgb[1] <= 1.0 + eps &&
        rgb[2] >= -eps &&
        rgb[2] <= 1.0 + eps;
  }

  static List<double> _oklabToLinearSrgb(double okl, double oka, double okb) {
    final l_ = okl + 0.3963377774 * oka + 0.2158037573 * okb;
    final m_ = okl - 0.1055613458 * oka - 0.0638541728 * okb;
    final s_ = okl - 0.0894841775 * oka - 1.2914855480 * okb;

    final l = l_ * l_ * l_;
    final m = m_ * m_ * m_;
    final s = s_ * s_ * s_;

    return [
      4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    ];
  }

  static double _srgbToLinear(double c) {
    if (c <= 0.04045) return c / 12.92;
    return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _linearToSrgb(double c) {
    if (c <= 0.0031308) return 12.92 * c;
    return 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
  }

  static double _cbrt(double x) {
    if (x == 0) return 0;
    return x < 0
        ? -math.pow(-x, 1.0 / 3.0).toDouble()
        : math.pow(x, 1.0 / 3.0).toDouble();
  }

  @override
  List<Object?> get props => [lightness, chroma, hue, relativePercent];
}

/// Unified color representation preserving channel coordinates across spaces.
class const StudioColor({
  required final Color color,
  required final HSLuvColor hsluv,
  required final OklchColor oklch,
  required final double hctHue,
  required final double hctChroma,

  /// [hctChroma] as a share of the most chroma this hue and tone can reach.
  required final double hctChromaPercent,
  required final double hctTone,
  required final HSLColor hsl,
  required final HSVColor hsv,
}) extends Equatable {
  factory fromColor(Color color) {
    final opaque = color.withValues(alpha: 1.0);
    final hct = Hct.fromInt(opaque.toARGB32());
    return StudioColor(
      color: opaque,
      hsluv: hsluvFromColor(opaque),
      oklch: OklchColor.fromColor(opaque),
      hctHue: hct.hue,
      hctChroma: hct.chroma,
      hctChromaPercent: _hctChromaShare(hct.hue, hct.chroma, hct.tone),
      hctTone: hct.tone,
      hsl: HSLColor.fromColor(opaque),
      hsv: HSVColor.fromColor(opaque),
    );
  }

  factory fromHsluv(HSLuvColor hsluv) {
    final c = hsluv.toColor();
    final base = StudioColor.fromColor(c);
    return StudioColor(
      color: base.color,
      hsluv: hsluv,
      oklch: base.oklch,
      hctHue: base.hctHue,
      hctChroma: base.hctChroma,
      hctChromaPercent: base.hctChromaPercent,
      hctTone: base.hctTone,
      hsl: base.hsl,
      hsv: base.hsv,
    );
  }

  factory fromOklch(OklchColor oklch) {
    final c = oklch.toColor();
    final base = StudioColor.fromColor(c);
    return StudioColor(
      color: base.color,
      hsluv: base.hsluv,
      oklch: oklch,
      hctHue: base.hctHue,
      hctChroma: base.hctChroma,
      hctChromaPercent: base.hctChromaPercent,
      hctTone: base.hctTone,
      hsl: base.hsl,
      hsv: base.hsv,
    );
  }

  factory fromHct(double hue, double chroma, double tone) {
    final normHue = ((hue % 360.0) + 360.0) % 360.0;
    final clampedChroma = chroma.clamp(0.0, 120.0);
    final clampedTone = tone.clamp(0.0, 100.0);
    final solved = Hct.from(normHue, clampedChroma, clampedTone);
    final c = Color(solved.toInt());
    final base = StudioColor.fromColor(c);
    return StudioColor(
      color: base.color,
      hsluv: base.hsluv,
      oklch: base.oklch,
      hctHue: normHue,
      hctChroma: clampedChroma,
      hctChromaPercent: _hctChromaShare(normHue, clampedChroma, clampedTone),
      hctTone: clampedTone,
      hsl: base.hsl,
      hsv: base.hsv,
    );
  }

  /// HCT colour whose chroma is [chromaPercent] of what the hue and tone
  /// can reach, so every value from 0 to 100 gives a different colour.
  factory fromHctRelative(double hue, double chromaPercent, double tone) {
    final normHue = ((hue % 360.0) + 360.0) % 360.0;
    final percent = chromaPercent.clamp(0.0, 100.0).toDouble();
    final clampedTone = tone.clamp(0.0, 100.0).toDouble();
    final chroma = _maxHctChroma(normHue, clampedTone) * (percent / 100.0);
    final base = StudioColor.fromColor(
      Color(Hct.from(normHue, chroma, clampedTone).toInt()),
    );
    return StudioColor(
      color: base.color,
      hsluv: base.hsluv,
      oklch: base.oklch,
      hctHue: normHue,
      hctChroma: chroma,
      hctChromaPercent: percent,
      hctTone: clampedTone,
      hsl: base.hsl,
      hsv: base.hsv,
    );
  }

  /// The colour at [hue], [saturationPct] and [lightnessPct] in [mode].
  factory fromSpace(
    ColorSpaceMode mode, {
    required double hue,
    required double saturationPct,
    required double lightnessPct,
  }) {
    final h = ((hue % 360.0) + 360.0) % 360.0;
    final s = saturationPct.clamp(0.0, 100.0).toDouble();
    final l = lightnessPct.clamp(0.0, 100.0).toDouble();
    return switch (mode) {
      ColorSpaceMode.hsluv => StudioColor.fromHsluv(
        HSLuvColor.fromHSL(h, s, l),
      ),
      ColorSpaceMode.oklch => StudioColor.fromOklch(
        OklchColor.fromRelative(hue: h, saturationPercent: s, lightness: l),
      ),
      ColorSpaceMode.hct => StudioColor.fromHctRelative(h, s, l),
      ColorSpaceMode.hsl => StudioColor.fromHsl(
        HSLColor.fromAHSL(1.0, h, s / 100.0, l / 100.0),
      ),
      ColorSpaceMode.hsv => StudioColor.fromHsv(
        HSVColor.fromAHSV(1.0, h, s / 100.0, l / 100.0),
      ),
    };
  }

  static double _maxHctChroma(double hue, double tone) =>
      Hct.from(hue, 150.0, tone).chroma;

  static double _hctChromaShare(double hue, double chroma, double tone) {
    final most = _maxHctChroma(hue, tone);
    if (most <= 1e-3) return 0.0;
    return ((chroma / most) * 100.0).clamp(0.0, 100.0).toDouble();
  }

  factory fromHsl(HSLColor hsl) {
    final c = hsl.toColor();
    final base = StudioColor.fromColor(c);
    return StudioColor(
      color: base.color,
      hsluv: base.hsluv,
      oklch: base.oklch,
      hctHue: base.hctHue,
      hctChroma: base.hctChroma,
      hctChromaPercent: base.hctChromaPercent,
      hctTone: base.hctTone,
      hsl: hsl,
      hsv: base.hsv,
    );
  }

  factory fromHsv(HSVColor hsv) {
    final c = hsv.toColor();
    final base = StudioColor.fromColor(c);
    return StudioColor(
      color: base.color,
      hsluv: base.hsluv,
      oklch: base.oklch,
      hctHue: base.hctHue,
      hctChroma: base.hctChroma,
      hctChromaPercent: base.hctChromaPercent,
      hctTone: base.hctTone,
      hsl: base.hsl,
      hsv: hsv,
    );
  }

  /// Uppercase `#RRGGBB` hex string.
  String get hex {
    final r = (color.r * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final g = (color.g * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final b = (color.b * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }

  String get rgbCss {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return 'rgb($r, $g, $b)';
  }

  String get hsluvDisplay =>
      'HSLuv(${hsluv.hue.round()}°, ${hsluv.saturation.round()}%, ${hsluv.lightness.round()}%)';

  String get oklchDisplay => oklch.toCssString();

  String get hctDisplay =>
      'HCT(${hctHue.round()}°, C${hctChroma.round()}, T${hctTone.round()})';

  String get hslDisplay =>
      'hsl(${hsl.hue.round()}deg ${(hsl.saturation * 100).round()}% ${(hsl.lightness * 100).round()}%)';

  String get hsvDisplay =>
      'HSV(${hsv.hue.round()}°, ${(hsv.saturation * 100).round()}%, ${(hsv.value * 100).round()}%)';

  /// Channels ordered uniformly as [Hue, Saturation/Chroma, Lightness/Tone/Value].
  List<ChannelDescriptor> channelsFor(ColorSpaceMode mode) {
    return switch (mode) {
      ColorSpaceMode.hsluv => [
        ChannelDescriptor(
          index: 0,
          name: 'Hue',
          shortName: 'H',
          value: hsluv.hue,
          min: 0,
          max: 360,
          unit: '°',
          formattedValue: '${hsluv.hue.round()}°',
        ),
        ChannelDescriptor(
          index: 1,
          name: 'Saturation',
          shortName: 'S',
          value: hsluv.saturation,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${hsluv.saturation.round()}%',
        ),
        ChannelDescriptor(
          index: 2,
          name: 'Lightness',
          shortName: 'L',
          value: hsluv.lightness,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${hsluv.lightness.round()}%',
        ),
      ],
      ColorSpaceMode.oklch => [
        ChannelDescriptor(
          index: 0,
          name: 'Hue',
          shortName: 'h',
          value: oklch.hue,
          min: 0,
          max: 360,
          unit: '°',
          formattedValue: '${oklch.hue.round()}°',
        ),
        ChannelDescriptor(
          index: 1,
          name: 'Chroma',
          shortName: 'C',
          value: oklch.relativeSaturationPercent,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${oklch.relativeSaturationPercent.round()}%',
          secondaryLabel: 'C ${oklch.chroma.toStringAsFixed(3)}',
        ),
        ChannelDescriptor(
          index: 2,
          name: 'Lightness',
          shortName: 'L',
          value: oklch.lightness,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${oklch.lightness.round()}%',
        ),
      ],
      ColorSpaceMode.hct => [
        ChannelDescriptor(
          index: 0,
          name: 'Hue',
          shortName: 'H',
          value: hctHue,
          min: 0,
          max: 360,
          unit: '°',
          formattedValue: '${hctHue.round()}°',
        ),
        ChannelDescriptor(
          index: 1,
          name: 'Chroma',
          shortName: 'C',
          value: hctChromaPercent,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${hctChromaPercent.round()}%',
          secondaryLabel: 'C ${hctChroma.round()}',
        ),
        ChannelDescriptor(
          index: 2,
          name: 'Tone',
          shortName: 'T',
          value: hctTone,
          min: 0,
          max: 100,
          unit: '',
          formattedValue: hctTone.round().toString(),
        ),
      ],
      ColorSpaceMode.hsl => [
        ChannelDescriptor(
          index: 0,
          name: 'Hue',
          shortName: 'H',
          value: hsl.hue,
          min: 0,
          max: 360,
          unit: '°',
          formattedValue: '${hsl.hue.round()}°',
        ),
        ChannelDescriptor(
          index: 1,
          name: 'Saturation',
          shortName: 'S',
          value: hsl.saturation * 100,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${(hsl.saturation * 100).round()}%',
        ),
        ChannelDescriptor(
          index: 2,
          name: 'Lightness',
          shortName: 'L',
          value: hsl.lightness * 100,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${(hsl.lightness * 100).round()}%',
        ),
      ],
      ColorSpaceMode.hsv => [
        ChannelDescriptor(
          index: 0,
          name: 'Hue',
          shortName: 'H',
          value: hsv.hue,
          min: 0,
          max: 360,
          unit: '°',
          formattedValue: '${hsv.hue.round()}°',
        ),
        ChannelDescriptor(
          index: 1,
          name: 'Saturation',
          shortName: 'S',
          value: hsv.saturation * 100,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${(hsv.saturation * 100).round()}%',
        ),
        ChannelDescriptor(
          index: 2,
          name: 'Value',
          shortName: 'V',
          value: hsv.value * 100,
          min: 0,
          max: 100,
          unit: '%',
          formattedValue: '${(hsv.value * 100).round()}%',
        ),
      ],
    };
  }

  /// Updates a single channel in [mode], returning a new [StudioColor].
  StudioColor withChannelValue(
    ColorSpaceMode mode,
    int channelIndex,
    double newValue,
  ) {
    return switch (mode) {
      ColorSpaceMode.hsluv => switch (channelIndex) {
        0 => StudioColor.fromHsluv(
          hsluv.withHue(((newValue % 360.0) + 360.0) % 360.0),
        ),
        1 => StudioColor.fromHsluv(
          hsluv.withSaturation(newValue.clamp(0.0, 100.0)),
        ),
        _ => StudioColor.fromHsluv(
          hsluv.withLightness(newValue.clamp(0.0, 100.0)),
        ),
      },
      ColorSpaceMode.oklch => switch (channelIndex) {
        0 => StudioColor.fromOklch(
          OklchColor.fromRelative(
            hue: newValue,
            saturationPercent: oklch.relativeSaturationPercent,
            lightness: oklch.lightness,
          ),
        ),
        1 => StudioColor.fromOklch(
          OklchColor.fromRelative(
            hue: oklch.hue,
            saturationPercent: newValue,
            lightness: oklch.lightness,
          ),
        ),
        _ => StudioColor.fromOklch(
          OklchColor.fromRelative(
            hue: oklch.hue,
            saturationPercent: oklch.relativeSaturationPercent,
            lightness: newValue,
          ),
        ),
      },
      ColorSpaceMode.hct => switch (channelIndex) {
        0 => StudioColor.fromHctRelative(newValue, hctChromaPercent, hctTone),
        1 => StudioColor.fromHctRelative(hctHue, newValue, hctTone),
        _ => StudioColor.fromHctRelative(hctHue, hctChromaPercent, newValue),
      },
      ColorSpaceMode.hsl => switch (channelIndex) {
        0 => StudioColor.fromHsl(
          hsl.withHue(((newValue % 360.0) + 360.0) % 360.0),
        ),
        1 => StudioColor.fromHsl(
          hsl.withSaturation((newValue / 100.0).clamp(0.0, 1.0)),
        ),
        _ => StudioColor.fromHsl(
          hsl.withLightness((newValue / 100.0).clamp(0.0, 1.0)),
        ),
      },
      ColorSpaceMode.hsv => switch (channelIndex) {
        0 => StudioColor.fromHsv(
          hsv.withHue(((newValue % 360.0) + 360.0) % 360.0),
        ),
        1 => StudioColor.fromHsv(
          hsv.withSaturation((newValue / 100.0).clamp(0.0, 1.0)),
        ),
        _ => StudioColor.fromHsv(
          hsv.withValue((newValue / 100.0).clamp(0.0, 1.0)),
        ),
      },
    };
  }

  /// Fast color evaluation for rendering swatches/gradients along [channelIndex]
  /// where [value] is in that channel's natural [min..max] range.
  Color sampleChannel(ColorSpaceMode mode, int channelIndex, double value) {
    return switch (mode) {
      ColorSpaceMode.hsluv => switch (channelIndex) {
        0 => HSLuvColor.fromHSL(
          ((value % 360.0) + 360.0) % 360.0,
          hsluv.saturation,
          hsluv.lightness,
        ).toColor(),
        1 => HSLuvColor.fromHSL(
          hsluv.hue,
          value.clamp(0.0, 100.0),
          hsluv.lightness,
        ).toColor(),
        _ => HSLuvColor.fromHSL(
          hsluv.hue,
          hsluv.saturation,
          value.clamp(0.0, 100.0),
        ).toColor(),
      },
      ColorSpaceMode.oklch => switch (channelIndex) {
        0 => OklchColor.fromRelative(
          hue: value,
          saturationPercent: oklch.relativeSaturationPercent,
          lightness: oklch.lightness,
        ).toColor(),
        1 => OklchColor.fromRelative(
          hue: oklch.hue,
          saturationPercent: value,
          lightness: oklch.lightness,
        ).toColor(),
        _ => OklchColor.fromRelative(
          hue: oklch.hue,
          saturationPercent: oklch.relativeSaturationPercent,
          lightness: value,
        ).toColor(),
      },
      ColorSpaceMode.hct => switch (channelIndex) {
        0 => sampleAcrossSpace(
          mode,
          hue: value,
          saturationPct: hctChromaPercent,
          lightnessPct: hctTone,
        ),
        1 => sampleAcrossSpace(
          mode,
          hue: hctHue,
          saturationPct: value,
          lightnessPct: hctTone,
        ),
        _ => sampleAcrossSpace(
          mode,
          hue: hctHue,
          saturationPct: hctChromaPercent,
          lightnessPct: value,
        ),
      },
      ColorSpaceMode.hsl => switch (channelIndex) {
        0 => hsl.withHue(((value % 360.0) + 360.0) % 360.0).toColor(),
        1 => hsl.withSaturation((value / 100.0).clamp(0.0, 1.0)).toColor(),
        _ => hsl.withLightness((value / 100.0).clamp(0.0, 1.0)).toColor(),
      },
      ColorSpaceMode.hsv => switch (channelIndex) {
        0 => hsv.withHue(((value % 360.0) + 360.0) % 360.0).toColor(),
        1 => hsv.withSaturation((value / 100.0).clamp(0.0, 1.0)).toColor(),
        _ => hsv.withValue((value / 100.0).clamp(0.0, 1.0)).toColor(),
      },
    };
  }

  /// Generates a 11-step design system tonal scale (`50`..`950`) in [mode].
  List<({int token, Color color, double lightness})> tonalRamp(
    ColorSpaceMode mode,
  ) {
    const tokens = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950];
    const stops = [
      96.0,
      90.0,
      82.0,
      72.0,
      62.0,
      52.0,
      43.0,
      34.0,
      25.0,
      17.0,
      10.0,
    ];

    return [
      for (int i = 0; i < tokens.length; i++)
        (
          token: tokens[i],
          color: switch (mode) {
            ColorSpaceMode.hsluv => HSLuvColor.fromHSL(
              hsluv.hue,
              hsluv.saturation,
              stops[i],
            ).toColor(),
            ColorSpaceMode.oklch => OklchColor.fromRelative(
              hue: oklch.hue,
              saturationPercent: oklch.relativeSaturationPercent,
              lightness: stops[i],
            ).toColor(),
            ColorSpaceMode.hct => Color(
              Hct.from(hctHue, hctChroma, stops[i]).toInt(),
            ),
            ColorSpaceMode.hsl => hsl.withLightness(stops[i] / 100.0).toColor(),
            ColorSpaceMode.hsv => hsv.withValue(stops[i] / 100.0).toColor(),
          },
          lightness: stops[i],
        ),
    ];
  }

  @override
  List<Object> get props => [
    color,
    hsluv,
    oklch,
    hctHue,
    hctChroma,
    hctChromaPercent,
    hctTone,
    hsl,
    hsv,
  ];
}

/// How far from the grey axis [mode] can go at [hue] and [lightnessPct],
/// from 0 to about 1.
///
/// Spaces that normalise saturation reach the same distance everywhere, so
/// their gamut is a cylinder. The others reach as far as sRGB lets them.
double chromaReach(
  ColorSpaceMode mode, {
  required double hue,
  required double lightnessPct,
}) {
  const mostOklchChroma = 0.3;
  const mostHctChroma = 100.0;
  return switch (mode) {
    ColorSpaceMode.hsluv || ColorSpaceMode.hsl || ColorSpaceMode.hsv => 1.0,
    ColorSpaceMode.oklch =>
      OklchColor.maxChromaForLH(lightnessPct, hue) / mostOklchChroma,
    ColorSpaceMode.hct =>
      Hct.from(hue, 150.0, lightnessPct).chroma / mostHctChroma,
  };
}

/// Samples [hue] at [saturationPct] and [lightnessPct] across any space.
Color sampleAcrossSpace(
  ColorSpaceMode mode, {
  required double hue,
  required double saturationPct,
  required double lightnessPct,
}) {
  final h = ((hue % 360.0) + 360.0) % 360.0;
  final s = saturationPct.clamp(0.0, 100.0);
  final l = lightnessPct.clamp(0.0, 100.0);
  return switch (mode) {
    ColorSpaceMode.hsluv => HSLuvColor.fromHSL(h, s, l).toColor(),
    ColorSpaceMode.oklch => OklchColor.fromRelative(
      hue: h,
      saturationPercent: s,
      lightness: l,
    ).toColor(),
    ColorSpaceMode.hct => () {
      final maxChroma = Hct.from(h, 150.0, l).chroma;
      return Color(Hct.from(h, maxChroma * (s / 100.0), l).toInt());
    }(),
    ColorSpaceMode.hsl => HSLColor.fromAHSL(
      1.0,
      h,
      s / 100.0,
      l / 100.0,
    ).toColor(),
    ColorSpaceMode.hsv => HSVColor.fromAHSV(
      1.0,
      h,
      s / 100.0,
      l / 100.0,
    ).toColor(),
  };
}

/// Chooses a curated eight-swatch palette for a new studio.
List<StudioColor> defaultStudioPalette({math.Random? random}) {
  const palettes = [
    // Bright spectrum
    [
      Color(0xFF3B82F6),
      Color(0xFFF97316),
      Color(0xFF10B981),
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
      Color(0xFFEAB308),
      Color(0xFF06B6D4),
      Color(0xFF1E293B),
    ],
    // Desert sunset
    [
      Color(0xFFE76F51),
      Color(0xFFA95452),
      Color(0xFFF4A261),
      Color(0xFFE9C46A),
      Color(0xFFB99B80),
      Color(0xFFF7E5D1),
      Color(0xFF8C6B55),
      Color(0xFF48363B),
    ],
    // Tidal pool
    [
      Color(0xFF168C80),
      Color(0xFF5DC9B2),
      Color(0xFF81D4DA),
      Color(0xFF4189A2),
      Color(0xFF226478),
      Color(0xFFC2DED4),
      Color(0xFFEDE7D5),
      Color(0xFF163B43),
    ],
    // Wisteria
    [
      Color(0xFF7D5AC2),
      Color(0xFFAC91D8),
      Color(0xFFD6C6EB),
      Color(0xFF6064AE),
      Color(0xFF888EBB),
      Color(0xFFCE90B7),
      Color(0xFFF3E4EF),
      Color(0xFF362C53),
    ],
    // Botanical
    [
      Color(0xFF48734F),
      Color(0xFF81A979),
      Color(0xFFA9C853),
      Color(0xFFBDC58B),
      Color(0xFFDDE5C8),
      Color(0xFFC88753),
      Color(0xFFF1E9D7),
      Color(0xFF344439),
    ],
    // Rosewater
    [
      Color(0xFFCD5E89),
      Color(0xFFDD789E),
      Color(0xFFE6A3B4),
      Color(0xFFF4CBD0),
      Color(0xFFB84FA1),
      Color(0xFF945877),
      Color(0xFFFFE8DB),
      Color(0xFF4B2E40),
    ],
    // Blue hour
    [
      Color(0xFF5476B1),
      Color(0xFF79B7E7),
      Color(0xFF3E63DD),
      Color(0xFF96AACB),
      Color(0xFFBFD0E5),
      Color(0xFFE0D8F0),
      Color(0xFFF0EEE9),
      Color(0xFF242D50),
    ],
    // Marigold
    [
      Color(0xFFBC9238),
      Color(0xFFD3A72A),
      Color(0xFFE7BF58),
      Color(0xFFF4D992),
      Color(0xFFE4A373),
      Color(0xFF8C7950),
      Color(0xFFF6EED7),
      Color(0xFF52452E),
    ],
  ];
  final palette = palettes[random?.nextInt(palettes.length) ?? 0];
  return palette.map(StudioColor.fromColor).toList();
}

/// Generates a fresh, perceptually balanced 8-color palette seeded from a base hue.
List<StudioColor> generateHarmoniousPalette(double seedHue) {
  final rng = math.Random();
  final baseL = 56.0 + rng.nextDouble() * 10.0;
  final baseS = 78.0 + rng.nextDouble() * 18.0;
  final offsets = [0.0, 32.0, 145.0, 180.0, 215.0, 275.0, 60.0, 15.0];
  final lightnesses = [
    baseL,
    (baseL + 12).clamp(25.0, 88.0),
    baseL,
    (baseL - 6).clamp(20.0, 85.0),
    (baseL + 16).clamp(25.0, 88.0),
    (baseL - 12).clamp(20.0, 85.0),
    92.0,
    18.0,
  ];
  final saturations = [
    baseS,
    baseS,
    baseS,
    baseS * 0.9,
    baseS * 0.85,
    baseS,
    22.0,
    24.0,
  ];

  return [
    for (int i = 0; i < 8; i++)
      StudioColor.fromHsluv(
        HSLuvColor.fromHSL(
          (seedHue + offsets[i]) % 360.0,
          saturations[i].clamp(0.0, 100.0),
          lightnesses[i].clamp(0.0, 100.0),
        ),
      ),
  ];
}

/// Parses hex (`#RGB`, `#RRGGBB`, `RRGGBB`) or `oklch(L% C H)` / `rgb(r,g,b)` input.
Color? parseColorInput(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return null;

  var hex = input.startsWith('#') ? input.substring(1) : input;
  if (RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(hex)) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return Color(int.parse('FF$hex', radix: 16));
  }

  final rgbMatch = RegExp(
    r'^rgb\s*\(\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})\s*\)$',
    caseSensitive: false,
  ).firstMatch(input);
  if (rgbMatch != null) {
    final r = int.parse(rgbMatch.group(1)!).clamp(0, 255);
    final g = int.parse(rgbMatch.group(2)!).clamp(0, 255);
    final b = int.parse(rgbMatch.group(3)!).clamp(0, 255);
    return Color.fromARGB(255, r, g, b);
  }

  final oklchMatch = RegExp(
    r'^oklch\s*\(\s*([\d.]+)(%?)\s+([\d.]+)\s+([\d.]+)(?:deg)?\s*\)$',
    caseSensitive: false,
  ).firstMatch(input);
  if (oklchMatch != null) {
    var l = double.parse(oklchMatch.group(1)!);
    if (oklchMatch.group(2)!.isEmpty && l <= 1.0) l *= 100.0;
    final c = double.parse(oklchMatch.group(3)!);
    final h = double.parse(oklchMatch.group(4)!);
    return OklchColor(lightness: l, chroma: c, hue: h).toColor();
  }

  return null;
}
