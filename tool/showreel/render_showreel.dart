// Renders the Chroma Folio showreel: 36 s, 1920×1080, 60 fps, into
// build/showreel/chroma_folio_showreel.mp4.
//
// Run via `./tool/showreel/render.sh` (fetches fonts; needs `ffmpeg`).
//
// The app in the middle is the real StudioApp. Its reels, solid and scale move
// because the script below drives the cubit and real gestures frame by frame.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chroma_folio/blocs/studio_cubit.dart';
import 'package:chroma_folio/main.dart';
import 'package:chroma_folio/models/accessibility_utils.dart';
import 'package:chroma_folio/models/color_spaces.dart';
import 'package:chroma_folio/widgets/github_mark.dart';
import 'package:chroma_folio/widgets/palette_poster.dart';
import 'package:chroma_folio/widgets/studio_theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hsluv/hsluv.dart';
import 'package:hsluv/hsluvcolor.dart';
import 'package:material_ui/material_ui.dart';

const _fps = 60;
const _seconds = 36.0;
const _stage = Size(1280, 720);
const _pixelRatio = 1.5;
const _appSize = Size(1200, 700);
const _output = 'build/showreel/chroma_folio_showreel.mp4';

const _paper = Color(0xFFF6F4EE);
const _ink = Color(0xFF191918);
const _muted = Color(0xFF6B6A66);

const _riso = (
  pink: Color(0xFFFF48B0),
  yellow: Color(0xFFFFE800),
  blue: Color(0xFF0078BF),
  orange: Color(0xFFFF6C2F),
  green: Color(0xFF00A95C),
  purple: Color(0xFF765BA7),
);

const _starterStyles = [
  PosterStyle.overprint,
  PosterStyle.arches,
  PosterStyle.sun,
  PosterStyle.grid,
  PosterStyle.sun,
  PosterStyle.grid,
  PosterStyle.overprint,
  PosterStyle.arches,
  PosterStyle.arches,
  PosterStyle.sun,
  PosterStyle.grid,
  PosterStyle.overprint,
];

// ─── Timing ──────────────────────────────────────────────────────────────────

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();
double _lerp(double a, double b, double x) => a + (b - a) * x;
double _expoOut(double x) => x >= 1 ? 1 : 1 - math.pow(2, -10 * x).toDouble();
double _expoIn(double x) => x <= 0 ? 0 : math.pow(2, 10 * x - 10).toDouble();
double _expoInOut(double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  return x < 0.5
      ? math.pow(2, 20 * x - 10) / 2
      : (2 - math.pow(2, -20 * x + 10)) / 2;
}

