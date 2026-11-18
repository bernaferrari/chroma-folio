import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoSlidingSegmentedControl;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

const studioPhoneBreakpoint = 568.0;

/// Shared styling for the studio's Cupertino segmented controls.
class const StudioSegmentedControl<T extends Object>({
  super.key,
  required final T value,
  required final Map<T, String> labels,
  required final ValueChanged<T> onChanged,
  final Map<T, IconData> icons = const {},
  final bool compact = false,
}) extends StatelessWidget {
  // Match Cupertino's fixed separator ink before mapping the whole control
  // to the studio palette. The separator then disappears at any opacity.
  static const _track = Color(0xFF8E8E93);
  // Keep the light palette inside the filter's range so it preserves the
  // partially covered pixels at the edges of each glyph.
  static const _lightThumb = Color(0xFF999BA5);
  static const _lightSelectedInk = Color(0xFF0B0D16);
  static const _light = ColorFilter.matrix([
    1.6,
    0,
    0,
    0,
    9,
    0,
    1.6,
    0,
    0,
    6,
    0,
    0,
    1.6,
    0,
    -11,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const _dark = ColorFilter.matrix([
    1.7,
    0,
    0,
    0,
    -225,
    0,
    1.7,
    0,
    0,
    -223,
    0,
    0,
    1.7,
    0,
    -219,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPhone = MediaQuery.sizeOf(context).width < studioPhoneBreakpoint;
    final minHeight = compact ? 30.0 : (isPhone ? 44.0 : 40.0);
    final selectedInk = isDark ? Colors.white : _lightSelectedInk;
    // These colors are mapped by the filter to muted label colors.
    final unselectedInk = isDark
        ? const Color(0xFFDDDDDD)
        : const Color(0xFF3E3F47);
    TextStyle labelStyle(bool selected) {
      final style = (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
        color: selected ? selectedInk : unselectedInk,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      );
      return GoogleFonts.config.allowRuntimeFetching
          ? GoogleFonts.plusJakartaSans(textStyle: style)
          : style;
    }

    return ColorFiltered(
      colorFilter: isDark ? _dark : _light,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        proportionalWidth: true,
        backgroundColor: _track,
        thumbColor: isDark ? const Color(0xFF9D9DA2) : _lightThumb,
        onValueChanged: (next) {
          if (next == null || next == value) return;
          HapticFeedback.selectionClick();
          onChanged(next);
        },
        children: {
          for (final entry in labels.entries)
            entry.key: ConstrainedBox(
              constraints: BoxConstraints(minWidth: 24, minHeight: minHeight),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icons[entry.key] case final icon?) ...[
                    Icon(
                      icon,
                      size: 14,
                      color: entry.key == value ? selectedInk : unselectedInk,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle(entry.key == value),
                    ),
                  ),
                ],
              ),
            ),
        },
      ),
    );
  }
}

/// Hairline neutral toggle pill for single switches like WCAG markers.
class const StudioTogglePill({
  super.key,
  required final String label,
  required final bool selected,
  required final VoidCallback onTap,
  final IconData? icon,
}) extends StatelessWidget {
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
class const StudioIconButton({
  super.key,
  required final IconData icon,
  required final String tooltip,

  /// Null disables the button.
  required final VoidCallback? onTap,

  /// Text colour of the surface behind the button, when it is not paper.
  final Color? ink,
  final bool selected = false,
}) extends StatefulWidget {
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
