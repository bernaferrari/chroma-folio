import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Descriptor for an option inside [StudioPillSelector].
class StudioPillOption<T> {
  const StudioPillOption({
    required this.value,
    required this.label,
    this.icon,
    this.iconOnly = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Shows just [icon], keeping [label] as the tooltip and spoken name.
  final bool iconOnly;
}

/// Sleek, single-line segmented pill control that never wraps text across lines.
///
/// When [canvasInk] is provided, renders in translucent adaptive ink suitable for
/// placement directly over any live color surface.
class StudioPillSelector<T> extends StatelessWidget {
  const StudioPillSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.expand = false,
    this.canvasInk,
  });

  final List<StudioPillOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool compact;

  /// Fills the available width with equally wide options.
  final bool expand;
  final Color? canvasInk;

  Widget _item(
    StudioPillOption<T> option,
    Color selectedBg,
    Color selectedBorder,
  ) {
    final item = _PillItem<T>(
      option: option,
      selected: option.value == value,
      compact: compact,
      selectedBg: selectedBg,
      selectedBorder: selectedBorder,
      inkOverride: canvasInk,
      onTap: () {
        if (option.value != value) {
          HapticFeedback.selectionClick();
          onChanged(option.value);
        }
      },
    );
    return expand ? Expanded(child: item) : item;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = canvasInk;

    final trackColor = ink != null
        ? ink.withValues(alpha: 0.10)
        : (isDark ? const Color(0xFF16181F) : const Color(0xFFECE9E1));
    final selectedBg = ink != null
        ? ink.withValues(alpha: 0.20)
        : (isDark ? const Color(0xFF292C36) : Colors.white);
    final selectedBorder = ink != null
        ? ink.withValues(alpha: 0.28)
        : (isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06));
    final trackBorder = ink != null
        ? ink.withValues(alpha: 0.16)
        : scheme.outlineVariant.withValues(alpha: isDark ? 0.24 : 0.38);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(compact ? 11 : 13),
        border: Border.all(color: trackBorder),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final option in options)
            _item(option, selectedBg, selectedBorder),
        ],
      ),
    );
  }
}

class _PillItem<T> extends StatelessWidget {
  const _PillItem({
    required this.option,
    required this.selected,
    required this.compact,
    required this.selectedBg,
    required this.selectedBorder,
    required this.onTap,
    this.inkOverride,
  });

  final StudioPillOption<T> option;
  final bool selected;
  final bool compact;
  final Color selectedBg;
  final Color selectedBorder;
  final Color? inkOverride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = inkOverride != null
        ? inkOverride!.withValues(alpha: selected ? 0.96 : 0.65)
        : (selected ? scheme.onSurface : scheme.onSurfaceVariant);

    final icon = option.icon;
    final showsIconOnly = option.iconOnly && icon != null;
    final fontSize = compact ? 12.0 : 12.5;
    final labelHeight = MediaQuery.textScalerOf(context).scale(fontSize) * 1.15;
    final tabHeight =
        math.max(18.0, labelHeight.ceilToDouble()) + (compact ? 12.0 : 14.0);

    final item = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: tabHeight,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          decoration: BoxDecoration(
            color: selected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(compact ? 8 : 10),
            border: Border.all(
              color: selected ? selectedBorder : Colors.transparent,
            ),
            boxShadow: selected && !isDark && inkOverride == null
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Align(
            widthFactor: 1,
            child: showsIconOnly
                ? Icon(icon, size: 18, color: fg, semanticLabel: option.label)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: compact ? 14 : 15, color: fg),
                        SizedBox(width: compact ? 5 : 6),
                      ],
                      Flexible(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontSize: fontSize,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: fg,
                                height: 1.15,
                              ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    if (!showsIconOnly) return item;
    return Tooltip(
      message: option.label,
      waitDuration: const Duration(milliseconds: 400),
      child: item,
    );
  }
}

