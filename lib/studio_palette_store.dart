import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Color, ColorSpace;

import 'package:flutter/foundation.dart';
import 'package:hsluv/hsluvcolor.dart';
import 'package:material_ui/material_ui.dart' show HSLColor, HSVColor;
import 'package:shared_preferences/shared_preferences.dart';

import 'blocs/studio_cubit.dart';
import 'models/color_spaces.dart';

/// Stores the palette and selected slot together as a single snapshot.
class StudioPaletteStore({
  required final Future<String?> Function() _read,
  required final Future<void> Function(String) _write,
}) {
  factory local() {
    const key = 'studio.palette.v1';
    final preferences = SharedPreferencesAsync();
    return StudioPaletteStore(
      read: () => preferences.getString(key),
      write: (palette) => preferences.setString(key, palette),
    );
  }

  Future<StudioCubit> open() async {
    StudioState? saved;
    var didRead = false;
    try {
      final snapshot = await _read();
      didRead = true;
      if (snapshot != null) saved = _decode(snapshot);
    } catch (error) {
      debugPrint('Could not read the studio palette: $error');
    }

    final initial =
        saved ??
        StudioState.initial(
          palette: defaultStudioPalette(random: math.Random()),
        );
    final cubit = StudioCubit(initialState: initial);
    if (saved == null && didRead) await _save(initial);

    var previous = initial;
    var pending = Future<void>.value();
    cubit.stream.listen((state) {
      if (identical(state.palette, previous.palette) &&
          state.selectedIndex == previous.selectedIndex) {
        return;
      }
      previous = state;
      // Complete writes in order so a slow write cannot replace a newer edit.
      pending = pending.then((_) => _save(state));
    });
    return cubit;
  }

  Future<void> _save(StudioState state) async {
    try {
      await _write(
        jsonEncode({
          'selectedIndex': state.selectedIndex,
          'colors': state.palette.map(_encodeColor).toList(),
        }),
      );
    } catch (error) {
      debugPrint('Could not save the studio palette: $error');
    }
  }

  static StudioState _decode(String snapshot) {
    if (jsonDecode(snapshot)
        case {
          'selectedIndex': final int index,
          'colors': final List<Object?> colors,
        }
        when colors.length == 8 && index >= 0 && index < colors.length) {
      return StudioState.initial(
        palette: colors.map(_decodeColor).toList(),
        selectedIndex: index,
      );
    }
    throw const FormatException('Invalid palette snapshot');
  }

  // Keep the editable coordinates because RGB alone loses hue and chroma at
  // the ends of the lightness range and rounds values to a visible swatch.
  static List<Object?> _encodeColor(StudioColor entry) => [
    [entry.color.r, entry.color.g, entry.color.b, entry.color.colorSpace.name],
    [entry.hsluv.hue, entry.hsluv.saturation, entry.hsluv.lightness],
    [
      entry.oklch.hue,
      entry.oklch.chroma,
      entry.oklch.lightness,
      entry.oklch.relativePercent,
    ],
    [entry.hctHue, entry.hctChroma, entry.hctChromaPercent, entry.hctTone],
    [entry.hsl.hue, entry.hsl.saturation, entry.hsl.lightness],
    [entry.hsv.hue, entry.hsv.saturation, entry.hsv.value],
  ];

  static StudioColor _decodeColor(Object? data) {
    if (data
        case [
          [num red, num green, num blue, String space],
          [num luvHue, num luvSaturation, num luvLightness],
          [num okHue, num okChroma, num okLightness, final relative],
          [num camHue, num camChroma, num camPercent, num camTone],
          [num hslHue, num hslSaturation, num hslLightness],
          [num hsvHue, num hsvSaturation, num hsvValue],
        ]
        when relative == null || relative is num) {
      return StudioColor(
        color: Color.from(
          alpha: 1,
          red: red.toDouble(),
          green: green.toDouble(),
          blue: blue.toDouble(),
          colorSpace: ColorSpace.values.byName(space),
        ),
        hsluv: HSLuvColor.fromHSL(
          luvHue.toDouble(),
          luvSaturation.toDouble(),
          luvLightness.toDouble(),
        ),
        oklch: OklchColor(
          hue: okHue.toDouble(),
          chroma: okChroma.toDouble(),
          lightness: okLightness.toDouble(),
          relativePercent: (relative as num?)?.toDouble(),
        ),
        hctHue: camHue.toDouble(),
        hctChroma: camChroma.toDouble(),
        hctChromaPercent: camPercent.toDouble(),
        hctTone: camTone.toDouble(),
        hsl: HSLColor.fromAHSL(
          1,
          hslHue.toDouble(),
          hslSaturation.toDouble(),
          hslLightness.toDouble(),
        ),
        hsv: HSVColor.fromAHSV(
          1,
          hsvHue.toDouble(),
          hsvSaturation.toDouble(),
          hsvValue.toDouble(),
        ),
      );
    }
    throw const FormatException('Invalid palette color');
  }
}
