import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/studio_cubit.dart';
import '../models/color_spaces.dart';
import '../widgets/specimen_stage.dart';
import '../widgets/studio_theme.dart';
import 'picker_screen.dart';
import 'gamut_solid_screen.dart';
import 'scales_harmonies_screen.dart';
import 'space_comparison_screen.dart';

enum _Lens { reels, spectrum, solid, palette }

/// App shell: the specimen on one side, and the tools that change it on the
/// other.
class StudioHome extends StatefulWidget {
  const StudioHome({super.key});

  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  static const double _sidePanelBreakpoint = 900;
  static const double _singleRowToolbarWidth = 740;
  static const double _sideBySideToolsWidth = 500;

  _Lens _lens = _Lens.reels;

  bool get _isEditingText {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return focused.widget is EditableText ||
        focused.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _unlessTyping(VoidCallback action) {
    if (!_isEditingText) action();
  }

  Widget _buildLens() {
    switch (_lens) {
      case _Lens.reels:
        return const PickerScreen(key: ValueKey<_Lens>(_Lens.reels));
      case _Lens.spectrum:
        return const SpaceComparisonScreen(
          key: ValueKey<_Lens>(_Lens.spectrum),
        );
      case _Lens.solid:
        return const GamutSolidScreen(key: ValueKey<_Lens>(_Lens.solid));
      case _Lens.palette:
        return const ScalesHarmoniesScreen(key: ValueKey<_Lens>(_Lens.palette));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hasSidePanel = size.width >= _sidePanelBreakpoint;
    final cubit = context.read<StudioCubit>();

    final brand = Text(
      'Chroma Folio',
      maxLines: 1,
      softWrap: false,
      style: studioDisplayStyle(context, fontSize: 28, height: 1.0),
    );
    StudioPillSelector<_Lens> lensSelector({bool expand = false}) {
      return StudioPillSelector<_Lens>(
        value: _lens,
        expand: expand,
        options: const [
          StudioPillOption(
            value: _Lens.reels,
            label: 'Reels',
            icon: Icons.view_week_rounded,
            iconOnly: true,
          ),
          StudioPillOption(
            value: _Lens.spectrum,
            label: 'Spectrum',
            icon: Icons.table_rows_rounded,
            iconOnly: true,
          ),
          StudioPillOption(
            value: _Lens.solid,
            label: 'Solid',
            icon: Icons.view_in_ar_rounded,
            iconOnly: true,
          ),
          StudioPillOption(
            value: _Lens.palette,
            label: 'Palette',
            icon: Icons.palette_outlined,
            iconOnly: true,
          ),
        ],
        onChanged: (lens) => setState(() => _lens = lens),
      );
    }

    const actions = _HistoryAndThemeActions();

    final workspace = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _buildLens(),
    );

    final toolsRow = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sideBySideToolsWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              lensSelector(expand: true),
              const SizedBox(height: 8),
              const _SpaceSelector(expand: true),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [lensSelector(), const _SpaceSelector()],
        );
      },
    );

    final Widget body;
    if (hasSidePanel) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: (size.width * 0.34).clamp(340.0, 440.0),
              child: const SpecimenStage(expanded: true),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fitsOneRow =
                      constraints.maxWidth >= _singleRowToolbarWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          brand,
                          const SizedBox(width: 16),
                          Expanded(
                            child: fitsOneRow
                                ? FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      children: [
                                        lensSelector(),
                                        const SizedBox(width: 12),
                                        const _SpaceSelector(),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 12),
                          actions,
                        ],
                      ),
                      if (!fitsOneRow) ...[
                        const SizedBox(height: 12),
                        toolsRow,
                      ],
                      const SizedBox(height: 20),
                      Expanded(child: workspace),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: brand),
                actions,
              ],
            ),
            const SizedBox(height: 10),
            const SpecimenStage(expanded: false),
            const SizedBox(height: 14),
            toolsRow,
            const SizedBox(height: 14),
            Expanded(child: workspace),
          ],
        ),
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _unlessTyping(() {
              HapticFeedback.selectionClick();
              cubit.shufflePalette();
            }),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            _unlessTyping(cubit.undo),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            _unlessTyping(cubit.undo),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): () =>
            _unlessTyping(cubit.redo),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () =>
            _unlessTyping(cubit.redo),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(body: SafeArea(child: body)),
      ),
    );
  }
}

class _SpaceSelector extends StatelessWidget {
  const _SpaceSelector({this.expand = false});

  final bool expand;

  static const _spaces = [
    ColorSpaceMode.hsluv,
    ColorSpaceMode.oklch,
    ColorSpaceMode.hct,
    ColorSpaceMode.hsl,
  ];

  @override
  Widget build(BuildContext context) {
    final space = context.select(
      (StudioCubit cubit) => cubit.state.activeSpace,
    );
    return StudioPillSelector<ColorSpaceMode>(
      value: _spaces.contains(space) ? space : ColorSpaceMode.hsluv,
      expand: expand,
      options: [
        for (final option in _spaces)
          StudioPillOption(value: option, label: option.label),
      ],
      onChanged: context.read<StudioCubit>().setSpaceMode,
    );
  }
}

class _HistoryAndThemeActions extends StatelessWidget {
  const _HistoryAndThemeActions();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<StudioCubit>();
    final canUndo = context.select((StudioCubit c) => c.state.canUndo);
    final canRedo = context.select((StudioCubit c) => c.state.canRedo);
    final isDark = context.select(
      (StudioCubit c) => c.state.themeMode == ThemeMode.dark,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioIconButton(
          icon: Icons.undo_rounded,
          tooltip: 'Undo',
          onTap: canUndo ? cubit.undo : null,
        ),
        const SizedBox(width: 4),
        StudioIconButton(
          icon: Icons.redo_rounded,
          tooltip: 'Redo',
          onTap: canRedo ? cubit.redo : null,
        ),
        const SizedBox(width: 4),
        StudioIconButton(
          icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          tooltip: isDark ? 'Light theme' : 'Dark theme',
          onTap: () {
            HapticFeedback.selectionClick();
            cubit.toggleThemeMode();
          },
        ),
      ],
    );
  }
}
