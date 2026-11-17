// Generates the README comparison animation for `chroma-folio`:
//   - build/readme_frames/oklch_vs_hsl_solid/*.png -> docs/screenshots/oklch_vs_hsl_solid.webp
//
// Run via `./tool/generate_assets.sh` (downloads fonts into build/readme_fonts;
// requires `flutter`, `curl`, `ffmpeg`, and `img2webp`).
//
// Visual language: the app's own folio. Archival paper, Instrument Serif
// headings, JetBrains Mono readouts, and a named specimen with a palette strip
// under each solid, exactly like the studio's specimen panel.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chroma_folio/models/color_spaces.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const ui.Color _paper = ui.Color(0xFFF6F4EE);
const ui.Color _page = ui.Color(0xFFFCFAF5);
const ui.Color _well = ui.Color(0xFFEFECE4);
const ui.Color _hairline = ui.Color(0xFFE2DED4);
const ui.Color _ink = ui.Color(0xFF191918);
const ui.Color _muted = ui.Color(0xFF6B6A66);

const double _width = 760.0;
const double _height = 492.0;
const double _dpr = 2.0;
const int _frames = 150;
const int _chips = 8;

typedef _Span = (String, ui.TextStyle);

ui.TextStyle _serif(double size, {ui.Color color = _ink}) => ui.TextStyle(
  fontFamily: 'Serif',
  fontSize: size,
  color: color,
  letterSpacing: -size * 0.01,
);

ui.TextStyle _mono(
  double size, {
  ui.Color color = _muted,
  double weight = 500,
}) => ui.TextStyle(
  fontFamily: 'Mono',
  fontSize: size,
  color: color,
  fontWeight: ui.FontWeight.values[(weight / 100).round() - 1],
  fontVariations: [ui.FontVariation('wght', weight)],
  fontFeatures: const [ui.FontFeature.tabularFigures()],
);

enum _Anchor { start, end }

void _text(
  ui.Canvas canvas,
  List<_Span> spans, {
  required double x,
  required double baseline,
  _Anchor anchor = _Anchor.start,
  double maxWidth = 2000,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(maxLines: 1, ellipsis: '…'),
  );
  for (final (text, style) in spans) {
    builder
      ..pushStyle(style)
      ..addText(text)
      ..pop();
  }
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth));
  final width = math.min(paragraph.maxIntrinsicWidth, maxWidth);
  canvas.drawParagraph(
    paragraph,
    ui.Offset(
      anchor == _Anchor.end ? x - width : x,
      baseline - paragraph.alphabeticBaseline,
    ),
  );
  paragraph.dispose();
}

ui.Paint _stroke(ui.Color color, [double width = 1.0]) => ui.Paint()
  ..style = ui.PaintingStyle.stroke
  ..strokeWidth = width
  ..color = color;

