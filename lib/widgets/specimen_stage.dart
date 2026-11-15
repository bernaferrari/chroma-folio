import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/studio_cubit.dart';
import '../models/accessibility_utils.dart';
import '../models/color_spaces.dart';
import 'studio_theme.dart';

/// The picked colour shown as itself, with its name, its codes and the
/// palette it belongs to.
class SpecimenStage extends StatefulWidget {
  const SpecimenStage({super.key, required this.expanded});

  /// Whether the stage fills a tall side panel or sits as a compact card.
  final bool expanded;

  @override
  State<SpecimenStage> createState() => _SpecimenStageState();
}

class _SpecimenStageState extends State<SpecimenStage> {
  @override
  void initState() {
    super.initState();
    ColorNameLookup.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  String _coordinates(StudioColor color, ColorSpaceMode space) {
    switch (space) {
      case ColorSpaceMode.oklch:
        return '${color.oklch.lightness.round()}%  '
            '${color.oklch.chroma.toStringAsFixed(2)}  '
            '${color.oklch.hue.round()}°';
      case ColorSpaceMode.hct:
        return '${color.hctHue.round()}°  '
            '${color.hctChroma.round()}  '
            '${color.hctTone.round()}';
      case ColorSpaceMode.hsl:
        return '${color.hsl.hue.round()}°  '
            '${(color.hsl.saturation * 100).round()}%  '
            '${(color.hsl.lightness * 100).round()}%';
      case ColorSpaceMode.hsluv:
      case ColorSpaceMode.hsv:
        return '${color.hsluv.hue.round()}°  '
            '${color.hsluv.saturation.round()}%  '
            '${color.hsluv.lightness.round()}%';
    }
  }

  Future<void> _enterColor(StudioColor current) async {
    final cubit = context.read<StudioCubit>();
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => _ColourEntryDialog(current: current),
    );
    if (result != null) cubit.setActiveColor(StudioColor.fromColor(result));
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.expanded;
    return BlocBuilder<StudioCubit, StudioState>(
      buildWhen: (prev, next) =>
          prev.palette != next.palette ||
          prev.selectedIndex != next.selectedIndex ||
          prev.activeSpace != next.activeSpace,
      builder: (context, state) {
        final cubit = context.read<StudioCubit>();
        final active = state.activeColor;
        final ink = contrastingTextColor(active.color);
        final name = ColorNameLookup.nearestNameSync(active.color) ?? '';

        return Container(
          decoration: BoxDecoration(
            color: active.color,
            borderRadius: BorderRadius.circular(expanded ? 32 : 28),
            border: Border.all(color: ink.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: active.color.withValues(alpha: 0.26),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          padding: EdgeInsets.all(expanded ? 24 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (expanded) const Spacer(),
              Text(
                name,
                maxLines: expanded ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: studioDisplayStyle(
                  context,
                  fontSize: expanded ? 56 : 38,
                  height: 1.0,
                  letterSpacing: -0.6,
                  color: ink,
                ),
              ),
              SizedBox(height: expanded ? 14 : 10),
              Row(
                children: [
                  _HexLabel(
                    hex: active.hex,
                    ink: ink,
                    onTap: () => copyWithFeedback(context, active.hex),
                  ),
                  const SizedBox(width: 4),
                  _QuietIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Enter a colour',
                    ink: ink,
                    onTap: () => _enterColor(active),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _coordinates(active, state.activeSpace),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      textAlign: TextAlign.end,
                      style: studioMonoStyle(
                        context,
                        fontSize: 12,
                        color: ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: expanded ? 16 : 12),
              _PaletteTray(
                palette: state.palette,
                selectedIndex: state.selectedIndex,
                onSelect: (index) {
                  if (index == state.selectedIndex) return;
                  HapticFeedback.selectionClick();
                  cubit.selectSlot(index);
                },
                onShuffle: () {
                  HapticFeedback.lightImpact();
                  cubit.shufflePalette();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The hex value set as plain type on the colour; tap to copy it.
class _HexLabel extends StatelessWidget {
  const _HexLabel({required this.hex, required this.ink, required this.onTap});

  final String hex;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copy',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hex,
                  style: studioMonoStyle(
                    context,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.copy_rounded,
                  size: 15,
                  color: ink.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon with no plate behind it, for sitting directly on a colour.
class _QuietIconButton extends StatelessWidget {
  const _QuietIconButton({
    required this.icon,
    required this.tooltip,
    required this.ink,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        label: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox.square(
              dimension: 32,
              child: Icon(icon, size: 16, color: ink.withValues(alpha: 0.6)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The palette as a strip of paint in a paper tray, with shuffle at its end.
///
/// The colours touch each other, except the selected one, which stands apart
/// from its neighbours as its own chip.
class _PaletteTray extends StatelessWidget {
  const _PaletteTray({
    required this.palette,
    required this.selectedIndex,
    required this.onSelect,
    required this.onShuffle,
  });

  static const double _height = 50;
  static const double _inset = 3;
  static const double _shuffleWidth = 36 + 6 + 3;

  final List<StudioColor> palette;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onShuffle;

  void _selectAt(double localDx, double stripWidth) {
    if (stripWidth <= 0 || palette.isEmpty) return;
    final fraction = (localDx / stripWidth).clamp(0.0, 0.9999);
    onSelect((fraction * palette.length).floor());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stripWidth = constraints.maxWidth - _shuffleWidth;
          return Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _selectAt(details.localPosition.dx, stripWidth),
                    onHorizontalDragStart: (details) =>
                        _selectAt(details.localPosition.dx, stripWidth),
                    onHorizontalDragUpdate: (details) =>
                        _selectAt(details.localPosition.dx, stripWidth),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < palette.length; i++)
                            Expanded(
                              child: _Swatch(
                                color: palette[i].color,
                                isSelected: i == selectedIndex,
                                gapBefore:
                                    i > 0 &&
                                    (i == selectedIndex ||
                                        i - 1 == selectedIndex),
                                gapAfter:
                                    i < palette.length - 1 &&
                                    (i == selectedIndex ||
                                        i + 1 == selectedIndex),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              StudioIconButton(
                icon: Icons.shuffle_rounded,
                tooltip: 'Shuffle palette (Space)',
                onTap: onShuffle,
              ),
              const SizedBox(width: 3),
            ],
          );
        },
      ),
    );
  }
}

/// One colour of the palette strip.
///
/// A gap opens on each side that borders the selected colour, and the
/// corners beside a gap are rounded.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.isSelected,
    required this.gapBefore,
    required this.gapAfter,
  });

  static const double _halfGap = 1.5;
  static const Radius _chipCorner = Radius.circular(10);
  static const Radius _neighbourCorner = Radius.circular(5);

  final Color color;
  final bool isSelected;
  final bool gapBefore;
  final bool gapAfter;

  @override
  Widget build(BuildContext context) {
    final corner = isSelected ? _chipCorner : _neighbourCorner;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(
        left: gapBefore ? _halfGap : 0,
        right: gapAfter ? _halfGap : 0,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: gapBefore || isSelected ? corner : Radius.zero,
          right: gapAfter || isSelected ? corner : Radius.zero,
        ),
      ),
    );
  }
}

/// Asks for a colour as hex, rgb() or oklch(), previewing it while typing.
class _ColourEntryDialog extends StatefulWidget {
  const _ColourEntryDialog({required this.current});

  final StudioColor current;

  @override
  State<_ColourEntryDialog> createState() => _ColourEntryDialogState();
}

class _ColourEntryDialogState extends State<_ColourEntryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current.hex,
  );
  late Color? _preview = widget.current.color;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_preview != null) Navigator.of(context).pop(_preview);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _preview ?? widget.current.color;
    return AlertDialog(
      title: Text(
        'Enter a colour',
        style: studioDisplayStyle(context, fontSize: 30),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 72,
            decoration: BoxDecoration(
              color: shown,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              _preview == null
                  ? 'Not a colour yet'
                  : StudioColor.fromColor(shown).hex,
              style: studioMonoStyle(
                context,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: contrastingTextColor(shown),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: studioMonoStyle(context, fontSize: 15),
            decoration: const InputDecoration(
              helperText: 'Hex, rgb() or oklch()',
              hintText: '#3B82F6',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() => _preview = parseColorInput(value));
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _preview == null ? null : _submit,
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}