/// Hairline neutral toggle pill for single switches like WCAG markers.
class StudioTogglePill extends StatelessWidget {
  const StudioTogglePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? scheme.onSurface
        : (isDark ? const Color(0xFF16181F) : const Color(0xFFECE9E1));
    final fg = selected ? scheme.surface : scheme.onSurfaceVariant;
    final border = selected
        ? Colors.transparent
        : scheme.outlineVariant.withValues(alpha: isDark ? 0.24 : 0.38);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round icon button that works on paper or, with [ink], on a live colour.
class StudioIconButton extends StatefulWidget {
  const StudioIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.ink,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;

  /// Null disables the button.
  final VoidCallback? onTap;

  /// Text colour of the surface behind the button, when it is not paper.
  final Color? ink;
  final bool selected;

  @override
  State<StudioIconButton> createState() => _StudioIconButtonState();
}

class _StudioIconButtonState extends State<StudioIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ink = widget.ink ?? Theme.of(context).colorScheme.onSurface;
    final enabled = widget.onTap != null;
    final fill = !enabled
        ? 0.0
        : widget.selected
        ? 0.22
        : _pressed
        ? 0.18
        : _hovered
        ? 0.12
        : 0.07;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _pressed ? 0.92 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: fill),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: ink.withValues(alpha: enabled ? 0.86 : 0.26),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Editorial serif display typography inspired by Moleskine Timepage & Paper.
TextStyle studioDisplayStyle(
  BuildContext context, {
  double? fontSize,
  FontWeight fontWeight = FontWeight.w400,
  FontStyle fontStyle = FontStyle.normal,
  double? height,
  double? letterSpacing,
  Color? color,
}) {
  final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
  if (!GoogleFonts.config.allowRuntimeFetching) {
    return TextStyle(
      fontFamily: 'serif',
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      height: height,
      letterSpacing: letterSpacing,
      color: effectiveColor,
    );
  }
  return GoogleFonts.instrumentSerif(
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    height: height,
    letterSpacing: letterSpacing,
    color: effectiveColor,
  );
}

TextStyle studioMonoStyle(
  BuildContext context, {
  double? fontSize,
  FontWeight fontWeight = FontWeight.w500,
  Color? color,
}) {
  final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
  if (!GoogleFonts.config.allowRuntimeFetching) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: effectiveColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
  return GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: effectiveColor,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

ThemeData buildStudioTheme(Brightness brightness, Color seedColor) {
  final isDark = brightness == Brightness.dark;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );

  // Archival warm paper in light mode; velvety obsidian charcoal in dark mode.
  final scheme = isDark
      ? baseScheme.copyWith(
          surface: const Color(0xFF0C0D10),
          surfaceContainerLowest: const Color(0xFF08090B),
          surfaceContainerLow: const Color(0xFF12141A),
          surfaceContainer: const Color(0xFF181A22),
          surfaceContainerHigh: const Color(0xFF20232D),
          surfaceContainerHighest: const Color(0xFF282B37),
          onSurface: const Color(0xFFF3F1EC),
          onSurfaceVariant: const Color(0xFF9EA0A8),
        )
      : baseScheme.copyWith(
          surface: const Color(0xFFF6F4EE),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFFCFAF5),
          surfaceContainer: const Color(0xFFEFECE4),
          surfaceContainerHigh: const Color(0xFFE6E2D8),
          onSurface: const Color(0xFF191918),
          onSurfaceVariant: const Color(0xFF6B6A66),
        );

  final baseText = isDark
      ? ThemeData.dark().textTheme
      : ThemeData.light().textTheme;
  final resolvedTextTheme = GoogleFonts.config.allowRuntimeFetching
      ? GoogleFonts.plusJakartaSansTextTheme(baseText)
      : baseText;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: resolvedTextTheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.22 : 0.36),
        ),
      ),
    ),
  );
}

Future<void> copyWithFeedback(
  BuildContext context,
  String value, {
  String? label,
}) async {
  HapticFeedback.selectionClick();
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          label != null ? 'Copied $label' : 'Copied $value',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}