String _hex(ui.Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Ink that stays legible on top of [color].
ui.Color _inkOn(ui.Color color) =>
    color.computeLuminance() > 0.36 ? _ink : const ui.Color(0xFFFCFAF5);

/// Familiar CSS color names; the specimen shows the perceptually nearest one.
const List<(String, ui.Color)> _colorNames = [
  ('Crimson', ui.Color(0xFFDC143C)),
  ('Red', ui.Color(0xFFFF0000)),
  ('Tomato', ui.Color(0xFFFF6347)),
  ('Coral', ui.Color(0xFFFF7F50)),
  ('Salmon', ui.Color(0xFFFA8072)),
  ('Orange Red', ui.Color(0xFFFF4500)),
  ('Dark Orange', ui.Color(0xFFFF8C00)),
  ('Orange', ui.Color(0xFFFFA500)),
  ('Gold', ui.Color(0xFFFFD700)),
  ('Yellow', ui.Color(0xFFFFFF00)),
  ('Khaki', ui.Color(0xFFF0E68C)),
  ('Olive', ui.Color(0xFF808000)),
  ('Olive Drab', ui.Color(0xFF6B8E23)),
  ('Yellow Green', ui.Color(0xFF9ACD32)),
  ('Lime Green', ui.Color(0xFF32CD32)),
  ('Lime', ui.Color(0xFF00FF00)),
  ('Chartreuse', ui.Color(0xFF7FFF00)),
  ('Spring Green', ui.Color(0xFF00FF7F)),
  ('Sea Green', ui.Color(0xFF2E8B57)),
  ('Forest Green', ui.Color(0xFF228B22)),
  ('Green', ui.Color(0xFF008000)),
  ('Dark Green', ui.Color(0xFF006400)),
  ('Teal', ui.Color(0xFF008080)),
  ('Turquoise', ui.Color(0xFF40E0D0)),
  ('Aquamarine', ui.Color(0xFF7FFFD4)),
  ('Cyan', ui.Color(0xFF00FFFF)),
  ('Dark Cyan', ui.Color(0xFF008B8B)),
  ('Cadet Blue', ui.Color(0xFF5F9EA0)),
  ('Steel Blue', ui.Color(0xFF4682B4)),
  ('Sky Blue', ui.Color(0xFF87CEEB)),
  ('Dodger Blue', ui.Color(0xFF1E90FF)),
  ('Cornflower', ui.Color(0xFF6495ED)),
  ('Royal Blue', ui.Color(0xFF4169E1)),
  ('Blue', ui.Color(0xFF0000FF)),
  ('Navy', ui.Color(0xFF000080)),
  ('Midnight Blue', ui.Color(0xFF191970)),
  ('Slate Blue', ui.Color(0xFF6A5ACD)),
  ('Indigo', ui.Color(0xFF4B0082)),
  ('Blue Violet', ui.Color(0xFF8A2BE2)),
  ('Dark Violet', ui.Color(0xFF9400D3)),
  ('Purple', ui.Color(0xFF800080)),
  ('Medium Purple', ui.Color(0xFF9370DB)),
  ('Orchid', ui.Color(0xFFDA70D6)),
  ('Violet', ui.Color(0xFFEE82EE)),
  ('Plum', ui.Color(0xFFDDA0DD)),
  ('Magenta', ui.Color(0xFFFF00FF)),
  ('Deep Pink', ui.Color(0xFFFF1493)),
  ('Hot Pink', ui.Color(0xFFFF69B4)),
  ('Pink', ui.Color(0xFFFFC0CB)),
  ('Maroon', ui.Color(0xFF800000)),
  ('Dark Red', ui.Color(0xFF8B0000)),
  ('Firebrick', ui.Color(0xFFB22222)),
  ('Brown', ui.Color(0xFFA52A2A)),
  ('Sienna', ui.Color(0xFFA0522D)),
  ('Chocolate', ui.Color(0xFFD2691E)),
  ('Peru', ui.Color(0xFFCD853F)),
  ('Goldenrod', ui.Color(0xFFDAA520)),
  ('Tan', ui.Color(0xFFD2B48C)),
  ('Light Coral', ui.Color(0xFFF08080)),
  ('Light Salmon', ui.Color(0xFFFFA07A)),
  ('Light Green', ui.Color(0xFF90EE90)),
  ('Pale Green', ui.Color(0xFF98FB98)),
  ('Light Blue', ui.Color(0xFFADD8E6)),
  ('Powder Blue', ui.Color(0xFFB0E0E6)),
  ('Lavender', ui.Color(0xFFE6E6FA)),
  ('Thistle', ui.Color(0xFFD8BFD8)),
  ('Moccasin', ui.Color(0xFFFFE4B5)),
  ('Peach Puff', ui.Color(0xFFFFDAB9)),
];

(double, double, double) _oklab(ui.Color color) {
  double linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final r = linear(color.r);
  final g = linear(color.g);
  final b = linear(color.b);
  final l = math.pow(
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    1 / 3,
  );
  final m = math.pow(
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    1 / 3,
  );
  final s = math.pow(
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
    1 / 3,
  );
  return (
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

String _nameOf(ui.Color color) {
  final (l, a, b) = _oklab(color);
  var best = _colorNames.first.$1;
  var bestDistance = double.infinity;
  for (final (name, candidate) in _colorNames) {
    final (l2, a2, b2) = _oklab(candidate);
    final d = (l - l2) * (l - l2) + (a - a2) * (a - a2) + (b - b2) * (b - b2);
    if (d < bestDistance) {
      bestDistance = d;
      best = name;
    }
  }
  return best;
}

/// OKLCH chroma is drawn larger than true scale so its shape reads next to the
/// HSL cylinder; proportions between hues are unchanged.
const double _oklchRadius = 0.52 * 1.45;

class _Camera {
  new({
    required this.yaw,
    required ui.Size size,
    required ui.Offset offset,
    this.radius = 0.52,
  }) : centre = offset + ui.Offset(size.width / 2, size.height / 2),
       scale = math.max(1.0, math.min(size.width / 1.35, size.height / 1.55));

  final double radius;
  static const double _pitch = 0.50;
  static final double _sinPitch = math.sin(_pitch);
  static final double _cosPitch = math.cos(_pitch);

  final double yaw;
  final ui.Offset centre;
  final double scale;

  static double _height(double lightnessPct) => lightnessPct / 100 - 0.5;

  /// The hue whose face points straight at the viewer.
  double get frontHue => (yaw * 180 / math.pi + 90) % 360;

  (double, double, double) project(
    double hue,
    double distance,
    double lightnessPct,
  ) {
    final angle = hue * math.pi / 180 - yaw;
    final across = distance * math.cos(angle);
    final towards = distance * math.sin(angle);
    final up = _height(lightnessPct);
    return (
      centre.dx + scale * across,
      centre.dy + scale * (towards * _sinPitch - up * _cosPitch),
      towards * _cosPitch + up * _sinPitch,
    );
  }
}

class _SolidMesh {
  new({required this.space, this.columns = 96})
    : reach = Float32List((rows + 1) * columns),
      colors = Int32List((rows + 1) * columns) {
    for (var row = 0; row <= rows; row++) {
      final lightness = lightnessOf(row);
      for (var column = 0; column < columns; column++) {
        final hue = hueOf(column);
        final at = row * columns + column;
        reach[at] = (lightness <= 0.01 || lightness >= 99.99)
            ? 0.0
            : chromaReach(space, hue: hue, lightnessPct: lightness);
        colors[at] = sampleAcrossSpace(
          space,
          hue: hue,
          saturationPct: 100.0,
          lightnessPct: lightness,
        ).toARGB32();
      }
    }
  }

  static const int rows = 64;

  final ColorSpaceMode space;
  final int columns;
  final Float32List reach;
  final Int32List colors;

  double hueOf(int column) => column * 360.0 / columns;
  static double lightnessOf(int row) => row * 100.0 / rows;
}

class _Slice {
  new({
    required ColorSpaceMode space,
    required this.lightness,
    this.columns = 96,
  }) : reach = Float32List(columns),
       colors = Int32List((rings + 1) * columns) {
    for (var column = 0; column < columns; column++) {
      final hue = column * 360.0 / columns;
      reach[column] = chromaReach(space, hue: hue, lightnessPct: lightness);
      for (var ring = 0; ring <= rings; ring++) {
        colors[ring * columns + column] = sampleAcrossSpace(
          space,
          hue: hue,
          saturationPct: ring * 100.0 / rings,
          lightnessPct: lightness,
        ).toARGB32();
      }
    }
  }

  static const int rings = 6;

  final int columns;
  final double lightness;
  final Float32List reach;
  final Int32List colors;
}

Uint16List _quadIndices(List<int> faces, int columns) {
  final indices = Uint16List(faces.length * 6);
  var cursor = 0;
  for (final face in faces) {
    final ring = face ~/ columns;
    final column = face % columns;
    final next = (column + 1) % columns;
    final a = ring * columns + column;
    final b = ring * columns + next;
    final c = (ring + 1) * columns + next;
    final d = (ring + 1) * columns + column;
    indices
      ..[cursor++] = a
      ..[cursor++] = b
      ..[cursor++] = c
      ..[cursor++] = a
      ..[cursor++] = c
      ..[cursor++] = d;
  }
  return indices;
}

void _paintSolid(
  ui.Canvas canvas,
  _Camera camera,
  _SolidMesh mesh,
  _Slice slice,
) {
  final columns = mesh.columns;
  const cageRingEvery = 8;
  const cageRibEvery = 12;
  final rowsBelow = (slice.lightness / (100 / _SolidMesh.rows)).ceil();

  if (rowsBelow > 0) {
    final ringCount = rowsBelow + 1;
    final positions = Float32List(ringCount * columns * 2);
    final colors = Int32List(ringCount * columns);
    final nearness = Float32List(ringCount * columns);
    final topColors = _Slice.rings * columns;

    for (var ring = 0; ring < ringCount; ring++) {
      final isCut = ring == rowsBelow;
      final lightness = isCut ? slice.lightness : _SolidMesh.lightnessOf(ring);
      for (var column = 0; column < columns; column++) {
        final at = ring * columns + column;
        final (x, y, near) = camera.project(
          mesh.hueOf(column),
          (isCut ? slice.reach[column] : mesh.reach[at]) * camera.radius,
          lightness,
        );
        positions[at * 2] = x;
        positions[at * 2 + 1] = y;
        nearness[at] = near;
        colors[at] = isCut ? slice.colors[topColors + column] : mesh.colors[at];
      }
    }

    final faces = List<int>.generate(rowsBelow * columns, (face) => face);
    final faceNearness = Float32List(faces.length);
    for (final face in faces) {
      final ring = face ~/ columns;
      final column = face % columns;
      final next = (column + 1) % columns;
      faceNearness[face] =
          nearness[ring * columns + column] +
          nearness[ring * columns + next] +
          nearness[(ring + 1) * columns + column] +
          nearness[(ring + 1) * columns + next];
    }
    faces.sort((a, b) => faceNearness[a].compareTo(faceNearness[b]));

    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: _quadIndices(faces, columns),
      ),
      ui.BlendMode.dst,
      ui.Paint(),
    );
  }

  const rings = _Slice.rings;
  final slicePos = Float32List((rings + 1) * columns * 2);
  final edge = ui.Path();
  for (var ring = 0; ring <= rings; ring++) {
    for (var column = 0; column < columns; column++) {
      final at = ring * columns + column;
      final (x, y, _) = camera.project(
        mesh.hueOf(column),
        slice.reach[column] * camera.radius * ring / rings,
        slice.lightness,
      );
      slicePos[at * 2] = x;
      slicePos[at * 2 + 1] = y;
      if (ring != rings) continue;
      if (column == 0) {
        edge.moveTo(x, y);
      } else {
        edge.lineTo(x, y);
      }
    }
  }
  edge.close();

  canvas.drawVertices(
    ui.Vertices.raw(
      ui.VertexMode.triangles,
      slicePos,
      colors: slice.colors,
      indices: _quadIndices(
        List<int>.generate(rings * columns, (face) => face),
        columns,
      ),
    ),
    ui.BlendMode.dst,
    ui.Paint(),
  );
  canvas.drawPath(
    edge,
    _stroke(const ui.Color(0xE6FFFFFF), 1.6)..strokeJoin = ui.StrokeJoin.round,
  );

  final cage = ui.Path();
  ui.Offset corner(int row, int column) {
    final (x, y, _) = camera.project(
      mesh.hueOf(column),
      mesh.reach[row * columns + column] * camera.radius,
      _SolidMesh.lightnessOf(row),
    );
    return ui.Offset(x, y);
  }

  for (var row = rowsBelow; row <= _SolidMesh.rows; row++) {
    final isTop = row == _SolidMesh.rows;
    if (row % cageRingEvery != 0 && !isTop) continue;
    if (_SolidMesh.lightnessOf(row) <= slice.lightness) continue;
    cage.addPolygon([
      for (var column = 0; column < columns; column++) corner(row, column),
    ], true);
  }
  for (var column = 0; column < columns; column += cageRibEvery) {
    final (x, y, _) = camera.project(
      mesh.hueOf(column),
      slice.reach[column] * camera.radius,
      slice.lightness,
    );
    cage.addPolygon([
      ui.Offset(x, y),
      for (var row = rowsBelow; row <= _SolidMesh.rows; row++)
        if (_SolidMesh.lightnessOf(row) > slice.lightness) corner(row, column),
    ], false);
  }
  canvas.drawPath(
    cage,
    _stroke(_ink.withValues(alpha: 0.13))..strokeJoin = ui.StrokeJoin.round,
  );
}

/// The studio's palette strip: [_chips] hues sampled around the cut.
void _paintPaletteStrip(
  ui.Canvas canvas,
  ui.Rect rect,
  List<ui.Color> colors,
  int selected,
) {
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(13)),
    ui.Paint()..color = _well,
  );
  const inset = 4.0;
  const gap = 3.0;
  final chipWidth =
      (rect.width - inset * 2 - gap * (colors.length - 1)) / colors.length;
  for (var i = 0; i < colors.length; i++) {
    final chip = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        rect.left + inset + i * (chipWidth + gap),
        rect.top + inset,
        chipWidth,
        rect.height - inset * 2,
      ),
      const ui.Radius.circular(9),
    );
    canvas.drawRRect(chip, ui.Paint()..color = colors[i]);
    if (i == selected) {
      canvas.drawRRect(chip.deflate(2.5), _stroke(_inkOn(colors[i]), 1.5));
    }
  }
}

