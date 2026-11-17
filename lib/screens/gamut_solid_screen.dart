import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
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
class const GamutSolidScreen({super.key}) extends StatefulWidget {
  @override
  State<GamutSolidScreen> createState() => _GamutSolidScreenState();
}

enum _Grab { undecided, turn, lift, pick }

class _GamutSolidScreenState extends State<GamutSolidScreen>
    with TickerProviderStateMixin {
  static const double _decideAfter = 6;
  static const double _spinFriction = 0.03;
  static const double _pickSlack = 1.08;
  static const double _levelReelWidth = 60;

  late final AnimationController _spin;
  late final AnimationController _morph;
  late final Animation<double> _progress;
  late final Listenable _repaint;
  final _zoom = ValueNotifier(1.0);
  late _SolidFrame _targetFrame;
  _SolidFrame? _fromFrame;
  late ColorSpaceMode _space;
  late int _shuffleRevision;
  _Grab _grab = _Grab.undecided;
  Offset _travel = Offset.zero;
  Size _size = Size.zero;
  final Map<ColorSpaceMode, _Slice> _slices = {};

  StudioCubit get _cubit => context.read<StudioCubit>();

  @override
  void initState() {
    super.initState();
    final state = _cubit.state;
    final hue = state.activeColor.channelsFor(state.activeSpace)[0].value;
    _space = state.activeSpace;
    _shuffleRevision = state.shuffleRevision;
    _targetFrame = _frameFor(state);
    _spin = AnimationController.unbounded(
      vsync: this,
      value: _Camera.yawFacing(hue),
    );
    _morph = AnimationController(vsync: this, value: 1);
    _progress = _morph.drive(CurveTween(curve: Curves.easeInOutCubic));
    _repaint = Listenable.merge([_spin, _morph, _zoom]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _finishMorph();
  }

  @override
  void dispose() {
    _spin.dispose();
    _morph.dispose();
    _zoom.dispose();
    super.dispose();
  }

  _Camera get _camera =>
      _Camera(yaw: _spin.value, size: _size, zoom: _zoom.value);

  _SolidFrame _frameFor(StudioState state) {
    final space = state.activeSpace;
    final channels = state.activeColor.channelsFor(space);
    final hue = channels[0].value;
    final lightness = channels[2].value;
    final cached = _slices[space];
    final slice = cached != null && cached.matches(space, lightness)
        ? cached
        : _slices[space] = _Slice(space, lightness);
    return _SolidFrame(
      mesh: _SolidMesh.of(space).samples,
      slice: slice.samples,
      lightness: lightness,
      markerHue: hue,
      markerReach:
          chromaReach(space, hue: hue, lightnessPct: lightness) *
          channels[1].value /
          100,
      markerColor: state.activeColor.color,
    );
  }

  static bool _frameChanged(StudioState previous, StudioState next) =>
      previous.activeColor != next.activeColor ||
      previous.activeSpace != next.activeSpace ||
      previous.shuffleRevision != next.shuffleRevision;

  void _updateFrame(StudioState state) {
    final switchedSpace = _space != state.activeSpace;
    final shuffled = _shuffleRevision != state.shuffleRevision;
    _space = state.activeSpace;
    _shuffleRevision = state.shuffleRevision;

    final from = _fromFrame;
    final previousTarget = _targetFrame;
    _targetFrame = _frameFor(state);
    if (MediaQuery.disableAnimationsOf(context) ||
        !(switchedSpace || shuffled)) {
      _finishMorph();
      return;
    }

    // Retarget from the visible shape when the user switches mid-transition.
    _fromFrame = from?.lerp(previousTarget, _progress.value) ?? previousTarget;
    _morph
      ..duration = Duration(milliseconds: switchedSpace ? 300 : 220)
      ..forward(from: 0);
  }

  void _finishMorph() {
    if (_fromFrame == null) return;
    _fromFrame = null;
    _morph.value = 1;
  }

  void _handleScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _zoom.value = (_zoom.value * math.exp(-event.scrollDelta.dy / 420)).clamp(
        0.65,
        2.6,
      );
    });
  }

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
    _finishMorph();
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
        break;
    }
    _endGrab();
  }

  void _endGrab() {
    if (_grab == _Grab.lift || _grab == _Grab.pick) _cubit.endScrub();
    _grab = _Grab.undecided;
  }

  void _handleTapUp(TapUpDetails details) {
    _finishMorph();
    final color = _colorOnSlice(details.localPosition);
    if (color != null) _cubit.setActiveColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocConsumer<StudioCubit, StudioState>(
      buildWhen: _frameChanged,
      listenWhen: _frameChanged,
      listener: (_, state) => _updateFrame(state),
      builder: (context, state) {
        final space = state.activeSpace;
        final channels = state.activeColor.channelsFor(space);
        final lightness = channels[2].value;

        final solid = LayoutBuilder(
          builder: (context, constraints) {
            _size = constraints.biggest;
            return ClipRect(
              child: Listener(
                onPointerSignal: _handleScroll,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: GestureDetector(
                    key: const ValueKey<String>('gamut_solid_canvas'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: _handlePanStart,
                    onPanUpdate: _handlePanUpdate,
                    onPanEnd: _handlePanEnd,
                    onPanCancel: _endGrab,
                    onTapUp: _handleTapUp,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _SolidPainter(
                        repaint: _repaint,
                        spin: _spin,
                        zoom: _zoom,
                        progress: _progress,
                        from: _fromFrame,
                        target: _targetFrame,
                        cageColor: scheme.onSurface,
                      ),
                    ),
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
                  Expanded(
                    child: RepaintBoundary(
                      key: const ValueKey('gamut_solid_viewport'),
                      child: solid,
                    ),
                  ),
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
                  for (final channel in channels.take(2)) ...[
                    if (channel.index == 1) const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${channel.name} ${channel.formattedValue}'),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: _levelReelWidth,
                            child: ChannelReel(
                              key: ValueKey('solid_${channel.index}_reel'),
                              axis: Axis.horizontal,
                              descriptor: channel,
                              space: space,
                              activeColor: state.activeColor,
                              showReadout: false,
                              onScrubStart: _cubit.beginScrub,
                              onScrubUpdate: (value) =>
                                  _cubit.scrubChannel(channel.index, value),
                              onScrubEnd: _cubit.endScrub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
class _Camera({
  required final double yaw,
  required Size size,
  required double zoom,
}) {
  /// Distance from the axis to the widest point of a solid.
  static const double radius = 0.55;
  static const double _pitch = 0.5;
  static final double _sinPitch = math.sin(_pitch);
  static final double _cosPitch = math.cos(_pitch);

  final Offset centre = size.center(Offset.zero);
  final double scale =
      math.max(1, math.min(size.width / 1.3, size.height / 1.65)) * zoom;

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

/// Radial coordinates and opaque vertex colors sampled on a common grid.
class const _GamutSamples(final Float32List reach, final Int32List colors) {
  _GamutSamples lerp(_GamutSamples target, double t) {
    if (identical(this, target)) return this;

    final radii = Float32List(reach.length);
    final blended = Int32List(colors.length);
    for (var i = 0; i < radii.length; i++) {
      radii[i] = reach[i] + (target.reach[i] - reach[i]) * t;
    }
    for (var i = 0; i < blended.length; i++) {
      blended[i] = _mixOpaque(colors[i], target.colors[i], t);
    }
    return _GamutSamples(radii, blended);
  }

  static int _mixOpaque(int from, int to, double t) {
    if (from == to) return from;
    int channel(int shift) {
      final a = (from >> shift) & 0xff;
      final b = (to >> shift) & 0xff;
      return (a + (b - a) * t).round() << shift;
    }

    return 0xff000000 | channel(16) | channel(8) | channel(0);
  }
}

class const _SolidFrame({
  required final _GamutSamples mesh,
  required final _GamutSamples slice,
  required final double lightness,
  required final double markerHue,
  required final double markerReach,
  required final Color markerColor,
}) {
  _SolidFrame lerp(_SolidFrame target, double t) {
    if (t <= 0) return this;
    if (t >= 1) return target;
    final hueDelta = (target.markerHue - markerHue + 540) % 360 - 180;

    return _SolidFrame(
      mesh: mesh.lerp(target.mesh, t),
      slice: slice.lerp(target.slice, t),
      lightness: lightness + (target.lightness - lightness) * t,
      markerHue: (markerHue + hueDelta * t) % 360,
      markerReach: markerReach + (target.markerReach - markerReach) * t,
      markerColor: Color.lerp(markerColor, target.markerColor, t)!,
    );
  }
}

/// The outer gamut sampled on a common hue and lightness grid.
class _SolidMesh._(ColorSpaceMode space) {
  factory of(ColorSpaceMode space) =>
      _cache.putIfAbsent(space, () => _SolidMesh._(space));

  static const int columns = 72;
  static const int rows = 40;
  static final Map<ColorSpaceMode, _SolidMesh> _cache = {};

  final samples = _GamutSamples(
    Float32List((rows + 1) * columns),
    Int32List((rows + 1) * columns),
  );

  this {
    final reach = samples.reach;
    final colors = samples.colors;
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

  static double hueOf(int column) => column * 360 / columns;
  static double lightnessOf(int row) => row * 100 / rows;
}

/// The cut face of a solid at one lightness, as rings from the grey axis out
/// to the edge.
class _Slice(final ColorSpaceMode space, final double lightness) {
  static const int rings = 6;

  final samples = _GamutSamples(
    Float32List(_SolidMesh.columns),
    Int32List((rings + 1) * _SolidMesh.columns),
  );

  this {
    final reach = samples.reach;
    final colors = samples.colors;
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

  bool matches(ColorSpaceMode space, double lightness) =>
      this.space == space && this.lightness == lightness;
}

class _SolidPainter({
  required Listenable repaint,
  required final Animation<double> spin,
  required final ValueListenable<double> zoom,
  required final Animation<double> progress,
  required final _SolidFrame? from,
  required final _SolidFrame target,
  required final Color cageColor,
}) extends CustomPainter {
  static const int _columns = _SolidMesh.columns;
  static const int _cageRingEvery = 5;
  static const int _cageRibEvery = 6;
  static const double _markerRadius = 13;

  this : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final camera = _Camera(yaw: spin.value, size: size, zoom: zoom.value);
    final frame = from?.lerp(target, progress.value) ?? target;
    // Rows of the mesh that sit below the cut.
    final rowsBelow = (frame.lightness / (100 / _SolidMesh.rows)).ceil();

    _paintBelow(canvas, camera, frame, rowsBelow);
    _paintSlice(canvas, camera, frame);
    _paintCage(canvas, camera, frame, rowsBelow);
    _paintMarker(canvas, camera, frame);
  }

  /// The solid from black up to the cut, far faces first.
  void _paintBelow(
    Canvas canvas,
    _Camera camera,
    _SolidFrame frame,
    int rowsBelow,
  ) {
    if (rowsBelow == 0) return;
    final ringCount = rowsBelow + 1;
    final positions = Float32List(ringCount * _columns * 2);
    final colors = Int32List(ringCount * _columns);
    final nearness = Float32List(ringCount * _columns);
    const topColors = _Slice.rings * _columns;
    final mesh = frame.mesh;
    final slice = frame.slice;

    for (var ring = 0; ring < ringCount; ring++) {
      final isCut = ring == rowsBelow;
      final lightness = isCut ? frame.lightness : _SolidMesh.lightnessOf(ring);
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
  void _paintSlice(Canvas canvas, _Camera camera, _SolidFrame frame) {
    const rings = _Slice.rings;
    final slice = frame.slice;
    final positions = Float32List((rings + 1) * _columns * 2);
    final edge = Path();

    for (var ring = 0; ring <= rings; ring++) {
      for (var column = 0; column < _columns; column++) {
        final at = ring * _columns + column;
        final (x, y, _) = camera.project(
          _SolidMesh.hueOf(column),
          slice.reach[column] * _Camera.radius * ring / rings,
          frame.lightness,
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
  void _paintCage(
    Canvas canvas,
    _Camera camera,
    _SolidFrame frame,
    int rowsBelow,
  ) {
    final cage = Path();
    final mesh = frame.mesh;
    final slice = frame.slice;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round;
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
      final aboveCut = _SolidMesh.lightnessOf(row) - frame.lightness;
      if (aboveCut <= 0) continue;
      final ring = [
        for (var column = 0; column < _columns; column++) corner(row, column),
      ];
      if (aboveCut < 4) {
        canvas.drawPath(
          Path()..addPolygon(ring, true),
          paint..color = cageColor.withValues(alpha: 0.14 * aboveCut / 4),
        );
      } else {
        cage.addPolygon(ring, true);
      }
    }
    for (var column = 0; column < _columns; column += _cageRibEvery) {
      final (x, y, _) = camera.project(
        _SolidMesh.hueOf(column),
        slice.reach[column] * _Camera.radius,
        frame.lightness,
      );
      cage.addPolygon([
        Offset(x, y),
        for (var row = rowsBelow; row <= _SolidMesh.rows; row++)
          if (_SolidMesh.lightnessOf(row) > frame.lightness)
            corner(row, column),
      ], false);
    }

    canvas.drawPath(cage, paint..color = cageColor.withValues(alpha: 0.14));
  }

  /// The picked colour, sitting on the cut face.
  void _paintMarker(Canvas canvas, _Camera camera, _SolidFrame frame) {
    final (x, y, _) = camera.project(
      frame.markerHue,
      frame.markerReach * _Camera.radius,
      frame.lightness,
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
    canvas.drawCircle(
      centre,
      _markerRadius - 3,
      Paint()..color = frame.markerColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SolidPainter oldDelegate) {
    return oldDelegate.target != target ||
        oldDelegate.from != from ||
        oldDelegate.cageColor != cageColor;
  }
}
