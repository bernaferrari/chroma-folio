import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/color_spaces.dart';
import 'reel.dart';
import 'studio_theme.dart';

/// One colour channel as a reel: drag or fling the strip of colours and the
/// one that lands in the lens becomes the picked value.
class const ChannelReel({
  super.key,
  required final ChannelDescriptor descriptor,
  required final ColorSpaceMode space,
  required final StudioColor activeColor,
  required final VoidCallback onScrubStart,
  required final ValueChanged<double> onScrubUpdate,
  required final VoidCallback onScrubEnd,

  /// Whether the channel name and value are shown above the reel.
  final bool showReadout = true,
  final Axis axis = Axis.vertical,
}) extends StatefulWidget {
  @override
  State<ChannelReel> createState() => _ChannelReelState();
}

class _ChannelReelState extends State<ChannelReel>
    with SingleTickerProviderStateMixin {
  static const double _hueStep = 15;
  static const double _levelStep = 5;

  /// Every reel shares one band size, so a drag moves each one the same.
  static const double _bandLength = 36;

  /// Short reels shrink their bands to keep at least this many in view.
  static const double _minBandsInView = 7;
  static const double _lensInset = 7;
  static const double _lensOverhang = 7;

  late final ReelMotion _motion;
  final FocusNode _focusNode = FocusNode(debugLabel: 'ChannelReel');
  bool _pressed = false;

  bool get _isVertical => widget.axis == Axis.vertical;
  bool get _isHue => widget.descriptor.index == 0;

  @override
  void initState() {
    super.initState();
    _motion = ReelMotion(
      vsync: this,
      onStart: () => widget.onScrubStart(),
      onChanged: (value) => widget.onScrubUpdate(value),
      onEnd: () => widget.onScrubEnd(),
    );
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _motion.dispose();
    super.dispose();
  }

  void _handleFocusChange() => setState(() {});

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final previous = _isVertical
        ? LogicalKeyboardKey.arrowUp
        : LogicalKeyboardKey.arrowLeft;
    final next = _isVertical
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    if (event.logicalKey != previous && event.logicalKey != next) {
      return KeyEventResult.ignored;
    }
    final amount = HardwareKeyboard.instance.isShiftPressed
        ? _motion.step
        : 1.0;
    final increases = (event.logicalKey == previous) == _motion.reversed;
    _motion.nudge(increases ? amount : -amount);
    return KeyEventResult.handled;
  }

  String _spoken(double value) {
    final descriptor = widget.descriptor;
    final reachable = _isHue
        ? value % 360
        : value.clamp(descriptor.min, descriptor.max);
    return '${reachable.round()}${descriptor.unit}';
  }

  Future<void> _enterExactValue() async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _ExactValueDialog(descriptor: widget.descriptor),
    );
    if (result == null) return;
    _motion.nudge(result - _motion.position);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final descriptor = widget.descriptor;
    final showsFocus =
        _focusNode.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    _motion
      ..min = descriptor.min
      ..max = descriptor.max
      ..wraps = _isHue
      ..reversed = _isVertical && !_isHue
      ..step = _isHue ? _hueStep : _levelStep
      ..sync(descriptor.value);

    return Semantics(
      slider: true,
      label: descriptor.name,
      value: descriptor.formattedValue,
      increasedValue: _spoken(descriptor.value + _motion.step),
      decreasedValue: _spoken(descriptor.value - _motion.step),
      onIncrease: () => _motion.nudge(_motion.step),
      onDecrease: () => _motion.nudge(-_motion.step),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showReadout) ...[
            _ChannelReadout(
              descriptor: descriptor,
              highlighted: showsFocus,
              onTap: _enterExactValue,
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _handleKey,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(28),
                ),

                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final extent = _isVertical
                        ? constraints.maxHeight
                        : constraints.maxWidth;
                    final bandLength = math.min(
                      _bandLength,
                      extent / _minBandsInView,
                    );
                    _motion.pixelsPerUnit = bandLength / _motion.step;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: ReelSurface(
                            motion: _motion,
                            axis: widget.axis,
                            onPressedChanged: (pressed) {
                              if (pressed) _focusNode.requestFocus();
                              setState(() => _pressed = pressed);
                            },
                            child: CustomPaint(
                              painter: ReelStripPainter(
                                motion: _motion,
                                axis: widget.axis,
                                paletteKey: (
                                  widget.activeColor,
                                  widget.space,
                                  bandLength,
                                ),
                                colorAt: (value) =>
                                    widget.activeColor.sampleChannel(
                                      widget.space,
                                      descriptor.index,
                                      value,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _isVertical ? _lensInset : null,
                          right: _isVertical ? _lensInset : null,
                          top: _isVertical ? null : _lensInset,
                          bottom: _isVertical ? null : _lensInset,
                          height: _isVertical
                              ? bandLength + _lensOverhang * 2
                              : null,
                          width: _isVertical
                              ? null
                              : bandLength + _lensOverhang * 2,
                          child: ListenableBuilder(
                            listenable: _motion,
                            builder: (context, _) => ReelLens(
                              color: widget.activeColor.color,
                              pressed: _pressed,
                              push: _isVertical
                                  ? Offset(0, _motion.overshoot)
                                  : Offset(_motion.overshoot, 0),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Channel name with its live value set large, tappable to type a number.
class const _ChannelReadout({
  required final ChannelDescriptor descriptor,

  /// Whether the reel below has keyboard focus.
  required final bool highlighted,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final number = descriptor.unit.isEmpty
        ? descriptor.formattedValue
        : descriptor.formattedValue.replaceAll(descriptor.unit, '');

    return Tooltip(
      message: 'Type a value',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  descriptor.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                    color: highlighted
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: Text.rich(
                          TextSpan(
                            text: number,
                            children: [
                              TextSpan(
                                text: descriptor.unit,
                                style: TextStyle(
                                  fontSize: descriptor.unit == '°' ? null : 26,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.42,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          style: studioDisplayStyle(
                            context,
                            fontSize: 44,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                    if (descriptor.secondaryLabel != null)
                      Expanded(
                        child: Text(
                          descriptor.secondaryLabel!,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          textAlign: TextAlign.end,
                          style: studioMonoStyle(
                            context,
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a channel value as a number.
class const _ExactValueDialog({required final ChannelDescriptor descriptor})
    extends StatefulWidget {
  @override
  State<_ExactValueDialog> createState() => _ExactValueDialogState();
}

class _ExactValueDialogState extends State<_ExactValueDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.descriptor.value.round().toString(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final descriptor = widget.descriptor;
    final parsed = double.tryParse(
      _controller.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null) return;
    Navigator.of(context)
        .pop(parsed.clamp(descriptor.min, descriptor.max).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = widget.descriptor;
    return AlertDialog(
      title: Text(
        descriptor.name,
        style: studioDisplayStyle(context, fontSize: 30),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: studioMonoStyle(context, fontSize: 18),
        decoration: InputDecoration(
          helperText: '${descriptor.min.round()} to ${descriptor.max.round()}',
          suffixText: descriptor.unit,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Set')),
      ],
    );
  }
}
