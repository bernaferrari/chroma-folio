import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

enum PosterStyle {
  /// The lead colour sets behind horizon bands of the others.
  sun,

  /// Nested arches, the lead colour outermost.
  arches,

  /// A Bauhaus grid: the lead as a big quarter disc, the rest as tiles.
  grid,

  /// Overlapping discs that mix like riso ink (or glow, on a dark ground).
  overprint,
}

/// A small abstract poster that shows a palette the way it is meant to be
/// used: lots of [background], the other colours as shapes on top of it.
class const PalettePoster({
  super.key,
  required final List<Color> colors,
  required final int background,
  required final PosterStyle style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PosterPainter(colors, background, style),
      child: const SizedBox.expand(),
    );
  }
}

class _PosterPainter(
  final List<Color> colors,
  final int background,
  final PosterStyle style,
) extends CustomPainter {
  Color get _ground => colors[background];

  /// Every colour but the ground, the lead first.
  List<Color> get _accents => [
    for (final (i, color) in colors.indexed)
      if (i != background) color,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(bounds)
      ..drawRect(bounds, Paint()..color = _ground);
    final accents = _accents;
    if (accents.isNotEmpty) {
      switch (style) {
        case PosterStyle.sun:
          _paintSun(canvas, size, accents);
        case PosterStyle.arches:
          _paintArches(canvas, size, accents);
        case PosterStyle.grid:
          _paintGrid(canvas, size, accents);
        case PosterStyle.overprint:
          _paintOverprint(canvas, size, accents);
      }
    }
    canvas.restore();
  }

  void _paintSun(Canvas canvas, Size size, List<Color> accents) {
    final bands = accents.skip(1).toList();
    final horizon = bands.isEmpty ? size.height * 0.72 : size.height * 0.6;
    canvas.drawCircle(
      Offset(size.width * 0.62, horizon),
      size.height * 0.4,
      Paint()..color = accents.first,
    );
    if (bands.isEmpty) return;
    final bandHeight = (size.height - horizon) / bands.length;
    for (final (i, color) in bands.indexed) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          horizon + i * bandHeight,
          size.width,
          bandHeight + 0.5,
        ),
        Paint()..color = color,
      );
    }
  }

  void _paintArches(Canvas canvas, Size size, List<Color> accents) {
    final centre = Offset(size.width * 0.36, size.height);
    final outer = math.min(size.height * 0.94, size.width * 0.62);
    final step = outer / (accents.length + 0.7);
    for (final (i, color) in accents.indexed) {
      canvas.drawCircle(centre, outer - i * step, Paint()..color = color);
    }
    canvas.drawCircle(
      centre,
      outer - accents.length * step,
      Paint()..color = _ground,
    );
  }

  void _paintGrid(Canvas canvas, Size size, List<Color> accents) {
    // A square block for the lead, then two rows of square tiles.
    final block = math.min(size.height, size.width * 0.66);
    canvas.drawPath(
      _quarterDisc(Offset(0, size.height), block, 3),
      Paint()..color = accents.first,
    );

    final rest = accents.skip(1).toList();
    final tile = size.height / 2;
    final columns = math.max(1, ((size.width - block) / tile).floor());
    final tileWidth = (size.width - block) / columns;
    final cells = math.min(rest.length, columns * 2);
    for (var i = 0; i < cells; i++) {
      final cell = Rect.fromLTWH(
        block + (i ~/ 2) * tileWidth,
        (i % 2) * tile,
        tileWidth,
        tile,
      );
      final side = math.min(cell.width, cell.height);
      final paint = Paint()..color = rest[i];
      switch (i % 3) {
        case 0:
          canvas
            ..drawRect(cell, paint)
            ..drawCircle(cell.center, side * 0.28, Paint()..color = _ground);
        case 1:
          canvas.drawPath(_quarterDisc(cell.topLeft, side, 0), paint);
        case _:
          canvas.drawCircle(cell.center, side * 0.4, paint);
      }
    }
    // Anything left over becomes dots in the open corner of the lead block.
    for (final (i, color) in rest.skip(cells).indexed) {
      canvas.drawCircle(
        Offset(block * (0.8 - i * 0.2), size.height * 0.2),
        size.height * 0.08,
        Paint()..color = color,
      );
    }
  }

  /// A quarter disc around [corner]; [turn] picks the quadrant, starting with
  /// the one below and to the right and going clockwise.
  static Path _quarterDisc(Offset corner, double radius, int turn) {
    final start = turn * math.pi / 2;
    return Path()
      ..moveTo(corner.dx, corner.dy)
      ..arcTo(
        Rect.fromCircle(center: corner, radius: radius),
        start,
        math.pi / 2,
        false,
      )
      ..close();
  }

  void _paintOverprint(Canvas canvas, Size size, List<Color> accents) {
    final onDark = _ground.computeLuminance() < 0.2;
    final blend = onDark ? BlendMode.screen : BlendMode.multiply;
    // Only a few inks overlap: dark ones and extras would print to mud, so
    // they sit on top as small dots instead.
    bool inks(Color color) => onDark
        ? color.computeLuminance() > 0.04
        : color.computeLuminance() > 0.1;
    final discs = accents.where(inks).take(4).toList();
    final dots = [
      for (final color in accents)
        if (!discs.contains(color)) color,
    ];

    final radius = size.height * 0.3;
    final lead = radius * 1.25;
    final spread = size.width - lead - radius - size.width * 0.08;
    final bounds = Offset.zero & size;
    canvas
      ..saveLayer(bounds, Paint())
      ..drawRect(bounds, Paint()..color = _ground);
    for (final (i, color) in discs.indexed) {
      final share = discs.length == 1 ? 0.5 : i / (discs.length - 1);
      canvas.drawCircle(
        Offset(lead + spread * share, size.height * (i.isEven ? 0.44 : 0.58)),
        i == 0 ? lead : radius,
        Paint()
          ..color = color
          ..blendMode = i == 0 ? BlendMode.srcOver : blend,
      );
    }
    canvas.restore();

    final dot = size.height * 0.065;
    for (final (i, color) in dots.indexed) {
      canvas.drawCircle(
        Offset(size.width - dot * 2 - i * dot * 2.8, size.height - dot * 2),
        dot,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_PosterPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.background != background ||
      !_sameColors(oldDelegate.colors, colors);

  static bool _sameColors(List<Color> a, List<Color> b) =>
      a.length == b.length &&
      a.indexed.every((entry) => entry.$2 == b[entry.$1]);
}
