// Generates the README comparison animation for `chroma-folio`:
//   - build/readme_frames/oklch_vs_hsl_solid/*.png -> docs/screenshots/oklch_vs_hsl_solid.webp
//
// Run via `./tool/generate_assets.sh` (requires `flutter`, `ffmpeg`, and `img2webp`).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chroma_folio/models/color_spaces.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const ui.Color _paper = ui.Color(0xFFF6F4EE);
const ui.Color _cardBg = ui.Color(0xFFFCFAF5);
const ui.Color _borderCol = ui.Color(0xFFE0DDD4);
const ui.Color _ink = ui.Color(0xFF191918);
const ui.Color _inkMuted = ui.Color(0xFF6B6A66);

class _Camera {
  new({required this.yaw, required ui.Size size, required ui.Offset offset})
    : centre = offset + ui.Offset(size.width / 2, size.height / 2),
      scale = math.max(1.0, math.min(size.width / 1.35, size.height / 1.55));

  final double radius = 0.52;
  static const double _pitch = 0.50;
  static final double _sinPitch = math.sin(_pitch);
  static final double _cosPitch = math.cos(_pitch);

  final double yaw;
  final ui.Offset centre;
  final double scale;

  static double _height(double lightnessPct) => lightnessPct / 100 - 0.5;

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

void _paintSolid(
  ui.Canvas canvas,
  _Camera camera,
  _SolidMesh mesh,
  _Slice slice, {
  bool drawCageRibs = false,
}) {
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

    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
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

  final sliceIdx = Uint16List(rings * columns * 6);
  var sliceCursor = 0;
  for (var ring = 0; ring < rings; ring++) {
    for (var column = 0; column < columns; column++) {
      final next = (column + 1) % columns;
      final a = ring * columns + column;
      final b = ring * columns + next;
      final c = (ring + 1) * columns + next;
      final d = (ring + 1) * columns + column;
      sliceIdx
        ..[sliceCursor++] = a
        ..[sliceCursor++] = b
        ..[sliceCursor++] = c
        ..[sliceCursor++] = a
        ..[sliceCursor++] = c
        ..[sliceCursor++] = d;
    }
  }

  canvas.drawVertices(
    ui.Vertices.raw(
      ui.VertexMode.triangles,
      slicePos,
      colors: slice.colors,
      indices: sliceIdx,
    ),
    ui.BlendMode.dst,
    ui.Paint(),
  );
  canvas.drawPath(
    edge,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = ui.StrokeJoin.round
      ..color = const ui.Color(0xCCFFFFFF),
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
  if (drawCageRibs) {
    for (var column = 0; column < columns; column += cageRibEvery) {
      final (x, y, _) = camera.project(
        mesh.hueOf(column),
        slice.reach[column] * camera.radius,
        slice.lightness,
      );
      cage.addPolygon([
        ui.Offset(x, y),
        for (var row = rowsBelow; row <= _SolidMesh.rows; row++)
          if (_SolidMesh.lightnessOf(row) > slice.lightness)
            corner(row, column),
      ], false);
    }
  }
  canvas.drawPath(
    cage,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = ui.StrokeJoin.round
      ..color = _ink.withValues(alpha: 0.14),
  );
}

void _drawText(
  ui.Canvas canvas,
  String text,
  ui.Offset offset, {
  required ui.TextStyle style,
  ui.TextAlign align = ui.TextAlign.left,
  double maxWidth = 420,
}) {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: align, maxLines: 1, ellipsis: '…'),
        )
        ..pushStyle(style)
        ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth));
  final dx = switch (align) {
    ui.TextAlign.center => offset.dx - maxWidth / 2,
    ui.TextAlign.right => offset.dx - maxWidth,
    _ => offset.dx,
  };
  canvas.drawParagraph(paragraph, ui.Offset(dx, offset.dy));
}

void _drawLightnessPill(
  ui.Canvas canvas,
  double width,
  double height,
  double lightness,
) {
  final pillRect = ui.RRect.fromRectAndRadius(
    ui.Rect.fromLTWH(width / 2 - 74, height - 39, 148, 28),
    const ui.Radius.circular(14),
  );
  canvas.drawRRect(pillRect, ui.Paint()..color = _cardBg);
  canvas.drawRRect(
    pillRect,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = _borderCol,
  );
  final value = '${lightness.round()}%';
  final builder =
      ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
        ..pushStyle(
          ui.TextStyle(
            fontFamily: 'StudioSans',
            fontSize: 12.5,
            fontWeight: ui.FontWeight.w500,
            color: _inkMuted,
          ),
        )
        ..addText('lightness: ')
        ..pop()
        ..pushStyle(
          ui.TextStyle(
            fontFamily: 'StudioMono',
            fontSize: 12.5,
            fontWeight: ui.FontWeight.w700,
            color: _ink,
          ),
        )
        ..addText(value);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 200));
  canvas.drawParagraph(paragraph, ui.Offset(width / 2 - 100, height - 32.5));
}

