import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/studio_cubit.dart';
import '../models/color_spaces.dart';
import '../widgets/channel_reel.dart';
import '../widgets/studio_theme.dart';

/// The active colour space as a solid: every colour it can make, with hue
/// around the axis, lightness up it and saturation outwards.
///
/// The solid is cut open at the picked lightness. Drag sideways to turn it,
/// drag on the cut face to pick a hue and saturation, and move the cut with
/// the lightness reel beside it or by dragging up or down off the cut face.
class GamutSolidScreen extends StatefulWidget {
  const GamutSolidScreen({super.key});

  @override
  State<GamutSolidScreen> createState() => _GamutSolidScreenState();
}

enum _Grab { undecided, turn, lift, pick }

class _GamutSolidScreenState extends State<GamutSolidScreen>
    with SingleTickerProviderStateMixin {
  static const double _decideAfter = 6;
  static const double _spinFriction = 0.03;
  static const double _pickSlack = 1.08;
  static const double _levelReelWidth = 60;

  late final AnimationController _spin;
  _Grab _grab = _Grab.undecided;
  Offset _travel = Offset.zero;
  Size _size = Size.zero;
  _Slice? _slice;

  StudioCubit get _cubit => context.read<StudioCubit>();

  @override
  void initState() {
    super.initState();
    final state = _cubit.state;
    final hue = state.activeColor.channelsFor(state.activeSpace)[0].value;
    _spin = AnimationController.unbounded(
      vsync: this,
      value: _Camera.yawFacing(hue),
    );
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  _Camera get _camera => _Camera(yaw: _spin.value, size: _size);

  /// The colour on the cut face under [position], if there is one.
  StudioColor? _colorOnSlice(Offset position) {
    final state = _cubit.state;
    final space = state.activeSpace;
    final lightness = state.activeColor.channelsFor(space)[2].value;
    final (hue, distance) = _camera.onLevel(position, lightness);
    final reach = chromaReach(space, hue: hue, lightnessPct: lightness);
    if (reach <= 1e-4) return null;
    final share = distance / (reach * _Camera.radius);
    if (share > _pickSlack) return null;
    return StudioColor.fromSpace(
      space,
      hue: hue,
      saturationPct: share * 100,
      lightnessPct: lightness,
    );
  }

  void _pickAt(Offset position) {
    final color = _colorOnSlice(position);
    if (color != null) _cubit.setActiveColor(color, recordHistory: false);
  }

  void _handlePanStart(DragStartDetails details) {
    _spin.stop();
    _travel = Offset.zero;
    if (_colorOnSlice(details.localPosition) == null) {
      _grab = _Grab.undecided;
      return;
    }
    _grab = _Grab.pick;
    _cubit.beginScrub();
    _pickAt(details.localPosition);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    switch (_grab) {
      case _Grab.undecided:
        _travel += details.delta;
        if (_travel.distance < _decideAfter) return;
        if (_travel.dx.abs() >= _travel.dy.abs()) {
          _grab = _Grab.turn;
        } else {
          _grab = _Grab.lift;
          _cubit.beginScrub();
        }
      case _Grab.turn:
        _spin.value += _camera.turnFor(details.delta.dx);
      case _Grab.lift:
        final state = _cubit.state;
        final lightness = state.activeColor
            .channelsFor(state.activeSpace)[2]
            .value;
        _cubit.scrubChannel(
          2,
          (lightness + _camera.liftFor(details.delta.dy)).clamp(0.0, 100.0),
        );
      case _Grab.pick:
        _pickAt(details.localPosition);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    switch (_grab) {
      case _Grab.undecided:
        break;
      case _Grab.turn:
        _spin.animateWith(
          FrictionSimulation(
            _spinFriction,
            _spin.value,
            _camera.turnFor(details.velocity.pixelsPerSecond.dx),
          ),
        );
      case _Grab.lift:
      case _Grab.pick:
        _cubit.endScrub();
    }
    _grab = _Grab.undecided;
  }

  void _handleTapUp(TapUpDetails details) {
    final color = _colorOnSlice(details.localPosition);
    if (color != null) _cubit.setActiveColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<StudioCubit, StudioState>(
      buildWhen: (prev, next) =>
          prev.activeColor != next.activeColor ||
          prev.activeSpace != next.activeSpace,
      builder: (context, state) {
        final space = state.activeSpace;
        final channels = state.activeColor.channelsFor(space);
        final hue = channels[0].value;
        final saturation = channels[1];
        final lightness = channels[2].value;
        final cached = _slice;
        final slice = cached != null && cached.matches(space, lightness)
            ? cached
            : _slice = _Slice(space, lightness);

        final solid = LayoutBuilder(
          builder: (context, constraints) {
            _size = constraints.biggest;
            return MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: GestureDetector(
                key: const ValueKey<String>('gamut_solid_canvas'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: _handlePanStart,
                onPanUpdate: _handlePanUpdate,
                onPanEnd: _handlePanEnd,
                onPanCancel: () => _grab = _Grab.undecided,
                onTapUp: _handleTapUp,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _SolidPainter(
                    spin: _spin,
                    mesh: _SolidMesh.of(space),
                    slice: slice,
                    markerHue: hue,
                    markerReach:
                        chromaReach(space, hue: hue, lightnessPct: lightness) *
                        channels[1].value /
                        100,
                    markerColor: state.activeColor.color,
                    cageColor: scheme.onSurface,
                  ),
                ),
              ),
            );
          },
        );

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
                    space.label,
                    style: studioDisplayStyle(
                      context,
                      fontSize: 24,
                      height: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${channels[2].name.toLowerCase()} ${lightness.round()}',
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: solid),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: _levelReelWidth,
                    child: ChannelReel(
                      descriptor: channels[2],
                      space: space,
                      activeColor: state.activeColor,
                      showReadout: false,
                      onScrubStart: _cubit.beginScrub,
                      onScrubUpdate: (value) => _cubit.scrubChannel(2, value),
                      onScrubEnd: _cubit.endScrub,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, _levelReelWidth + 12, 0),
              child: Row(
                children: [
                  Text(saturation.name),
                  Expanded(
                    child: Slider(
                      value: saturation.value.clamp(
                        saturation.min,
                        saturation.max,
                      ),
                      min: saturation.min,
                      max: saturation.max,
                      semanticFormatterCallback: (value) =>
                          '${saturation.name} ${value.round()}${saturation.unit}',
                      onChangeStart: (_) => _cubit.beginScrub(),
                      onChanged: (value) => _cubit.scrubChannel(1, value),
                      onChangeEnd: (_) => _cubit.endScrub(),
                    ),
                  ),
                  Text(
                    saturation.formattedValue,
                    style: studioMonoStyle(context, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Looks at the solid from slightly above, turned by [yaw] around its axis.
class _Camera {
  _Camera({required this.yaw, required Size size})
    : centre = size.center(Offset.zero),
      scale = math.max(1, math.min(size.width / 1.3, size.height / 1.65));

  /// Distance from the axis to the widest point of a solid.
  static const double radius = 0.55;
  static const double _pitch = 0.5;
  static final double _sinPitch = math.sin(_pitch);
  static final double _cosPitch = math.cos(_pitch);

  final double yaw;
  final Offset centre;
  final double scale;

  /// The yaw that brings [hue] to the front.
  static double yawFacing(double hue) => hue * math.pi / 180 - math.pi / 2;

  static double _height(double lightnessPct) => lightnessPct / 100 - 0.5;

  /// Screen position and nearness of the point at [hue], [distance] from
  /// the axis, at [lightnessPct].
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

  /// Hue and distance from the axis of the point seen at [position] on the
  /// level of [lightnessPct].
  (double, double) onLevel(Offset position, double lightnessPct) {
    final across = (position.dx - centre.dx) / scale;
    final towards =
        ((position.dy - centre.dy) / scale +
            _height(lightnessPct) * _cosPitch) /
        _sinPitch;
    final hue = (math.atan2(towards, across) + yaw) * 180 / math.pi;
    return (
      (hue % 360 + 360) % 360,
      math.sqrt(across * across + towards * towards),
    );
  }

  /// Yaw change that makes the front of the solid follow [pixels] sideways.
  double turnFor(double pixels) => pixels / (scale * radius);

  /// Lightness change that makes the cut follow [pixels] downwards.
  double liftFor(double pixels) => -pixels / (scale * _cosPitch) * 100;
}

/// The outside of a solid: how far each hue reaches at each lightness, and
/// the most saturated colour found there.
class _SolidMesh {
  _SolidMesh._(ColorSpaceMode space)
    : reach = Float32List((rows + 1) * columns),
      colors = Int32List((rows + 1) * columns) {
    for (var row = 0; row <= rows; row++) {
      for (var column = 0; column < columns; column++) {
        final hue = hueOf(column);
        final lightness = lightnessOf(row);
        final at = row * columns + column;
        reach[at] = chromaReach(space, hue: hue, lightnessPct: lightness);
        colors[at] = sampleAcrossSpace(
          space,
          hue: hue,
          saturationPct: 100,
          lightnessPct: lightness,
        ).toARGB32();
      }
    }
  }

  factory _SolidMesh.of(ColorSpaceMode space) =>
      _cache.putIfAbsent(space, () => _SolidMesh._(space));

  static const int columns = 72;
  static const int rows = 40;
  static final Map<ColorSpaceMode, _SolidMesh> _cache = {};

  final Float32List reach;
  final Int32List colors;

  static double hueOf(int column) => column * 360 / columns;
  static double lightnessOf(int row) => row * 100 / rows;
}

/// The cut face of a solid at one lightness, as rings from the grey axis out
/// to the edge.
class _Slice {
  _Slice(this.space, this.lightness)
    : reach = Float32List(_SolidMesh.columns),
      colors = Int32List((rings + 1) * _SolidMesh.columns) {
    for (var column = 0; column < _SolidMesh.columns; column++) {
      final hue = _SolidMesh.hueOf(column);
      reach[column] = chromaReach(space, hue: hue, lightnessPct: lightness);
      for (var ring = 0; ring <= rings; ring++) {
        colors[ring * _SolidMesh.columns + column] = sampleAcrossSpace(
          space,
          hue: hue,
          saturationPct: ring * 100 / rings,
          lightnessPct: lightness,
        ).toARGB32();
      }
    }
  }

  static const int rings = 6;

  final ColorSpaceMode space;
  final double lightness;
  final Float32List reach;
  final Int32List colors;

  bool matches(ColorSpaceMode space, double lightness) =>
      this.space == space && this.lightness == lightness;
}

class _SolidPainter extends CustomPainter {
  _SolidPainter({
    required this.spin,
    required this.mesh,
    required this.slice,
    required this.markerHue,
    required this.markerReach,
    required this.markerColor,
    required this.cageColor,
  }) : super(repaint: spin);

  static const int _columns = _SolidMesh.columns;
  static const int _cageRingEvery = 5;
  static const int _cageRibEvery = 6;
  static const double _markerRadius = 13;

  final Animation<double> spin;
  final _SolidMesh mesh;
  final _Slice slice;
  final double markerHue;
  final double markerReach;
  final Color markerColor;
  final Color cageColor;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = _Camera(yaw: spin.value, size: size);
    // Rows of the mesh that sit below the cut.
    final rowsBelow = (slice.lightness / (100 / _SolidMesh.rows)).ceil();

    _paintBelow(canvas, camera, rowsBelow);
    _paintSlice(canvas, camera);
    _paintCage(canvas, camera, rowsBelow);
    _paintMarker(canvas, camera);
  }

  /// The solid from black up to the cut, far faces first.
  void _paintBelow(Canvas canvas, _Camera camera, int rowsBelow) {
    if (rowsBelow == 0) return;
    final ringCount = rowsBelow + 1;
    final positions = Float32List(ringCount * _columns * 2);
    final colors = Int32List(ringCount * _columns);
    final nearness = Float32List(ringCount * _columns);
    const topColors = _Slice.rings * _columns;

    for (var ring = 0; ring < ringCount; ring++) {
      final isCut = ring == rowsBelow;
      final lightness = isCut ? slice.lightness : _SolidMesh.lightnessOf(ring);
      for (var column = 0; column < _columns; column++) {
        final at = ring * _columns + column;
        final (x, y, near) = camera.project(
          _SolidMesh.hueOf(column),
          (isCut ? slice.reach[column] : mesh.reach[at]) * _Camera.radius,
          lightness,
        );
        positions[at * 2] = x;
        positions[at * 2 + 1] = y;
        nearness[at] = near;
        colors[at] = isCut ? slice.colors[topColors + column] : mesh.colors[at];
      }
    }

    final faces = List<int>.generate(rowsBelow * _columns, (face) => face);
    double nearnessOf(int face) {
      final ring = face ~/ _columns;
      final column = face % _columns;
      final next = (column + 1) % _columns;
      return nearness[ring * _columns + column] +
          nearness[ring * _columns + next] +
          nearness[(ring + 1) * _columns + column] +
          nearness[(ring + 1) * _columns + next];
    }

    final faceNearness = Float32List(faces.length);
    for (final face in faces) {
      faceNearness[face] = nearnessOf(face);
    }
    faces.sort((a, b) => faceNearness[a].compareTo(faceNearness[b]));

    final indices = Uint16List(faces.length * 6);
    var cursor = 0;
    for (final face in faces) {
      final ring = face ~/ _columns;
      final column = face % _columns;
      final next = (column + 1) % _columns;
      final a = ring * _columns + column;
      final b = ring * _columns + next;
      final c = (ring + 1) * _columns + next;
      final d = (ring + 1) * _columns + column;
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
      BlendMode.dst,
      Paint(),
    );
  }

  /// The cut face, grey at the axis and most saturated at the edge.
  void _paintSlice(Canvas canvas, _Camera camera) {
    const rings = _Slice.rings;
    final positions = Float32List((rings + 1) * _columns * 2);
    final edge = Path();

    for (var ring = 0; ring <= rings; ring++) {
      for (var column = 0; column < _columns; column++) {
        final at = ring * _columns + column;
        final (x, y, _) = camera.project(
          _SolidMesh.hueOf(column),
          slice.reach[column] * _Camera.radius * ring / rings,
          slice.lightness,
        );
        positions[at * 2] = x;
        positions[at * 2 + 1] = y;
        if (ring != rings) continue;
        if (column == 0) {
          edge.moveTo(x, y);
        } else {
          edge.lineTo(x, y);
        }
      }
    }
    edge.close();

    final indices = Uint16List(rings * _columns * 6);
    var cursor = 0;
    for (var ring = 0; ring < rings; ring++) {
      for (var column = 0; column < _columns; column++) {
        final next = (column + 1) % _columns;
        final a = ring * _columns + column;
        final b = ring * _columns + next;
        final c = (ring + 1) * _columns + next;
        final d = (ring + 1) * _columns + column;
        indices
          ..[cursor++] = a
          ..[cursor++] = b
          ..[cursor++] = c
          ..[cursor++] = a
          ..[cursor++] = c
          ..[cursor++] = d;
      }
    }

    canvas.drawVertices(
      ui.Vertices.raw(
        ui.VertexMode.triangles,
        positions,
        colors: slice.colors,
        indices: indices,
      ),
      BlendMode.dst,
      Paint(),
    );
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  /// The part of the solid above the cut, as an open cage.
  void _paintCage(Canvas canvas, _Camera camera, int rowsBelow) {
    final cage = Path();
    Offset corner(int row, int column) {
      final (x, y, _) = camera.project(
        _SolidMesh.hueOf(column),
        mesh.reach[row * _columns + column] * _Camera.radius,
        _SolidMesh.lightnessOf(row),
      );
      return Offset(x, y);
    }

    for (var row = rowsBelow; row <= _SolidMesh.rows; row++) {
      final isTop = row == _SolidMesh.rows;
      if (row % _cageRingEvery != 0 && !isTop) continue;
      if (_SolidMesh.lightnessOf(row) <= slice.lightness) continue;
      cage.addPolygon([
        for (var column = 0; column < _columns; column++) corner(row, column),
      ], true);
    }
    for (var column = 0; column < _columns; column += _cageRibEvery) {
      final (x, y, _) = camera.project(
        _SolidMesh.hueOf(column),
        slice.reach[column] * _Camera.radius,
        slice.lightness,
      );
      cage.addPolygon([
        Offset(x, y),
        for (var row = rowsBelow; row <= _SolidMesh.rows; row++)
          if (_SolidMesh.lightnessOf(row) > slice.lightness)
            corner(row, column),
      ], false);
    }

    canvas.drawPath(
      cage,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round
        ..color = cageColor.withValues(alpha: 0.14),
    );
  }

  /// The picked colour, sitting on the cut face.
  void _paintMarker(Canvas canvas, _Camera camera) {
    final (x, y, _) = camera.project(
      markerHue,
      markerReach * _Camera.radius,
      slice.lightness,
    );
    final centre = Offset(x, y);
    canvas.drawCircle(
      centre + const Offset(0, 4),
      _markerRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(centre, _markerRadius, Paint()..color = Colors.white);
    canvas.drawCircle(centre, _markerRadius - 3, Paint()..color = markerColor);
  }

  @override
  bool shouldRepaint(covariant _SolidPainter oldDelegate) {
    return oldDelegate.slice != slice ||
        oldDelegate.mesh != mesh ||
        oldDelegate.markerHue != markerHue ||
        oldDelegate.markerReach != markerReach ||
        oldDelegate.markerColor != markerColor ||
        oldDelegate.cageColor != cageColor;
  }
}
