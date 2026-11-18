import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:hsluv/contrast.dart';
import 'package:hsluv/hsluvcolor.dart';
import 'package:material_ui/material_ui.dart';

import 'color_spaces.dart' show hsluvFromColor;

/// Standard WCAG 2.1 contrast ratio between [a] and [b] in [1.0 .. 21.0].
double wcagContrastRatio(Color a, Color b) {
  final lumA = a.computeLuminance();
  final lumB = b.computeLuminance();
  final lighter = math.max(lumA, lumB);
  final darker = math.min(lumA, lumB);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Returns crisp foreground text color (near-black or near-white) with optimal contrast.
Color contrastingTextColor(Color bg) {
  const dark = Color(0xFF0B0F19);
  const light = Color(0xFFF8FAFC);
  return wcagContrastRatio(bg, dark) >= wcagContrastRatio(bg, light)
      ? dark
      : light;
}

/// Solves for the nearest [HSLuvColor] lightness that achieves [targetRatio]
/// against [background] while preserving hue and saturation.
HSLuvColor? solveHsluvForContrast(
  HSLuvColor source,
  Color background,
  double targetRatio,
) {
  final bgLuv = hsluvFromColor(background);

  // Use Contrast helper bounds as starting hints, then refine against true sRGB color.
  HSLuvColor? searchDarker() {
    if (wcagContrastRatio(source.withLightness(0).toColor(), background) <
        targetRatio) {
      return null;
    }
    var low = 0.0;
    var high = math.min(source.lightness, bgLuv.lightness);
    if (wcagContrastRatio(source.withLightness(high).toColor(), background) >=
        targetRatio) {
      high = source.lightness;
    }
    // Check if even at L=source.lightness it passes
    if (wcagContrastRatio(source.toColor(), background) >= targetRatio) {
      return source;
    }
    // Binary search largest L in [0, bgLuv.lightness] that reaches targetRatio
    low = 0.0;
    high = bgLuv.lightness;
    for (int i = 0; i < 24; i++) {
      final mid = (low + high) * 0.5;
      final candidate = source.withLightness(mid).toColor();
      if (wcagContrastRatio(candidate, background) >= targetRatio) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return source.withLightness(low);
  }

  HSLuvColor? searchLighter() {
    if (wcagContrastRatio(source.withLightness(100).toColor(), background) <
        targetRatio) {
      return null;
    }
    if (wcagContrastRatio(source.toColor(), background) >= targetRatio) {
      return source;
    }
    var low = math.max(
      bgLuv.lightness,
      Contrast.lighterMinL(targetRatio) * 0.0,
    );
    low = bgLuv.lightness;
    var high = 100.0;
    for (int i = 0; i < 24; i++) {
      final mid = (low + high) * 0.5;
      final candidate = source.withLightness(mid).toColor();
      if (wcagContrastRatio(candidate, background) >= targetRatio) {
        high = mid;
      } else {
        low = mid;
      }
    }
    return source.withLightness(high);
  }

  final darker = searchDarker();
  final lighter = searchLighter();

  if (darker == null) return lighter;
  if (lighter == null) return darker;

  final diffDark = (source.lightness - darker.lightness).abs();
  final diffLight = (lighter.lightness - source.lightness).abs();
  return diffDark <= diffLight ? darker : lighter;
}

/// Cached lookup against `assets/colornames.json`.
class ColorNameLookup._() {
  static List<({String name, int r, int g, int b})>? _entries;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    if (_entries != null) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/colornames.json');
      final decoded = json.decode(raw) as List<dynamic>;
      _entries = [
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            () {
              final hex = (item['hex'] as String).replaceFirst('#', '');
              final val = int.parse(hex, radix: 16);
              return (
                name: item['name'] as String,
                r: (val >> 16) & 0xFF,
                g: (val >> 8) & 0xFF,
                b: val & 0xFF,
              );
            }(),
      ];
    } catch (_) {
      _entries = const [];
    }
  }

  static String? nearestNameSync(Color color) {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return null;

    final cr = (color.r * 255.0).round().clamp(0, 255);
    final cg = (color.g * 255.0).round().clamp(0, 255);
    final cb = (color.b * 255.0).round().clamp(0, 255);

    var bestDist = 1 << 30;
    String? bestName;

    for (final entry in entries) {
      // Weighted perceptual RGB distance (redmean approximation) for fast exact lookup.
      final dr = cr - entry.r;
      final dg = cg - entry.g;
      final db = cb - entry.b;
      final rMean = (cr + entry.r) >> 1;
      final dist =
          (((512 + rMean) * dr * dr) >> 8) +
          4 * dg * dg +
          (((767 - rMean) * db * db) >> 8);
      if (dist == 0) return entry.name;
      if (dist < bestDist) {
        bestDist = dist;
        bestName = entry.name;
      }
    }
    return bestName;
  }
}
