import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../models/accessibility_utils.dart';
import '../models/color_spaces.dart';

class const StudioState({
  required final List<StudioColor> palette,
  required final int selectedIndex,
  required final ColorSpaceMode activeSpace,
  required final ThemeMode themeMode,
  required final List<List<StudioColor>> undoStack,
  required final List<List<StudioColor>> redoStack,
  final int shuffleRevision = 0,
}) extends Equatable {
  factory initial() {
    return StudioState(
      palette: defaultStudioPalette(),
      selectedIndex: 0,
      activeSpace: ColorSpaceMode.hsluv,
      themeMode: ThemeMode.light,
      undoStack: const [],
      redoStack: const [],
    );
  }

  StudioColor get activeColor => palette[selectedIndex];
  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  StudioState copyWith({
    List<StudioColor>? palette,
    int? selectedIndex,
    ColorSpaceMode? activeSpace,
    ThemeMode? themeMode,
    List<List<StudioColor>>? undoStack,
    List<List<StudioColor>>? redoStack,
    int? shuffleRevision,
  }) {
    return StudioState(
      palette: palette ?? this.palette,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      activeSpace: activeSpace ?? this.activeSpace,
      themeMode: themeMode ?? this.themeMode,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      shuffleRevision: shuffleRevision ?? this.shuffleRevision,
    );
  }

  @override
  List<Object?> get props => [
    palette,
    selectedIndex,
    activeSpace,
    themeMode,
    undoStack,
    redoStack,
    shuffleRevision,
  ];
}

class StudioCubit() extends Cubit<StudioState> {
  this : super(StudioState.initial());

  List<StudioColor>? _scrubSnapshot;
  static const int _maxHistory = 30;

  void selectSlot(int index) {
    if (index < 0 || index >= state.palette.length) return;
    emit(state.copyWith(selectedIndex: index));
  }

  void setActiveColor(StudioColor color, {bool recordHistory = true}) {
    final updated = List<StudioColor>.from(state.palette);
    if (updated[state.selectedIndex] == color) return;
    final undo = recordHistory
        ? _pushUndo(state.undoStack, state.palette)
        : state.undoStack;
    updated[state.selectedIndex] = color;
    emit(
      state.copyWith(
        palette: updated,
        undoStack: undo,
        redoStack: recordHistory ? const [] : state.redoStack,
      ),
    );
  }

  void beginScrub() {
    _scrubSnapshot = List<StudioColor>.from(state.palette);
  }

  void scrubChannel(int channelIndex, double newValue) {
    final updatedColor = state.activeColor.withChannelValue(
      state.activeSpace,
      channelIndex,
      newValue,
    );
    setActiveColor(updatedColor, recordHistory: false);
  }

  void scrubHsluvHueSat(double hue, double saturation) {
    final updatedColor = StudioColor.fromHsluv(
      state.activeColor.hsluv
          .withHue(hue)
          .withSaturation(saturation.clamp(0.0, 100.0)),
    );
    setActiveColor(updatedColor, recordHistory: false);
  }

  void scrubTwoChannels({
    required int xChannel,
    required double xValue,
    required int yChannel,
    required double yValue,
  }) {
    final step1 = state.activeColor.withChannelValue(
      state.activeSpace,
      xChannel,
      xValue,
    );
    final step2 = step1.withChannelValue(state.activeSpace, yChannel, yValue);
    setActiveColor(step2, recordHistory: false);
  }

  void endScrub() {
    final snap = _scrubSnapshot;
    _scrubSnapshot = null;
    if (snap != null && snap[state.selectedIndex] != state.activeColor) {
      emit(
        state.copyWith(
          undoStack: _pushUndo(state.undoStack, snap),
          redoStack: const [],
        ),
      );
    }
  }

  void setSpaceMode(ColorSpaceMode mode) {
    emit(state.copyWith(activeSpace: mode));
  }

  void toggleThemeMode() {
    final next = state.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    emit(state.copyWith(themeMode: next));
  }

  void shufflePalette() {
    final seedHue = math.Random().nextDouble() * 360.0;
    emit(
      state.copyWith(
        palette: generateHarmoniousPalette(seedHue),
        shuffleRevision: state.shuffleRevision + 1,
        undoStack: _pushUndo(state.undoStack, state.palette),
        redoStack: const [],
      ),
    );
  }

  void applyColorsToPalette(List<StudioColor> colors) {
    final updated = List<StudioColor>.from(state.palette);
    for (int i = 0; i < updated.length && i < colors.length; i++) {
      updated[i] = colors[i];
    }
    emit(
      state.copyWith(
        palette: updated,
        undoStack: _pushUndo(state.undoStack, state.palette),
        redoStack: const [],
      ),
    );
  }

  bool fixActiveColorContrast(
    double targetRatio, {
    Color against = Colors.white,
  }) {
    final solved = solveHsluvForContrast(
      state.activeColor.hsluv,
      against,
      targetRatio,
    );
    if (solved == null) return false;
    setActiveColor(StudioColor.fromHsluv(solved));
    return true;
  }

  void undo() {
    if (state.undoStack.isEmpty) return;
    final prev = state.undoStack.last;
    final nextUndo = state.undoStack.sublist(0, state.undoStack.length - 1);
    final nextRedo = [...state.redoStack, state.palette];
    emit(
      state.copyWith(palette: prev, undoStack: nextUndo, redoStack: nextRedo),
    );
  }

  void redo() {
    if (state.redoStack.isEmpty) return;
    final next = state.redoStack.last;
    final nextRedo = state.redoStack.sublist(0, state.redoStack.length - 1);
    final nextUndo = [...state.undoStack, state.palette];
    emit(
      state.copyWith(palette: next, undoStack: nextUndo, redoStack: nextRedo),
    );
  }

  List<List<StudioColor>> _pushUndo(
    List<List<StudioColor>> stack,
    List<StudioColor> snapshot,
  ) {
    final next = [...stack, snapshot];
    if (next.length > _maxHistory) {
      return next.sublist(next.length - _maxHistory);
    }
    return next;
  }
}
