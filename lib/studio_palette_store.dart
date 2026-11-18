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
  // Earlier swatch signatures keyed by the starter they should refresh to.
  static const _previousPresets = {
    'Riso Club': [
      '3B82F6 F97316 10B981 EC4899 8B5CF6 EAB308 06B6D4 1E293B',
      '3B60C8 27398C 8298E4 D9AE45 95653D D6DDF0 F3EBDD 22253C',
      '3452CC 243478 859CEA E3AD40 9D6338 D8E2F5 F6EDDB 21253A',
      '242943 303F74 3D56A8 5370CF 798FDA A1ADE3 CACDE2 F5ECDE',
      '17244B 213A79 2852B6 356BE8 568DF3 83B2F9 B8D6FA E8F3FB',
    ],
    'Harvest': [
      'E76F51 A95452 F4A261 E9C46A B99B80 F7E5D1 8C6B55 48363B',
      '237D69 185447 78A89A C56C44 D5AF75 C4D9C8 F3EBDD 23332E',
      '187A53 164D3B 80A995 A7C755 DDE5A4 B65843 F2EFDF 233730',
      '19352F 285040 376C52 488964 75A36D A0BD74 C9D595 F2ECCD',
    ],
    'Deep Sea': [
      '168C80 5DC9B2 81D4DA 4189A2 226478 C2DED4 EDE7D5 163B43',
      'B44A32 743A2C DC8E68 596F61 A2A878 E1C9A8 F3EBDD 342B2C',
      'E98758 A74B36 F4BC87 305D88 8EAEBF DCC2A6 FAECD9 35292B',
      '412B33 663D3C 8D4E44 B4624C CD825F E5A172 F2C5A1 FAEAD4',
    ],
    'Wildflower': [
      '7D5AC2 AC91D8 D6C6EB 6064AE 888EBB CE90B7 F3E4EF 362C53',
      '51458D 392E62 9C91BF B89B49 697554 D9CEE1 F3EBDD 2A2635',
      '8880C4 55458A BFB1E9 C9D37C 718365 DFD9ED F5EDE3 302840',
      '2C2845 483C67 65528C 8369AF 9E89C2 BAA8D4 D5CAE5 F1ECF6',
      '2C2845 473969 664F95 886ABC A487CD BEA8DC D9C9EE F3EDF9',
    ],
    'Matcha': [
      '48734F 81A979 A9C853 BDC58B DDE5C8 C88753 F1E9D7 344439',
      '6A743D 454F2C A8A958 75465C C18766 D8CE9E F3EBDD 342C2A',
      '8B9850 4A5732 C7C686 70485F AF8FA7 D9C5A4 F3E8D7 322936',
      '333A2D 4A5238 626C43 7C8650 9D9D6A BEB586 D9D0B1 F4EBDD',
    ],
    'Bubblegum': [
      'CD5E89 DD789E E6A3B4 F4CBD0 B84FA1 945877 FFE8DB 4B2E40',
      '873847 582B31 B6776C 83A894 B89A65 DCBFAE F3EBDD 29292B',
      '843341 563036 C28370 83AD96 B79660 DFC4AA F6EBDD 302A2B',
      '36232D 5D333D 86434D A95B5F C07D75 D69F8C E6C3B2 F6E7D9',
      '302333 4B3147 6B4059 895469 A57380 C1959D DAC0BF F2E7E4',
    ],
    'Fjord': [
      '5476B1 79B7E7 3E63DD 96AACB BFD0E5 E0D8F0 F0EEE9 242D50',
      '2A6474 1E4555 769BA8 B66C46 D0996B CBDDE0 F3EBDD 232B32',
      '509DA3 1A5663 6C879B BC6747 D5A780 C5E1DE F0ECE1 25333D',
      '23323E 2C4D58 326A74 43878E 69A2A3 8EBDB9 BAD6CF E7F0E6',
    ],
    'Citrus Stand': [
      'BC9238 D3A72A E7BF58 F4D992 E4A373 8C7950 F6EED7 52452E',
      'AD772F 79582E D7AA56 4F687D 839497 E9D4A6 F3EBDD 2D2A27',
      'E0AF42 A77330 F3CF75 42617A 879BA6 956C57 F7E9CA 272F36',
      '3A2B26 5A4130 7C573A A16F42 BE8C4E D9AC5A ECCE8F FAF0D1',
      '392B25 594234 7C5837 A77536 C29444 D9B350 ECD78B FBEDC9',
    ],
  };

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

    final replacement = saved == null ? null : _refreshPreset(saved.palette);
    final initial =
        saved?.copyWith(
          palette: replacement,
          selectedIndex: replacement == null ? null : 0,
        ) ??
        StudioState.initial(
          palette: defaultStudioPalette(random: math.Random()),
        );
    final cubit = StudioCubit(initialState: initial);
    if (didRead && (saved == null || replacement != null)) await _save(initial);

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

  static List<StudioColor>? _refreshPreset(List<StudioColor> palette) {
    // A swatch can have edited channel values even when its displayed hex matches.
    if (palette.any((entry) => entry != StudioColor.fromColor(entry.color))) {
      return null;
    }
    final signature = palette.map((entry) => entry.hex.substring(1)).join(' ');
    for (final MapEntry(key: name, value: versions)
        in _previousPresets.entries) {
      if (!versions.contains(signature)) continue;
      return studioStarterPaletteAt(
        studioStarterPalettes.indexWhere((starter) => starter.name == name),
      );
    }
    return null;
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
        when colors.length >= 2 &&
            colors.length <= maxStudioPaletteLength &&
            index >= 0 &&
            index < colors.length) {
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