void _paintPage(
  ui.Canvas canvas, {
  required ui.Rect page,
  required ColorSpaceMode space,
  required String note,
  required _SolidMesh mesh,
  required double yaw,
  required double lightness,
  double radius = 0.52,
}) {
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(page, const ui.Radius.circular(20)),
    ui.Paint()..color = _page,
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(page, const ui.Radius.circular(20)),
    _stroke(_hairline),
  );

  const inset = 22.0;
  final left = page.left + inset;
  final right = page.right - inset;
  _text(canvas, [(space.label, _serif(36))], x: left, baseline: page.top + 50);
  _text(canvas, [(note, _mono(10))], x: left, baseline: page.top + 72);
  _text(
    canvas,
    [
      ('lightness ', _mono(10)),
      ('${lightness.round()}', _mono(10, color: _ink, weight: 700)),
    ],
    x: right,
    baseline: page.top + 46,
    anchor: _Anchor.end,
  );

  final camera = _Camera(
    yaw: yaw,
    size: ui.Size(page.width - 40, 236),
    offset: ui.Offset(page.left + 20, page.top + 86),
    radius: radius,
  );
  _paintSolid(canvas, camera, mesh, _Slice(space: space, lightness: lightness));

  final chips = [
    for (var i = 0; i < _chips; i++)
      sampleAcrossSpace(
        space,
        hue: i * 360.0 / _chips,
        saturationPct: 100,
        lightnessPct: lightness,
      ),
  ];
  final selected = (camera.frontHue / (360 / _chips)).round() % _chips;
  final front = chips[selected];
  final specimen = ui.Rect.fromLTRB(
    left,
    page.top + 338,
    right,
    page.top + 398,
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(specimen, const ui.Radius.circular(14)),
    ui.Paint()..color = front,
  );
  final onFront = _inkOn(front);
  _text(
    canvas,
    [(_nameOf(front), _serif(27, color: onFront))],
    x: specimen.left + 14,
    baseline: specimen.bottom - 17,
    maxWidth: specimen.width - 110,
  );
  _text(
    canvas,
    [(_hex(front), _mono(10, color: onFront.withValues(alpha: 0.8)))],
    x: specimen.right - 14,
    baseline: specimen.bottom - 18,
    anchor: _Anchor.end,
  );

  _paintPaletteStrip(
    canvas,
    ui.Rect.fromLTRB(left, page.top + 408, right, page.top + 446),
    chips,
    selected,
  );
}