Future<void> _savePng(
  ui.PictureRecorder recorder,
  double width,
  double height,
  double dpr,
  String path,
) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * dpr).round(),
    (height * dpr).round(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(byteData!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

Future<void> _loadFonts() async {
  Future<void> tryLoad(String family, String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await tryLoad('StudioSans', '/System/Library/Fonts/SFNS.ttf');
  await tryLoad('StudioMono', '/System/Library/Fonts/SFNSMono.ttf');
}

void main() {
  test('render chroma-folio README solid comparison frames', () async {
    await _loadFonts();

    final outDir = Directory('build/readme_frames/oklch_vs_hsl_solid')
      ..createSync(recursive: true);

    final oklchMesh = _SolidMesh(space: ColorSpaceMode.oklch);
    final hslMesh = _SolidMesh(space: ColorSpaceMode.hsl);

    const width = 760.0;
    const height = 430.0;
    const dpr = 2.0;
    const frames = 150;

    for (var frame = 0; frame < frames; frame++) {
      final t = frame / frames;
      final yaw = 0.65 + 2 * math.pi * t;
      final lightness = 62.5 + 22.5 * math.cos(2 * math.pi * t);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(dpr, dpr);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, width, height),
        ui.Paint()..color = _paper,
      );

      const panelGap = 16.0;
      const outerPad = 18.0;
      const panelWidth = (width - outerPad * 2 - panelGap) / 2;
      const panelHeight = height - outerPad - 52;
      const panelRadius = ui.Radius.circular(18);

      for (final left in [outerPad, outerPad + panelWidth + panelGap]) {
        final rr = ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(left, outerPad, panelWidth, panelHeight),
          panelRadius,
        );
        canvas.drawRRect(rr, ui.Paint()..color = _cardBg);
        canvas.drawRRect(
          rr,
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = _borderCol,
        );
      }

      const solidSize = ui.Size(panelWidth - 20, panelHeight - 66);
      _paintSolid(
        canvas,
        _Camera(
          yaw: yaw,
          size: solidSize,
          offset: const ui.Offset(outerPad + 10, outerPad + 56),
        ),
        oklchMesh,
        _Slice(space: ColorSpaceMode.oklch, lightness: lightness),
        drawCageRibs: true,
      );
      _paintSolid(
        canvas,
        _Camera(
          yaw: yaw,
          size: solidSize,
          offset: const ui.Offset(
            outerPad + panelWidth + panelGap + 10,
            outerPad + 56,
          ),
        ),
        hslMesh,
        _Slice(space: ColorSpaceMode.hsl, lightness: lightness),
        drawCageRibs: true,
      );

      for (final (left, title, subtitle) in [
        (outerPad, 'OKLCH', 'True sRGB gamut · even lightness'),
        (
          outerPad + panelWidth + panelGap,
          'HSL',
          'Forced cylinder · uneven brightness',
        ),
      ]) {
        _drawText(
          canvas,
          title,
          ui.Offset(left + panelWidth / 2, outerPad + 14),
          align: ui.TextAlign.center,
          style: ui.TextStyle(
            fontFamily: 'StudioSans',
            fontSize: 18,
            fontWeight: ui.FontWeight.w700,
            color: _ink,
            letterSpacing: -0.3,
          ),
        );
        _drawText(
          canvas,
          subtitle,
          ui.Offset(left + panelWidth / 2, outerPad + 38),
          align: ui.TextAlign.center,
          style: ui.TextStyle(
            fontFamily: 'StudioSans',
            fontSize: 12,
            fontWeight: ui.FontWeight.w500,
            color: _inkMuted,
          ),
        );
      }

      _drawLightnessPill(canvas, width, height, lightness);
      final name = frame.toString().padLeft(4, '0');
      await _savePng(
        recorder,
        width,
        height,
        dpr,
        '${outDir.path}/frame_$name.png',
      );
    }
  });
}
