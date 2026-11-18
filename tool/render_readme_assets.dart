// Generates the README lightness rings for `chroma-folio` on a white panel:
//   - build/readme_frames/lightness_rings/*.png -> docs/screenshots/lightness_rings.webp
//   - docs/screenshots/lightness_rings.png, a still of the gray hold
//
// Run via `./tool/generate_assets.sh` (downloads fonts into build/readme_fonts;
// requires `flutter`, `curl`, `ffmpeg`, and `img2webp`).
//
// Two color wheels at lightness 50. The ring is every hue. Inside it the color
// drains away from the center, leaving each hue in gray right under its own
// color: HSL's grays split into light and dark spokes, HSLuv's settle into one
// even gray. Then the color flows back.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsluv/hsluv.dart';

const double _width = 760.0;
const double _height = 424.0;
const double _dpr = 2.0;
const double _lightness = 50.0;
const double _radius = 124.0;
const double _ringWidth = 24.0;
const double _seam = 3.0;
const double _innerEdge = _radius - _ringWidth - _seam;

const int _fps = 30;

/// Seconds spent in color, draining, in gray, and refilling.
const (double, double, double, double) _beats = (1.2, 1.8, 2.6, 1.6);

const _panel = ui.Color(0xFFFFFFFF);
const _panelRadius = 28.0;
const _title = ui.Color(0xFF191918);
const _note = ui.Color(0xFF6B6A66);

void _centeredText(
  ui.Canvas canvas,
  String text,
  ui.TextStyle style, {
  required double x,
  required double baseline,
}) {
  final paragraph =
      (ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1))
            ..pushStyle(style)
            ..addText(text))
          .build()
        ..layout(const ui.ParagraphConstraints(width: 2000));
  canvas.drawParagraph(
    paragraph,
    ui.Offset(
      x - paragraph.maxIntrinsicWidth / 2,
      baseline - paragraph.alphabeticBaseline,
    ),
  );
  paragraph.dispose();
}

/// The gray that looks as light as [rgb] (same relative luminance).
double _grayOf(List<double> rgb) {
  double linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final y =
      0.2126 * linear(rgb[0]) +
      0.7152 * linear(rgb[1]) +
      0.0722 * linear(rgb[2]);
  return y <= 0.0031308 ? 12.92 * y : 1.055 * math.pow(y, 1 / 2.4) - 0.055;
}

// Both wheels skip 8-bit rounding, so every HSLuv gray comes out identical.
List<double> _hsl(double hue) {
  const l = _lightness / 100;
  final a = math.min(l, 1 - l);
  double channel(double n) {
    final k = (n + hue / 30) % 12;
    return l - a * math.max(-1, math.min(math.min(k - 3, 9 - k), 1));
  }

  return [channel(0), channel(8), channel(4)];
}

List<double> _hsluv(double hue) => [
  for (final channel in Hsluv.hsluvToRgb([hue, 100, _lightness]))
    channel.clamp(0, 1).toDouble(),
];

/// A wheel's colors and grays, worked out once and blended for every frame.
class _Wheel {
  new(List<double> Function(double hue) colorAt)
    : colors = Uint8List(_size * _size * 3),
      grays = Uint8List(_size * _size),
      depth = Float32List(_size * _size) {
    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        final dx = (x + 0.5) / _dpr - _radius;
        final dy = (y + 0.5) / _dpr - _radius;
        final distance = math.sqrt(dx * dx + dy * dy);
        final at = y * _size + x;
        // Red at the top, hues running clockwise.
        final hue = (math.atan2(dx, -dy) * 180 / math.pi + 360) % 360;
        final rgb = colorAt(hue);
        for (var c = 0; c < 3; c++) {
          colors[at * 3 + c] = (rgb[c] * 255).round();
        }
        grays[at] = (_grayOf(rgb) * 255).round();
        depth[at] = distance / _innerEdge;
      }
    }
  }

  static final int _size = (_radius * 2 * _dpr).ceil();

  final Uint8List colors;
  final Uint8List grays;

  /// Distance from the center, where 1 is the inside edge of the ring.
  final Float32List depth;

  /// Gray has spread from the center to [reach], with a soft front.
  Future<ui.Image> frame(double reach) {
    const softness = 0.16;
    final front = reach * (1 + softness);
    final pixels = Uint8List(_size * _size * 4);
    for (var at = 0; at < depth.length; at++) {
      final d = depth[at];
      final gray = d > 1.01
          ? 0.0
          : ((front - d) / softness).clamp(0.0, 1.0).toDouble();
      for (var c = 0; c < 3; c++) {
        final color = colors[at * 3 + c];
        pixels[at * 4 + c] = (color + (grays[at] - color) * gray).round();
      }
      pixels[at * 4 + 3] = 255;
    }
    final decoded = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      _size,
      _size,
      ui.PixelFormat.rgba8888,
      decoded.complete,
    );
    return decoded.future;
  }
}