Future<void> _savePng(ui.PictureRecorder recorder, String path) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (_width * _dpr).round(),
    (_height * _dpr).round(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(byteData!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
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
  test('render chroma-folio README solid comparison frames', () async {
    await _loadFonts();

    final oklchMesh = _SolidMesh(space: ColorSpaceMode.oklch);
    final hslMesh = _SolidMesh(space: ColorSpaceMode.hsl);

    const gap = 14.0;
    const pageWidth = (_width - gap * 3) / 2;
    const leftPage = ui.Rect.fromLTWH(gap, gap, pageWidth, _height - gap * 2);
    const rightPage = ui.Rect.fromLTWH(
      gap * 2 + pageWidth,
      gap,
      pageWidth,
      _height - gap * 2,
    );

    for (var frame = 0; frame < _frames; frame++) {
      final t = frame / _frames;
      final yaw = 0.65 + 2 * math.pi * t;
      final lightness = 68 + 20 * math.cos(2 * math.pi * t);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(_dpr, _dpr);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(0, 0, _width, _height),
          const ui.Radius.circular(28),
        ),
        ui.Paint()..color = _paper,
      );

      _paintPage(
        canvas,
        page: leftPage,
        space: ColorSpaceMode.oklch,
        note: 'follows the real sRGB edge',
        mesh: oklchMesh,
        yaw: yaw,
        lightness: lightness,
        radius: _oklchRadius,
      );
      _paintPage(
        canvas,
        page: rightPage,
        space: ColorSpaceMode.hsl,
        note: 'a cylinder, so brightness drifts',
        mesh: hslMesh,
        yaw: yaw,
        lightness: lightness,
      );

      final name = frame.toString().padLeft(4, '0');
      await _savePng(
        recorder,
        'build/readme_frames/oklch_vs_hsl_solid/frame_$name.png',
      );
    }
  }, timeout: Timeout.none);
}