double _cubicIn(double x) => x * x * x;
double _cubicOut(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _cubicInOut(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
double _backOut(double x, [double s = 1.7]) {
  final y = x - 1;
  return 1 + (s + 1) * y * y * y + s * y * y;
}

/// Overshoots and settles, like the reels do.
double _spring(double x) =>
    x >= 1 ? 1 : 1 - math.exp(-6.5 * x) * math.cos(2 * math.pi * 1.5 * x);

// ─── Type ────────────────────────────────────────────────────────────────────

TextStyle _serif(double size, {bool italic = false, Color color = _ink}) =>
    TextStyle(
      fontFamily: 'serif',
      fontSize: size,
      height: 1.0,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: -size * 0.02,
      color: color,
    );

TextStyle _mono(
  double size, {
  Color color = _muted,
  FontWeight weight = FontWeight.w500,
  double spacing = 0,
}) => TextStyle(
  fontFamily: 'monospace',
  fontSize: size,
  height: 1.0,
  fontWeight: weight,
  letterSpacing: spacing,
  color: color,
  fontFeatures: const [ui.FontFeature.tabularFigures()],
);

TextStyle _sans(
  double size, {
  Color color = _ink,
  FontWeight weight = FontWeight.w600,
}) => TextStyle(
  fontFamily: 'Roboto',
  fontSize: size,
  height: 1.0,
  fontWeight: weight,
  color: color,
);

/// Lines of serif words that rise through a mask one after another, and
/// leave upward at [end]. Words wrapped in `*` are italic.
class _Words extends StatelessWidget {
  const new(
    this.t, {
    required this.lines,
    required this.start,
    this.end = 99,
    this.size = 64,
  });

  static const _stagger = 0.05;

  final double t;
  final List<String> lines;
  final double start;
  final double end;
  final double size;

  @override
  Widget build(BuildContext context) {
    var index = 0;
    var italic = false;
    final rows = <Widget>[];
    for (final (row, line) in lines.indexed) {
      final words = <Widget>[];
      for (var word in line.split(' ')) {
        var wordItalic = italic;
        if (word.startsWith('*')) {
          word = word.substring(1);
          wordItalic = true;
          italic = true;
        }
        if (word.endsWith('*')) {
          word = word.substring(0, word.length - 1);
          italic = false;
        }
        final delay = index * _stagger;
        final rise = _expoOut(_seg(t, start + delay, start + delay + 0.65));
        final leave = _cubicIn(
          _seg(t, end + index * 0.03, end + index * 0.03 + 0.34),
        );
        final y = (1 - rise) * 1.7 - leave * 1.7;
        if (words.isNotEmpty) words.add(SizedBox(width: size * 0.24));
        words.add(
          ClipRect(
            clipper: _WordMask(size),
            child: Padding(
              padding: EdgeInsets.only(top: size * 0.12, bottom: size * 0.24),
              child: FractionalTranslation(
                translation: Offset(0, y),
                child: Transform.rotate(
                  angle: (1 - rise) * 0.05,
                  alignment: Alignment.bottomLeft,
                  child: Text(word, style: _serif(size, italic: wordItalic)),
                ),
              ),
            ),
          ),
        );
        index++;
      }
      rows.add(
        Transform.translate(
          offset: Offset(0, -row * size * 0.3),
          child: Row(mainAxisSize: MainAxisSize.min, children: words),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

/// The window a word rises through. It reaches below and beside the word's
/// box so italic descenders and overhangs aren't cut off.
class _WordMask extends CustomClipper<Rect> {
  new(this.fontSize);

  final double fontSize;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -fontSize * 0.12,
    0,
    size.width + fontSize * 0.12,
    size.height + fontSize * 0.14,
  );

  @override
  bool shouldReclip(_WordMask old) => old.fontSize != fontSize;
}

void _text(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset at, {
  double opacity = 1,
  double anchorX = 0,
}) {
  if (opacity <= 0) return;
  final color = style.color ?? _ink;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(color: color.withValues(alpha: color.a * opacity)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, at - Offset(painter.width * anchorX, 0));
  painter.dispose();
}

/// [from] rolls up and out while [to] rolls in, like a split-flap.
void _roll(
  Canvas canvas,
  String from,
  String to,
  double p,
  TextStyle style,
  Offset at, {
  double anchorX = 0,
  double opacity = 1,
}) {
  if (p <= 0 || from == to) {
    _text(canvas, from, style, at, anchorX: anchorX, opacity: opacity);
    return;
  }
  if (p >= 1) {
    _text(canvas, to, style, at, anchorX: anchorX, opacity: opacity);
    return;
  }
  final h = style.fontSize! * 1.4;
  canvas
    ..save()
    ..clipRect(Rect.fromLTWH(at.dx - 300, at.dy - 3, 600, h));
  _text(
    canvas,
    from,
    style,
    at.translate(0, -h * p),
    anchorX: anchorX,
    opacity: opacity * (1 - p),
  );
  _text(
    canvas,
    to,
    style,
    at.translate(0, h * (1 - p)),
    anchorX: anchorX,
    opacity: opacity * p,
  );
  canvas.restore();
}

Color _rgb(List<double> c) => Color.from(
  alpha: 1,
  red: c[0].clamp(0.0, 1.0),
  green: c[1].clamp(0.0, 1.0),
  blue: c[2].clamp(0.0, 1.0),
);

// ─── Scene 1: HSL lies ───────────────────────────────────────────────────────

class _Tile {
  factory(double hue) {
    final hsl = HSLColor.fromAHSL(1, hue, 1, 0.5).toColor();
    final luv = Hsluv.rgbToHsluv([hsl.r, hsl.g, hsl.b]);
    return _Tile._(
      hsl: hsl,
      lightness: luv[2],
      hsluvHue: luv[0],
      hsluv: _rgb(Hsluv.hsluvToRgb([luv[0], 100, 50])),
      gray: _rgb(Hsluv.hsluvToRgb([0, 0, luv[2]])),
      hslLabel: 'hsl(${hue.round()} 100% 50%)',
      hsluvLabel: 'hsluv(${luv[0].round()} 100 50)',
    );
  }

  const new _({
    required this.hsl,
    required this.lightness,
    required this.hsluvHue,
    required this.hsluv,
    required this.gray,
    required this.hslLabel,
    required this.hsluvLabel,
  });

  final Color hsl;
  final double lightness;
  final double hsluvHue;
  final Color hsluv;
  final Color gray;
  final String hslLabel;
  final String hsluvLabel;
}

final _tiles = [
  for (final hue in const [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]) _Tile(hue),
];

const _tileW = 150.0;
const _tileGap = 22.0;
const _rowLeft = 135.0;
const _rowBottom = 560.0;

/// The scan bar passes twice: over the HSL colors, then over the HSLuv ones.
const _scans = [(start: 1.1, end: 2.1), (start: 4.2, end: 4.95)];

/// When the HSLuv colors come back after the second scan proves them gray.
const _colorBack = 5.0;
double _tileHeight(double lightness) => 70 + 260 * lightness / 100;
final _baseHeight = _tileHeight(50);
final _gray50 = _rgb(Hsluv.hsluvToRgb([0, 0, 50]));

double _scanX(double t, int pass) => _lerp(
  _rowLeft - 60,
  _rowLeft + 6 * _tileW + 5 * _tileGap + 60,
  _cubicInOut(_seg(t, _scans[pass].start, _scans[pass].end)),
);

/// When the first scan crosses the middle of each tile.
final _passTimes = [
  for (var i = 0; i < 6; i++)
    () {
      final x = _rowLeft + i * (_tileW + _tileGap) + _tileW / 2;
      var lo = _scans[0].start, hi = _scans[0].end;
      for (var k = 0; k < 40; k++) {
        final mid = (lo + hi) / 2;
        if (_scanX(mid, 0) < x) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      return lo;
    }(),
];

double _fixAt(int i) => 3.3 + i * 0.08;

class _TilesPainter extends CustomPainter {
  new(this.t, this.tray);

  final double t;

  /// Where the palette strip sits in the app, so the tiles can land on it.
  final Rect tray;

  @override
  void paint(Canvas canvas, Size size) {
    final merge = _expoInOut(_seg(t, 5.2, 5.6));
    final fly = _expoInOut(_seg(t, 5.4, 6.2));
    final vanish = 1 - _seg(t, 6.2, 6.3);
    if (vanish <= 0) return;

    final gap = _tileGap * (1 - merge);
    final rowWidth = 6 * _tileW + 5 * gap;
    final left0 = (size.width - rowWidth) / 2;
    final strip = Rect.fromLTWH(
      left0,
      _rowBottom - _baseHeight,
      rowWidth,
      _baseHeight,
    );
    Rect landed(Rect r) {
      final sx = tray.width / strip.width;
      final sy = tray.height / strip.height;
      return Rect.fromLTWH(
        tray.left + (r.left - strip.left) * sx,
        tray.top + (r.top - strip.top) * sy,
        r.width * sx,
        r.height * sy,
      );
    }

    final labels = 1 - _seg(t, 5.05, 5.25);
    final guide = _seg(t, 0.15, 0.3) * (1 - _seg(t, 5.05, 5.25));
    if (guide > 0) {
      final y = _rowBottom - _baseHeight;
      final paint = Paint()
        ..color = _ink.withValues(alpha: 0.35 * guide)
        ..strokeWidth = 1.2;
      final reach = _lerp(
        _rowLeft - 40,
        _rowLeft + rowWidth + 40,
        _expoOut(_seg(t, 0.2, 0.9)),
      );
      for (var x = _rowLeft - 40; x < reach; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
      }
      _text(
        canvas,
        'L* 50',
        _mono(11, color: _ink, weight: FontWeight.w600),
        Offset(_rowLeft - 48, y - 5),
        opacity: guide,
        anchorX: 1,
      );
    }

    for (final (i, tile) in _tiles.indexed) {
      const dy = 0.0;
      final measured = _spring(_seg(t, _passTimes[i], _passTimes[i] + 0.8));
      final fixed = _spring(_seg(t, _fixAt(i) - 0.05, _fixAt(i) + 0.75));
      var h = _lerp(_baseHeight, _tileHeight(tile.lightness), measured);
      h = _lerp(h, _baseHeight, fixed);
      h = _lerp(h, _baseHeight, merge);

      var rect = Rect.fromLTWH(
        left0 + i * (_tileW + gap),
        _rowBottom - h + dy,
        _tileW,
        h,
      );
      rect = Rect.lerp(rect, landed(rect), fly)!;
      final outer = _lerp(18, 6, fly);
      final inner = outer * (1 - merge);
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(i == 0 ? outer : inner),
        bottomLeft: Radius.circular(i == 0 ? outer : inner),
        topRight: Radius.circular(i == 5 ? outer : inner),
        bottomRight: Radius.circular(i == 5 ? outer : inner),
      );

      double grayedBy(int pass) => t < _scans[pass].start
          ? 0
          : ((_scanX(t, pass) - rect.left) / _tileW).clamp(0.0, 1.0);
      final proof =
          grayedBy(1) *
          (1 - _cubicInOut(_seg(t, _colorBack, _colorBack + 0.16)));
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        rect,
        Paint()
          ..color = Color.lerp(
            tile.hsl,
            tile.gray,
            grayedBy(0),
          )!.withValues(alpha: vanish),
      );
      final fill = _cubicInOut(_seg(t, _fixAt(i) - 0.15, _fixAt(i) + 0.35));
      if (fill > 0) {
        final top = rect.bottom - rect.height * fill * 1.1;
        final amplitude = 9 * math.sin(fill * math.pi);
        final wave = Path()..moveTo(rect.left, rect.bottom);
        for (var x = 0.0; x <= rect.width; x += 4) {
          wave.lineTo(
            rect.left + x,
            top + amplitude * math.sin(x * 0.055 + t * 16 + i),
          );
        }
        wave
          ..lineTo(rect.right, rect.bottom)
          ..close();
        canvas.drawPath(
          wave,
          Paint()
            ..color = Color.lerp(
              tile.hsluv,
              _gray50,
              proof,
            )!.withValues(alpha: vanish),
        );
      }
      canvas.restore();

      if (labels > 0) {
        final cx = rect.center.dx;
        const y = _rowBottom + 18 + dy;
        final main = _mono(15, color: _ink, weight: FontWeight.w700);
        final sub = _mono(10.5);
        final measuredLabel = 'L* ${tile.lightness.round()}';
        final rollFix = _expoOut(_seg(t, _fixAt(i), _fixAt(i) + 0.3));
        final rollMeasure = _expoOut(
          _seg(t, _passTimes[i], _passTimes[i] + 0.3),
        );
        if (rollFix > 0) {
          _roll(
            canvas,
            measuredLabel,
            'L* 50',
            rollFix,
            main,
            Offset(cx, y),
            anchorX: 0.5,
            opacity: labels,
          );
          _roll(
            canvas,
            tile.hslLabel,
            tile.hsluvLabel,
            rollFix,
            sub,
            Offset(cx, y + 22),
            anchorX: 0.5,
            opacity: labels,
          );
        } else {
          _roll(
            canvas,
            'L 50%',
            measuredLabel,
            rollMeasure,
            main,
            Offset(cx, y),
            anchorX: 0.5,
            opacity: labels,
          );
          _text(
            canvas,
            tile.hslLabel,
            sub,
            Offset(cx, y + 22),
            anchorX: 0.5,
            opacity: labels,
          );
        }
      }
    }

    for (final (pass, scan) in _scans.indexed) {
      if (t <= scan.start - 0.05 || t >= scan.end + 0.1) continue;
      final x = _scanX(t, pass);
      final alpha =
          _seg(t, scan.start - 0.05, scan.start + 0.05) *
          (1 - _seg(t, scan.end, scan.end + 0.1));
      canvas.drawRect(
        Rect.fromLTWH(x - 40, _rowBottom - 360, 40, 380),
        Paint()
          ..shader = ui.Gradient.linear(Offset(x - 40, 0), Offset(x, 0), [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.5 * alpha),
          ]),
      );
      canvas.drawRect(
        Rect.fromLTWH(x - 1.25, _rowBottom - 360, 2.5, 380),
        Paint()..color = _ink.withValues(alpha: alpha),
      );
      _text(
        canvas,
        'MEASURING L*',
        _mono(10, color: _ink, weight: FontWeight.w700, spacing: 1.2),
        Offset(x + 8, _rowBottom - 360),
        opacity: alpha,
      );
    }
  }

  @override
  bool shouldRepaint(_TilesPainter old) => old.t != t || old.tray != tray;
}

class _SpaceTag extends CustomPainter {
  new(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final show = 1 - _seg(t, 5.05, 5.25);
    if (show <= 0) return;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 92, 0, 92, 30),
      const Radius.circular(99),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _ink.withValues(alpha: show),
    );
    _roll(
      canvas,
      'HSL',
      'HSLUV',
      _expoOut(_seg(t, 3.2, 3.5)),
      _mono(12, color: _ink, weight: FontWeight.w700, spacing: 1.4),
      Offset(size.width - 46, 9),
      anchorX: 0.5,
      opacity: show,
    );
  }

  @override
  bool shouldRepaint(_SpaceTag old) => old.t != t;
}

// ─── Camera on the app window ────────────────────────────────────────────────

class _Cam {
  const new(
    this.time,
    this.center,
    this.scale, {
    this.rx = 0,
    this.ry = 0,
    this.focus = const Offset(600, 350),
    this.ease = _expoInOut,
  });

  final double time;
  final Offset center;
  final double scale;
  final double rx;
  final double ry;
  final Offset focus;

  /// Easing used to arrive at this key.
  final double Function(double) ease;

  Matrix4 get matrix => Matrix4.identity()
    ..translateByDouble(center.dx, center.dy, 0, 1)
    ..multiply(Matrix4.identity()..setEntry(3, 2, 0.0006))
    ..rotateX(rx)
    ..rotateY(ry)
    ..scaleByDouble(scale, scale, 1, 1)
    ..translateByDouble(-focus.dx, -focus.dy, 0, 1);

  static _Cam lerp(_Cam a, _Cam b, double x) => _Cam(
    0,
    Offset.lerp(a.center, b.center, x)!,
    _lerp(a.scale, b.scale, x),
    rx: _lerp(a.rx, b.rx, x),
    ry: _lerp(a.ry, b.ry, x),
    focus: Offset.lerp(a.focus, b.focus, x)!,
  );
}

class _Camera {
  new(this.keys);

  final List<_Cam> keys;

  Matrix4 at(double t) {
    var i = keys.lastIndexWhere((k) => k.time <= t);
    if (i < 0) i = 0;
    final a = keys[i];
    if (i == keys.length - 1) return a.matrix;
    final b = keys[i + 1];
    return _Cam.lerp(a, b, b.ease(_seg(t, a.time, b.time))).matrix;
  }
}

// ─── Wipes ───────────────────────────────────────────────────────────────────

/// Arches that sweep across from [origin], covering the frame for a moment
/// at [coverAt] and revealing the next shot behind them.
class _ArchWipe extends CustomPainter {
  new(this.t, this.start, this.origin, this.colors);

  final double t;
  final double start;
  final Offset origin;
  final List<Color> colors;

  static double coverAt(double start) => start + 0.44;
  static double endAt(double start) => start + 0.95;

  @override
  void paint(Canvas canvas, Size size) {
    const reach = 1600.0;
    for (final (k, color) in colors.indexed) {
      final a = start + k * 0.06;
      final outer = reach * _expoInOut(_seg(t, a, a + 0.42));
      final inner = reach * _expoInOut(_seg(t, a + 0.34, a + 0.8));
      if (outer <= inner) continue;
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCircle(center: origin, radius: outer))
          ..addOval(Rect.fromCircle(center: origin, radius: inner)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ArchWipe old) => old.t != t;
}

/// A circle that opens from the middle until it covers the whole box.
class _Iris extends CustomClipper<Rect> {
  new(this.p);

  final double p;

  @override
  Rect getClip(Size size) => Rect.fromCircle(
    center: size.center(Offset.zero),
    radius: p * size.longestSide * 0.62,
  );

  @override
  bool shouldReclip(_Iris old) => old.p != p;
}

// ─── Copy reel ───────────────────────────────────────────────────────────────

const _copyFormats = ['Hex', 'CSS', 'Display P3', 'Flutter', 'Tailwind'];
const _copyStops = [30.45, 30.8, 31.15, 31.5];

double _copyIndex(double t) {
  var index = 0.0;
  for (final stop in _copyStops) {
    index += _backOut(_seg(t, stop, stop + 0.26), 2.0);
  }
  return index;
}

class _CopyReel extends CustomPainter {
  new(this.t, this.samples);

  final double t;
  final List<String> samples;

  static const _row = 128.0;

  @override
  void paint(Canvas canvas, Size size) {
    final enter = _expoOut(_seg(t, 29.8, 30.3));
    final open = _expoInOut(_seg(t, 31.95, 32.4));
    final index = _copyIndex(t);
    const lensRect = Rect.fromLTWH(488, 296, 700, 128);
    final lens = RRect.fromRectAndRadius(
      Rect.lerp(lensRect, Offset.zero & size, open)!,
      Radius.circular(_lerp(30, 0, open)),
    );
    final itemsAlpha = enter * (1 - _seg(t, 31.9, 32.1));
    final slide = (1 - enter) * 220;

    void items(Color color, double Function(double distance) alpha) {
      for (final (i, name) in _copyFormats.indexed) {
        final distance = i - index;
        final a = alpha(distance.abs()) * itemsAlpha;
        if (a <= 0) continue;
        _text(
          canvas,
          name,
          _serif(92, italic: true, color: color),
          Offset(
            lensRect.left + 40,
            lensRect.top + 14 + distance * _row + slide,
          ),
          opacity: a,
        );
      }
    }

    items(_ink, (d) => (0.32 - d * 0.1).clamp(0.0, 1.0));

    canvas.drawRRect(
      lens.shift(const Offset(0, 14)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10 * enter * (1 - open))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawRRect(
      lens,
      Paint()
        ..color = Color.lerp(
          Colors.white,
          _paper,
          open,
        )!.withValues(alpha: enter),
    );
    canvas.drawRRect(
      lens.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _ink.withValues(alpha: 0.10 * enter * (1 - open)),
    );
    canvas
      ..save()
      ..clipRRect(lens);
    items(_ink, (d) => (1 - d * 1.2).clamp(0.0, 1.0));
    canvas.restore();

    final current = index.round().clamp(0, samples.length - 1);
    final settle = _seg(t, 30.05, 30.3) * (1 - _seg(t, 31.85, 32.0));
    _text(
      canvas,
      samples[current],
      _mono(17, color: _ink, weight: FontWeight.w600),
      Offset(lensRect.left + 44, lensRect.bottom + 30),
      opacity: settle,
    );
  }

  @override
  bool shouldRepaint(_CopyReel old) => old.t != t;
}

// ─── End card ────────────────────────────────────────────────────────────────

class _Sunrise extends CustomPainter {
  new(this.t);

  final double t;

  static const horizon = 580.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = _paper);
    final rise = _expoOut(_seg(t, 32.35, 33.6));
    final drift = _seg(t, 33.6, 36) * 16;
    final sun = Offset(640, _lerp(1040, 640, rise) - drift);
    canvas.drawCircle(sun, 262, Paint()..color = _riso.pink);

    final bands = [_riso.yellow, _riso.blue, _riso.orange, _riso.green];
    for (final (k, color) in bands.indexed) {
      final slide = _expoOut(_seg(t, 32.6 + k * 0.1, 33.5 + k * 0.1));
      final dir = k.isEven ? -1 : 1;
      canvas.drawRect(
        Rect.fromLTWH(
          (1 - slide) * 1400 * dir,
          horizon + k * 36,
          size.width,
          36,
        ),
        Paint()
          ..color = color
          ..blendMode = BlendMode.multiply,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Sunrise old) => old.t != t;
}

class _Sparks extends CustomPainter {
  new(this.p);

  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    if (p <= 0 || p >= 1) return;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = _riso.yellow.withValues(alpha: 1 - p)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 8; k++) {
      final angle = k * math.pi / 4;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + dir * (14 + 16 * _expoOut(p)),
        center + dir * (18 + 26 * _expoOut(p)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Sparks old) => old.p != p;
}

// ─── The reel ────────────────────────────────────────────────────────────────

const _solidWipe = 10.4;
final _solidCover = _ArchWipe.coverAt(_solidWipe);
const _solidEnd = 20.3;

/// The app window turns edge-on here, which hides the cut between lenses.
const _flipAt = 20.95;

/// When the camera has filled the frame with a harmony poster.
const _posterCover = 25.3;

const _turn = (start: 11.5, end: 12.3);
const _lift = (start: 13.45, end: 15.4);
const _pick = (start: 15.85, end: 17.55);

/// The solid opens in OKLCH, whose lopsided shape shows every turn.
const _solidSpace = ColorSpaceMode.oklch;
const _morphs = [
  (at: 17.95, space: ColorSpaceMode.hsluv),
  (at: 18.8, space: ColorSpaceMode.hct),
  (at: 19.65, space: ColorSpaceMode.oklch),
];

typedef _Beat = ({
  double at,
  List<String> lines,
  Widget Function(double t) note,
});

Widget _note(String text, {Color color = _ink}) => Text(
  text,
  style: _mono(11, color: color, weight: FontWeight.w700, spacing: 1.3),
);

final List<_Beat> _solidBeats = [
  (
    at: 10.95,
    lines: const ['See the whole', '*gamut.*'],
    note: (_) => _note('DRAG TO TURN IT'),
  ),
  (
    at: 13.25,
    lines: const ['Slice it by', '*lightness.*'],
    note: (_) => _note('DRAG UP AND DOWN'),
  ),
  (
    at: 15.65,
    lines: const ['Pick right', '*on the cut.*'],
    note: (_) => _note('DRAG ALONG THE RIM'),
  ),
  (
    at: 17.75,
    lines: const ['Morph between', '*color spaces.*'],
    note: (t) => Row(
      children: [
        for (final morph in _morphs)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _note(
              morph.space.label.toUpperCase(),
              color:
                  _morphs.lastIndexWhere((m) => t >= m.at) ==
                      _morphs.indexOf(morph)
                  ? _ink
                  : _muted.withValues(alpha: 0.4),
            ),
          ),
      ],
    ),
  ),
];

class _Shots {
  Rect tray = Rect.zero;
  Offset solidCenter = const Offset(780, 420);
  Rect solidCanvas = Rect.zero;
  Offset scaleFrom = Offset.zero;
  Offset scaleTo = Offset.zero;
  Offset scaleCenter = Offset.zero;
  Rect harmony = Rect.zero;
  ({List<Color> colors, int background, PosterStyle style})? harmonyPoster;
  late _Camera camera;
}

class _Showreel extends StatelessWidget {
  const new({
    required this.clock,
    required this.cubit,
    required this.appKey,
    required this.shots,
  });

  final ValueNotifier<double> clock;
  final StudioCubit cubit;
  final GlobalKey appKey;
  final _Shots shots;

  @override
  Widget build(BuildContext context) {
    final app = SizedBox.fromSize(
      key: appKey,
      size: _appSize,
      child: MediaQuery(
        data: const MediaQueryData(
          size: _appSize,
          devicePixelRatio: _pixelRatio,
        ),
        child: StudioApp(cubit: cubit),
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      child: app,
      builder: (context, t, app) {
        final appVisible = t >= 5.4 && t < _posterCover + 0.1;
        final appOpacity = _cubicInOut(_seg(t, 5.9, 6.3));
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned.fill(child: ColoredBox(color: _paper)),
            if (t < 5.5) ..._opening(t),
            Positioned(
              left: 0,
              top: 0,
              child: Offstage(
                offstage: !appVisible,
                child: Transform(
                  transform: shots.camera.at(t),
                  child: Opacity(
                    opacity: appOpacity,
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _ink.withValues(alpha: 0.08)),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 70,
                              offset: const Offset(0, 34),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: app,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(child: Stack(children: _overlays(t))),
            ),
          ],
        );
      },
    );
  }

  /// Everything drawn over the app; none of it takes the scripted taps.
  List<Widget> _overlays(double t) {
    return [
      if (t < 6.3)
        Positioned.fill(
          child: CustomPaint(painter: _TilesPainter(t, shots.tray)),
        ),
      if (t > 6.3 && t < _solidWipe + 0.5) ..._heroCaption(t),
      if (t > _solidBeats.first.at - 0.1 && t < _solidEnd + 0.4)
        _storyCard(t, beats: _solidBeats, end: _solidEnd),
      if (t > 21.9 && t < 24.7)
        _card(
          t,
          start: 22.0,
          end: 24.25,
          left: 56,
          bottom: 52,
          lines: const ['Scrub a scale.', '*Harmonies follow.*'],
          note: '50 → 950  ·  LIVE POSTERS',
        ),
      if (t > _solidWipe - 0.05 && t < _ArchWipe.endAt(_solidWipe))
        Positioned.fill(
          child: CustomPaint(
            painter: _ArchWipe(t, _solidWipe, const Offset(0, 720), [
              _riso.pink,
              _riso.yellow,
              _riso.blue,
            ]),
          ),
        ),
      if (t >= _posterCover - 0.15 && t < 29.95) ..._posters(t),
      if (t >= 29.7 && t < 32.45) ..._copy(t),
      if (t >= 32.35) ..._endCard(t),
    ];
  }

  /// One card that stays put while its words change with each beat.
  Widget _storyCard(
    double t, {
    required List<_Beat> beats,
    required double end,
  }) {
    final start = beats.first.at;
    final enter = _expoOut(_seg(t, start, start + 0.6));
    final leave = _cubicIn(_seg(t, end, end + 0.32));
    double wordsEnd(int i) =>
        i + 1 < beats.length ? beats[i + 1].at - 0.3 : end;
    return Positioned(
      left: 56,
      bottom: 52,
      child: Transform.translate(
        offset: Offset(0, (1 - enter) * 60 + leave * 40),
        child: Transform.scale(
          scale: _lerp(0.92, 1, enter),
          alignment: Alignment.bottomLeft,
          child: Opacity(
            opacity: _seg(t, start, start + 0.15) * (1 - leave),
            child: Container(
              width: 452,
              padding: const EdgeInsets.fromLTRB(30, 22, 30, 26),
              decoration: BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 50,
                    offset: const Offset(0, 22),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      for (final (i, beat) in beats.indexed)
                        _Words(
                          t,
                          lines: beat.lines,
                          start: beat.at + (i == 0 ? 0.08 : 0),
                          end: wordsEnd(i),
                          size: 54,
                        ),
                    ],
                  ),
                  Stack(
                    children: [
                      for (final (i, beat) in beats.indexed)
                        Opacity(
                          opacity:
                              _seg(t, beat.at + 0.25, beat.at + 0.5) *
                              (1 - _seg(t, wordsEnd(i), wordsEnd(i) + 0.2)),
                          child: beat.note(t),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _opening(double t) => [
    Positioned(
      left: _rowLeft - 4,
      top: 40,
      child: Stack(
        children: [
          if (t < 2.6)
            _Words(
              t,
              lines: const ['Every color here', 'is *50% lightness.*'],
              start: -2,
              end: 1.9,
              size: 60,
            ),
          if (t > 2.3 && t < 3.8)
            _Words(
              t,
              lines: const ['Your eyes', '*disagree.*'],
              start: 2.4,
              end: 3.15,
              size: 60,
            ),
          if (t > 3.5)
            _Words(
              t,
              lines: const ['Chroma Folio sees', '*what you see.*'],
              start: 3.6,
              end: 5.0,
              size: 60,
            ),
        ],
      ),
    ),
    Positioned(
      right: _rowLeft,
      top: 58,
      width: 120,
      height: 30,
      child: CustomPaint(painter: _SpaceTag(t)),
    ),
  ];

  List<Widget> _heroCaption(double t) {
    final spaces = ['HSLuv', 'OKLCH', 'HCT'];
    final current = t < 9.3 ? 0 : (t < 9.9 ? 1 : 2);
    final show = _seg(t, 7.0, 7.35) * (1 - _seg(t, 10.2, 10.4));
    return [
      Positioned(
        left: 64,
        top: 196,
        child: _Words(
          t,
          lines: const ['Spin', '*a color.*'],
          start: 6.55,
          end: 10.05,
          size: 104,
        ),
      ),
      Positioned(
        left: 70,
        top: 452,
        child: Opacity(
          opacity: show,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HUE  ·  SATURATION  ·  LIGHTNESS',
                style: _mono(
                  11,
                  color: _ink,
                  weight: FontWeight.w700,
                  spacing: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final (i, space) in spaces.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: Text(
                        space,
                        style: _mono(
                          15,
                          color: i == current
                              ? _ink
                              : _muted.withValues(alpha: 0.45),
                          weight: i == current
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _card(
    double t, {
    required double start,
    required double end,
    required double left,
    required double bottom,
    required List<String> lines,
    required String note,
  }) {
    final enter = _expoOut(_seg(t, start, start + 0.55));
    final leave = _expoIn(_seg(t, end, end + 0.28));
    return Positioned(
      left: left,
      bottom: bottom,
      child: Transform.translate(
        offset: Offset(0, (1 - enter) * 60 - leave * 30),
        child: Transform.scale(
          scale: _lerp(0.92, 1, enter),
          alignment: Alignment.bottomLeft,
          child: Opacity(
            opacity: _seg(t, start, start + 0.12) * (1 - leave),
            child: Container(
              padding: const EdgeInsets.fromLTRB(30, 22, 34, 26),
              decoration: BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 50,
                    offset: const Offset(0, 22),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Words(
                    t,
                    lines: lines,
                    start: start + 0.08,
                    end: end,
                    size: 54,
                  ),
                  Text(
                    note,
                    style: _mono(
                      11,
                      color: _ink,
                      weight: FontWeight.w700,
                      spacing: 1.3,
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

  List<Widget> _posters(double t) {
    final stage = Offset.zero & _stage;
    const cols = 4;
    const marginX = 48.0;
    const gapX = 18.0;
    const top = 116.0;
    const posterH = 158.0;
    const rowPitch = 196.0;
    final posterW = (_stage.width - 2 * marginX - (cols - 1) * gapX) / cols;
    Rect cell(int i) => Rect.fromLTWH(
      marginX + (i % cols) * (posterW + gapX),
      top + (i ~/ cols) * rowPitch,
      posterW,
      posterH,
    );

    const reveals = [25.75, 26.25, 26.75, 27.25];
    const revealOrder = [0, 5, 10, 3];
    const gridStart = 27.85;
    const gridEnd = 29.4;
    final lead = revealOrder.last;
    final toGrid = _expoInOut(_seg(t, gridStart, gridStart + 0.7));
    double leaving(int i) => _cubicIn(
      _seg(t, gridEnd + (i % cols) * 0.04, gridEnd + 0.3 + (i % cols) * 0.04),
    );
    double iris(int k) => _expoInOut(_seg(t, reveals[k], reveals[k] + 0.5));

    PalettePoster starter(int i) => PalettePoster(
      colors: studioStarterPalettes[i].colors,
      background: studioStarterPalettes[i].background,
      style: _starterStyles[i],
    );

    final children = <Widget>[];
    if (t >= gridStart) {
      for (var i = 0; i < 12; i++) {
        if (i == lead) continue;
        final distance = math.max(
          ((i % cols) - (lead % cols)).abs(),
          ((i ~/ cols) - (lead ~/ cols)).abs(),
        );
        final pop = _seg(
          t,
          gridStart + 0.3 + distance * 0.1,
          gridStart + 0.9 + distance * 0.1,
        );
        if (pop <= 0) continue;
        children.add(
          _posterCell(cell(i), starter(i), _backOut(pop), i, leaving(i)),
        );
      }
    }

    final harmony = shots.harmonyPoster;
    final layers = <Widget>[
      if (harmony != null && t < reveals.last + 0.5)
        PalettePoster(
          colors: harmony.colors,
          background: harmony.background,
          style: harmony.style,
        ),
      for (final (k, index) in revealOrder.indexed)
        if (iris(k) > 0 && (k + 1 == revealOrder.length || iris(k + 1) < 1))
          ClipOval(clipper: _Iris(iris(k)), child: starter(index)),
    ];
    final leadRect = Rect.lerp(stage, cell(lead), toGrid)!;
    children.add(
      Positioned.fromRect(
        rect: leadRect,
        child: Opacity(
          opacity:
              _seg(t, _posterCover - 0.12, _posterCover) * (1 - leaving(lead)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_lerp(0, 16, toGrid)),
            child: Stack(fit: StackFit.expand, children: layers),
          ),
        ),
      ),
    );
    if (t >= gridStart) {
      children.add(_posterName(cell(lead), lead, t, leaving(lead)));
      children.add(
        Positioned(
          left: marginX - 3,
          top: 22,
          child: _Words(
            t,
            lines: const ['Twelve starters. *One tap.*'],
            start: gridStart + 0.35,
            end: gridEnd - 0.05,
            size: 46,
          ),
        ),
      );
      children.add(
        Positioned(
          right: marginX,
          top: 52,
          child: Opacity(
            opacity:
                _seg(t, gridStart + 0.7, gridStart + 1.0) *
                (1 - _seg(t, gridEnd, gridEnd + 0.15)),
            child: Text(
              'UNDO BRINGS YOURS BACK',
              style: _mono(
                11,
                color: _ink,
                weight: FontWeight.w700,
                spacing: 1.3,
              ),
            ),
          ),
        ),
      );
    }
    if (t > reveals.first - 0.05 && t < gridStart + 0.4) {
      children.add(
        _card(
          t,
          start: reveals.first,
          end: gridStart - 0.3,
          left: 56,
          bottom: 52,
          lines: const ['Harmonies that', '*look designed.*'],
          note: 'PICKED FOR YOUR COLOR  ·  ONE TAP TO USE',
        ),
      );
    }
    return children;
  }

  Widget _posterCell(
    Rect rect,
    Widget poster,
    double pop,
    int index,
    double exit,
  ) {
    return Positioned.fromRect(
      rect: rect,
      child: Opacity(
        opacity: (pop.clamp(0.0, 1.0)) * (1 - exit),
        child: Transform.scale(
          scale: _lerp(0.5, 1, pop) * _lerp(1, 0.86, exit),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: poster,
                ),
              ),
              Positioned(
                left: 2,
                top: rect.height + 10,
                child: Text(
                  studioStarterPalettes[index].name,
                  style: _serif(19),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterName(Rect rect, int index, double t, double exit) => Positioned(
    left: rect.left + 2,
    top: rect.bottom + 10,
    child: Opacity(
      opacity: _seg(t, 28.25, 28.5) * (1 - exit),
      child: Text(studioStarterPalettes[index].name, style: _serif(19)),
    ),
  );

  List<Widget> _copy(double t) {
    final palette = studioStarterPaletteAt(0);
    String hex(Color c) => StudioColor.fromColor(c).hex;
    final samples = [
      palette.take(4).map((c) => c.hex).join(', '),
      '--color-1: ${palette.first.oklchDisplay};',
      'color(display-p3 ${() {
        final p3 = palette.first.color.withValues(colorSpace: ui.ColorSpace.displayP3);
        return [p3.r, p3.g, p3.b].map((c) => c.clamp(0, 1).toStringAsFixed(3)).join(' ');
      }()})',
      'Color(0xFF${palette.first.hex.substring(1)}),',
      "'500': '${hex(palette.first.color)}',",
    ];
    return [
      Positioned.fill(child: CustomPaint(painter: _CopyReel(t, samples))),
      Positioned(
        left: 92,
        top: 296,
        child: _Words(
          t,
          lines: const ['Copy as'],
          start: 29.8,
          end: 31.8,
          size: 104,
        ),
      ),
    ];
  }

  List<Widget> _endCard(double t) {
    const title = 'Chroma Folio';
    final pill = _backOut(_seg(t, 33.4, 33.95));
    final star = _seg(t, 34.0, 34.7);
    final links = _expoOut(_seg(t, 33.75, 34.3));
    return [
      Positioned.fill(child: CustomPaint(painter: _Sunrise(t))),
      Positioned(
        left: 0,
        right: 0,
        top: 96,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, letter) in title.split('').indexed)
                () {
                  final rise = _expoOut(
                    _seg(t, 32.4 + i * 0.045, 33.4 + i * 0.045),
                  );
                  return ClipRect(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 40),
                      child: FractionalTranslation(
                        translation: Offset(0, (1 - rise) * 1.4),
                        child: Transform.rotate(
                          angle: (1 - rise) * 0.2,
                          alignment: Alignment.bottomLeft,
                          child: Text(letter, style: _serif(164)),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 290,
        child: Opacity(
          opacity: _seg(t, 32.95, 33.4),
          child: Center(
            child: Text(
              'A PERCEPTUAL COLOR STUDIO  —  HSLUV  ·  OKLCH  ·  HCT',
              style: _mono(
                13,
                color: _ink,
                weight: FontWeight.w700,
                spacing: 2.2,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 404,
        child: Center(
          child: Opacity(
            opacity: pill.clamp(0.0, 1.0),
            child: Transform.scale(
              scale:
                  _lerp(0.6, 1, pill) *
                  (1 + 0.025 * math.sin(math.max(0, t - 34.6) * 4)),
              child: Container(
                height: 68,
                padding: const EdgeInsets.only(left: 20, right: 24),
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const IconTheme(
                      data: IconThemeData(color: _paper, size: 28),
                      child: GithubMark(),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Star on GitHub',
                      style: _sans(25, color: _paper, weight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    SizedBox.square(
                      dimension: 26,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: OverflowBox(
                              maxWidth: 90,
                              maxHeight: 90,
                              child: SizedBox.square(
                                dimension: 90,
                                child: CustomPaint(painter: _Sparks(star)),
                              ),
                            ),
                          ),
                          Transform.rotate(
                            angle: (1 - _backOut(star, 2.6)) * -1.2,
                            child: Transform.scale(
                              scale: star > 0
                                  ? _backOut(_seg(star, 0, 0.5), 3)
                                  : 1,
                              child: Icon(
                                Icons.star_rounded,
                                size: 26,
                                color: Color.lerp(
                                  _paper,
                                  _riso.yellow,
                                  _seg(star, 0, 0.2),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 484,
        child: Opacity(
          opacity: links,
          child: Transform.translate(
            offset: Offset(0, (1 - links) * 16),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _paper,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Text(
                    'github.com/bernaferrari/chroma-folio',
                    style: _mono(19, color: _ink, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

// ─── Director ────────────────────────────────────────────────────────────────

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final font = File('build/showreel_fonts/$file');
      if (!font.existsSync()) {
        throw StateError(
          'Missing ${font.path}. Run ./tool/showreel/render.sh.',
        );
      }
      loader.addFont(
        Future.value(ByteData.sublistView(font.readAsBytesSync())),
      );
    }
    await loader.load();
  }

  await load('serif', [
    'InstrumentSerif-Regular.ttf',
    'InstrumentSerif-Italic.ttf',
  ]);
  await load('monospace', ['JetBrainsMono.ttf']);
  await load('Roboto', ['PlusJakartaSans.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  testWidgets('render the Chroma Folio showreel', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    debugDisableShadows = false;
    await tester.runAsync(() async {
      await _loadFonts();
      await ColorNameLookup.ensureLoaded();
    });
    tester.view.physicalSize = _stage * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    final cubit = StudioCubit()
      ..applyColorsToPalette([
        for (final tile in _tiles)
          StudioColor.fromHsluv(HSLuvColor.fromHSL(tile.hsluvHue, 100, 50)),
      ], selectedIndex: 0);
    final clock = ValueNotifier<double>(12.0);
    final appKey = GlobalKey();
    final frameKey = GlobalKey();
    final shots = _Shots()
      ..camera = _Camera(const [_Cam(0, Offset(640, 360), 0.9)]);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: _sans(14),
          child: RepaintBoundary(
            key: frameKey,
            child: _Showreel(
              clock: clock,
              cubit: cubit,
              appKey: appKey,
              shots: shots,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final inApp = find.byKey(appKey);
    RenderBox appBox() =>
        appKey.currentContext!.findRenderObject()! as RenderBox;
    Rect local(Finder finder) {
      final box = tester.renderObject<RenderBox>(finder);
      return MatrixUtils.transformRect(
        box.getTransformTo(appBox()),
        Offset.zero & box.size,
      );
    }

    Finder app(Finder finder) => find.descendant(of: inApp, matching: finder);
    // Switches lenses through the control itself, since the camera can push
    // the tab bar off screen where taps miss.
    void selectLens(String name) {
      final dynamic control = tester.widget(
        app(
          find.byWidgetPredicate(
            (w) => w is StudioSegmentedControl && w.labels.containsValue(name),
          ),
        ),
      );
      final Map labels = control.labels;
      control.onChanged(labels.entries.firstWhere((e) => e.value == name).key);
    }

    Future<void> openTab(String name) async {
      selectLens(name);
      await tester.pump(const Duration(milliseconds: 700));
    }

    // Pre-roll: visit each tab once to learn where things are.
    final swatches = app(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Swatch'),
    );
    var tray = local(swatches.first);
    for (var i = 1; i < swatches.evaluate().length; i++) {
      tray = tray.expandToInclude(local(swatches.at(i)));
    }
    await openTab('Solid');
    shots.solidCanvas = local(
      app(find.byKey(const ValueKey<String>('gamut_solid_canvas'))),
    );
    shots.solidCenter = shots.solidCanvas.center;
    await openTab('Palette');
    shots.scaleFrom = local(app(find.text('100')).first).center;
    shots.scaleTo = local(app(find.text('900')).first).center;
    shots.scaleCenter = local(app(find.text('500')).first).center;
    shots.harmony = local(app(find.byType(PalettePoster)).at(1));
    await openTab('Reels');
    await tester.pump(const Duration(seconds: 1));

    const flat = _Cam(6.2, Offset(640, 360), 0.9);
    shots.tray = MatrixUtils.transformRect(flat.matrix, tray);
    final harmony = shots.harmony;
    final posterScale = math.max(
      _stage.width / harmony.width,
      _stage.height / harmony.height,
    );
    final solid = shots.solidCenter;
    final scale = shots.scaleCenter + const Offset(0, 95);
    final midway = Offset.lerp(solid, scale, 0.5)!;
    shots.camera = _Camera([
      const _Cam(5.4, Offset(640, 372), 0.95),
      flat,
      const _Cam(7.6, Offset(842, 376), 0.8, rx: 0.05, ry: -0.3),
      const _Cam(
        _solidWipe,
        Offset(828, 370),
        0.84,
        rx: 0.04,
        ry: -0.24,
        ease: _cubicInOut,
      ),
      _Cam(
        _solidCover,
        const Offset(760, 340),
        1.6,
        rx: 0.16,
        ry: 0.3,
        focus: solid,
      ),
      _Cam(
        _lift.start - 0.2,
        const Offset(750, 330),
        1.85,
        rx: 0.06,
        ry: 0.08,
        focus: solid,
        ease: _cubicInOut,
      ),
      _Cam(
        _pick.start - 0.2,
        const Offset(750, 326),
        1.95,
        rx: 0.12,
        ry: -0.14,
        focus: solid,
        ease: _cubicInOut,
      ),
      _Cam(
        _morphs.first.at - 0.25,
        const Offset(760, 326),
        2.05,
        rx: 0.05,
        ry: -0.04,
        focus: solid,
        ease: _cubicInOut,
      ),
      _Cam(
        _solidEnd + 0.05,
        const Offset(760, 336),
        1.6,
        rx: 0.14,
        ry: 0.2,
        focus: solid,
        ease: _cubicInOut,
      ),
      _Cam(
        _flipAt,
        const Offset(680, 350),
        1.02,
        rx: 0.06,
        ry: math.pi / 2,
        focus: midway,
        ease: _cubicIn,
      ),
      _Cam(
        _flipAt,
        const Offset(680, 340),
        1.02,
        rx: 0.06,
        ry: -math.pi / 2,
        focus: midway,
      ),
      _Cam(
        21.85,
        const Offset(690, 318),
        1.12,
        rx: 0.18,
        focus: scale,
        ease: _cubicOut,
      ),
      _Cam(
        24.4,
        const Offset(690, 336),
        1.18,
        rx: 0.08,
        focus: scale,
        ease: _cubicInOut,
      ),
      _Cam(
        _posterCover,
        const Offset(640, 360),
        posterScale,
        focus: harmony.center,
      ),
    ]);
    clock.value = 0;
    await tester.pump();

    Offset global(Offset appPoint, double t) =>
        MatrixUtils.transformPoint(shots.camera.at(t), appPoint);

    Directory('build/showreel').createSync(recursive: true);
    final ffmpeg = (await tester.runAsync(
      () => Process.start('ffmpeg', [
        '-y',
        '-loglevel',
        'error',
        '-f',
        'rawvideo',
        '-pix_fmt',
        'rgba',
        '-s',
        '${(_stage.width * _pixelRatio).round()}x${(_stage.height * _pixelRatio).round()}',
        '-r',
        '$_fps',
        '-i',
        '-',
        '-c:v',
        'libx264',
        '-preset',
        'slow',
        '-crf',
        '15',
        '-profile:v',
        'high',
        '-pix_fmt',
        'yuv420p',
        '-movflags',
        '+faststart',
        _output,
      ]),
    ))!;
    final ffmpegErrors = StringBuffer();
    ffmpeg.stderr.listen(
      (bytes) => ffmpegErrors.write(String.fromCharCodes(bytes)),
    );

    final base = cubit.state.activeColor.hsluv;
    TestGesture? solidDrag;
    TestGesture? scaleDrag;
    double? cutLevel;
    final frames = (_seconds * _fps).round();
    var previous = -1.0;
    bool at(double moment, double t) => previous < moment && t >= moment;

    // Real timestamps, so a fast drag lets go with real velocity.
    Duration stamp(double t) => Duration(microseconds: (t * 1e6).round());
    Future<void> drag(Offset appPoint, double t) async {
      final point = global(appPoint, t);
      final gesture = solidDrag;
      if (gesture == null) {
        solidDrag = await tester.createGesture();
        await solidDrag!.down(point, timeStamp: stamp(t));
      } else {
        await gesture.moveTo(point, timeStamp: stamp(t));
      }
    }

    Future<void> release() async {
      await solidDrag?.up(timeStamp: stamp(previous));
      solidDrag = null;
    }

    for (var frame = 0; frame < frames; frame++) {
      final t = frame / _fps;

      if (t >= 6.6 && t <= 9.7) {
        final hue = base.hue + 215 * _expoInOut(_seg(t, 6.6, 8.4));
        final dip = _cubicInOut(_seg(t, 8.5, 8.95));
        final lift = _cubicInOut(_seg(t, 8.95, 9.6));
        final lightness = _lerp(_lerp(50, 26, dip), 64, lift);
        cubit.setActiveColor(
          StudioColor.fromHsluv(HSLuvColor.fromHSL(hue % 360, 100, lightness)),
          recordHistory: false,
        );
      }
      if (at(9.3, t)) cubit.setSpaceMode(ColorSpaceMode.oklch);
      if (at(9.9, t)) cubit.setSpaceMode(ColorSpaceMode.hct);
      if (at(_solidCover, t)) {
        cubit.setSpaceMode(_solidSpace);
        selectLens('Solid');
      }

      // Off the cut, so these drags turn the solid or lift the cut.
      final grip = shots.solidCenter + const Offset(-200, -120);

      // A flick: speeds up, lets go, and the solid coasts.
      if (t >= _turn.start && t <= _turn.end) {
        final x = _seg(t, _turn.start, _turn.end);
        await drag(grip + Offset(360 * x * x, 0), t);
      }
      if (at(_turn.end + 0.01, t)) await release();

      if (t >= _lift.start && t <= _lift.end) {
        final x = _seg(t, _lift.start, _lift.end);
        final dy = x < 0.3
            ? _lerp(0, -60, _cubicInOut(x / 0.3))
            : x < 0.72
            ? _lerp(-60, 95, _cubicInOut((x - 0.3) / 0.42))
            : _lerp(95, 25, _cubicInOut((x - 0.72) / 0.28));
        await drag(grip + Offset(0, dy), t);
      }
      if (at(_lift.end + 0.01, t)) await release();

      // Starts on the axis of the cut, runs out past the rim and circles it,
      // so the pick follows the rim through every hue.
      if (t >= _pick.start && t <= _pick.end) {
        final level = cutLevel ??= cubit.state.activeColor
            .channelsFor(_solidSpace)[2]
            .value;
        final canvas = shots.solidCanvas.size;
        final s = math.max(
          1.0,
          math.min(canvas.width / 1.3, canvas.height / 1.65),
        );
        final axis =
            shots.solidCenter +
            Offset(0, -s * (level / 100 - 0.5) * math.cos(0.5));
        final x = _seg(t, _pick.start, _pick.end);
        final radius = s * 0.55 * 1.2 * _cubicOut(_seg(x, 0, 0.22));
        final angle =
            math.pi / 2 + 2 * math.pi * 0.85 * _cubicInOut(_seg(x, 0.18, 1));
        await drag(
          axis +
              Offset(
                radius * math.cos(angle),
                radius * math.sin(angle) * math.sin(0.5),
              ),
          t,
        );
      }
      if (at(_pick.end + 0.01, t)) await release();

      for (final morph in _morphs) {
        if (at(morph.at, t)) cubit.setSpaceMode(morph.space);
      }
      final morphTurn = (start: _morphs.first.at - 0.1, end: _solidEnd);
      if (t >= morphTurn.start && t <= morphTurn.end) {
        final x = _cubicInOut(_seg(t, morphTurn.start, morphTurn.end));
        await drag(grip + Offset(280 * x, 0), t);
      }
      if (at(morphTurn.end + 0.01, t)) await release();

      if (at(_flipAt, t)) selectLens('Palette');
      if (t >= 22.3 && t <= 23.7) {
        final point = Offset.lerp(
          shots.scaleFrom,
          shots.scaleTo,
          _cubicInOut(_seg(t, 22.3, 23.7)),
        )!;
        if (scaleDrag == null) {
          scaleDrag = await tester.startGesture(global(shots.scaleFrom, t));
        } else {
          await scaleDrag.moveTo(global(point, t));
        }
      }
      if (at(23.72, t)) await scaleDrag?.up();
      if (at(24.6, t)) {
        final poster = tester.widget<PalettePoster>(
          app(find.byType(PalettePoster)).at(1),
        );
        shots.harmonyPoster = (
          colors: poster.colors,
          background: poster.background,
          style: poster.style,
        );
      }

      clock.value = t;
      final elapsed = Duration(microseconds: (frame * 1e6 / _fps).round());
      final before = Duration(microseconds: ((frame - 1) * 1e6 / _fps).round());
      await tester.pump(frame == 0 ? Duration.zero : elapsed - before);
      previous = t;

      await tester.runAsync(() async {
        final boundary =
            frameKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _pixelRatio);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        ffmpeg.stdin.add(bytes!.buffer.asUint8List());
        await ffmpeg.stdin.flush();
        if (frame % 30 == 0 || frame == frames - 1) {
          final png = await (await boundary.toImage(pixelRatio: 0.5))
              .toByteData(format: ui.ImageByteFormat.png);
          File('build/showreel/frames/${frame.toString().padLeft(4, '0')}.png')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        }
      });
    }

    final code = (await tester.runAsync(() async {
      await ffmpeg.stdin.close();
      return ffmpeg.exitCode;
    }))!;
    expect(code, 0, reason: ffmpegErrors.toString());
    debugDisableShadows = true;
  }, timeout: Timeout.none);
}