void _paintWheel(ui.Canvas canvas, ui.Offset center, ui.Image image) {
  final bounds = ui.Rect.fromCircle(center: center, radius: _radius);
  final shape = ui.Path()
    ..fillType = ui.PathFillType.evenOdd
    ..addOval(bounds)
    ..addOval(ui.Rect.fromCircle(center: center, radius: _innerEdge + _seam))
    ..addOval(ui.Rect.fromCircle(center: center, radius: _innerEdge));
  canvas
    ..save()
    ..clipPath(shape)
    ..drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      bounds,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    )
    ..restore();
}

/// How far the gray has spread at [seconds] into the loop.
double _reachAt(double seconds) {
  final (color, drain, gray, refill) = _beats;
  double ease(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
  if (seconds < color) return 0;
  if (seconds < color + drain) return ease((seconds - color) / drain);
  if (seconds < color + drain + gray) return 1;
  return 1 - ease((seconds - color - drain - gray) / refill);
}

Future<void> _savePng(ui.Picture picture, String path) async {
  final image = await picture.toImage(
    (_width * _dpr).round(),
    (_height * _dpr).round(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(byteData!.buffer.asUint8List());
  image.dispose();
}

Future<void> _loadFonts() async {
  Future<void> load(String family, String file) async {
    final font = File('build/readme_fonts/$file');
    if (!font.existsSync()) {
      throw StateError(
        'Missing ${font.path}. Run ./tool/generate_assets.sh to fetch fonts.',
      );
    }
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
    await loader.load();
  }

  await load('Serif', 'InstrumentSerif-Regular.ttf');
  await load('Mono', 'JetBrainsMono.ttf');
}

void main() {
  test('render chroma-folio README lightness rings', () async {
    await _loadFonts();

    const wheelY = 36 + _radius;
    final wheels = [
      (
        x: _width * 0.27,
        name: 'HSL',
        note: 'the grays disagree',
        wheel: _Wheel(_hsl),
      ),
      (
        x: _width * 0.73,
        name: 'HSLuv',
        note: 'the grays agree',
        wheel: _Wheel(_hsluv),
      ),
    ];

    Future<void> render(double reach, String path) async {
      final images = [for (final w in wheels) await w.wheel.frame(reach)];
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..scale(_dpr, _dpr)
        ..drawRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTWH(0, 0, _width, _height),
            const ui.Radius.circular(_panelRadius),
          ),
          ui.Paint()..color = _panel,
        );
      for (final (i, w) in wheels.indexed) {
        _paintWheel(canvas, ui.Offset(w.x, wheelY), images[i]);
        _centeredText(
          canvas,
          w.name,
          ui.TextStyle(
            fontFamily: 'Serif',
            fontSize: 34,
            color: _title,
            letterSpacing: -0.34,
          ),
          x: w.x,
          baseline: wheelY + _radius + 50,
        );
        _centeredText(
          canvas,
          w.note,
          ui.TextStyle(
            fontFamily: 'Mono',
            fontSize: 11,
            color: _note,
            fontVariations: const [ui.FontVariation('wght', 500)],
          ),
          x: w.x,
          baseline: wheelY + _radius + 72,
        );
      }
      await _savePng(recorder.endRecording(), path);
      for (final image in images) {
        image.dispose();
      }
    }

    await render(1, 'docs/screenshots/lightness_rings.png');

    final (color, drain, gray, refill) = _beats;
    final frames = ((color + drain + gray + refill) * _fps).round();
    for (var frame = 0; frame < frames; frame++) {
      final name = frame.toString().padLeft(4, '0');
      await render(
        _reachAt(frame / _fps),
        'build/readme_frames/lightness_rings/frame_$name.png',
      );
    }
  }, timeout: Timeout.none);
}
