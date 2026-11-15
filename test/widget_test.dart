import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hsluv/hsluvcolor.dart';
import 'package:chroma_folio/blocs/studio_cubit.dart';
import 'package:chroma_folio/main.dart';
import 'package:chroma_folio/models/accessibility_utils.dart';
import 'package:chroma_folio/models/color_spaces.dart';
import 'package:chroma_folio/widgets/channel_reel.dart';
import 'package:chroma_folio/widgets/studio_theme.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Color math & StudioCubit unit tests', () {
    test('OklchColor round-trips sRGB colors accurately', () {
      const samples = [
        Color(0xFF00A8E8),
        Color(0xFFFF5A5F),
        Color(0xFF10B981),
        Color(0xFFF59E0B),
        Color(0xFF8B5CF6),
        Color(0xFF222222),
        Color(0xFFFAFAFA),
      ];

      for (final sample in samples) {
        final oklch = OklchColor.fromColor(sample);
        final back = oklch.toColor();
        final dr = ((sample.r - back.r) * 255).abs();
        final dg = ((sample.g - back.g) * 255).abs();
        final db = ((sample.b - back.b) * 255).abs();
        expect(dr, lessThanOrEqualTo(2));
        expect(dg, lessThanOrEqualTo(2));
        expect(db, lessThanOrEqualTo(2));
      }
    });

    test('solveHsluvForContrast finds AA and AAA compliant lightness', () {
      const lightYellow = HSLuvColor.fromHSL(75, 95, 88);
      final aa = solveHsluvForContrast(lightYellow, Colors.white, 4.5);
      final aaa = solveHsluvForContrast(lightYellow, Colors.white, 7.0);

      expect(aa, isNotNull);
      expect(
        wcagContrastRatio(aa!.toColor(), Colors.white),
        greaterThanOrEqualTo(4.5),
      );
      expect(aaa, isNotNull);
      expect(
        wcagContrastRatio(aaa!.toColor(), Colors.white),
        greaterThanOrEqualTo(7.0),
      );
    });

    test(
      'StudioCubit scrub lifecycle updates live and folds into single undo',
      () {
        final cubit = StudioCubit();
        final initialHex = cubit.state.activeColor.hex;

        cubit.beginScrub();
        cubit.scrubChannel(0, 120.0);
        final midHex = cubit.state.activeColor.hex;
        expect(midHex, isNot(equals(initialHex)));

        cubit.scrubChannel(0, 240.0);
        final secondHex = cubit.state.activeColor.hex;
        expect(secondHex, isNot(equals(midHex)));

        cubit.endScrub();
        expect(cubit.state.canUndo, isTrue);

        cubit.undo();
        expect(cubit.state.activeColor.hex, equals(initialHex));
        expect(cubit.state.canRedo, isTrue);

        cubit.redo();
        expect(cubit.state.activeColor.hex, equals(secondHex));
        cubit.close();
      },
    );
  });

  group('StudioApp widget tests', () {
    void configureViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<StudioCubit> pumpStudio(WidgetTester tester) async {
      configureViewport(tester);
      final cubit = StudioCubit();
      await tester.pumpWidget(StudioApp(cubit: cubit));
      await tester.pumpAndSettle();
      return cubit;
    }

    Finder reel(int channel) => find.byType(ChannelReel).at(channel);

    Finder reelStrip(int channel) => find
        .descendant(of: reel(channel), matching: find.byType(CustomPaint))
        .first;

    bool isOnBand(double value, double step) {
      final offset = value % step;
      return offset < 0.01 || step - offset < 0.01;
    }

    testWidgets('dragging a reel changes the colour while the finger is down', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      final before = cubit.state.activeColor.hsluv.lightness;

      final gesture = await tester.startGesture(tester.getCenter(reelStrip(2)));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 70));
      await tester.pump();

      final during = cubit.state.activeColor.hsluv.lightness;
      expect(during, greaterThan(before), reason: 'lighter bands sit above');
      expect(find.text(cubit.state.activeColor.hex), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      final after = cubit.state.activeColor.hsluv.lightness;
      expect(isOnBand(after, 5), isTrue, reason: 'rested at $after');
      expect(cubit.state.canUndo, isTrue);

      cubit.undo();
      expect(cubit.state.activeColor.hsluv.lightness, before);
    });

    testWidgets('a reel follows the finger band for band', (tester) async {
      final cubit = await pumpStudio(tester);
      final strip = tester.getRect(reelStrip(0));
      final bandLength = (strip.height / 13).clamp(32.0, 56.0);
      final before = cubit.state.activeColor.hsluv.hue;

      final gesture = await tester.startGesture(strip.center);
      await gesture.moveBy(Offset(0, -bandLength));
      await tester.pump();

      final travelled = cubit.state.activeColor.hsluv.hue - before;
      expect(travelled, closeTo(15, 0.01));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('flinging the hue reel keeps it spinning and lands on a band', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      final before = cubit.state.activeColor.hsluv.hue;

      await tester.fling(reelStrip(0), const Offset(0, -120), 1600);
      await tester.pumpAndSettle();

      final after = cubit.state.activeColor.hsluv.hue;
      const dragOnly = 120 / 32 * 15;
      expect((after - before).abs(), greaterThan(dragOnly));
      expect(isOnBand(after, 15), isTrue, reason: 'rested at $after');
    });

    testWidgets('a saturation fling stops at the end of the range', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);

      await tester.fling(reelStrip(1), const Offset(0, 200), 4000);
      await tester.pumpAndSettle();

      expect(cubit.state.activeColor.hsluv.saturation, 100);
    });

    testWidgets('tapping a band brings it into the lens', (tester) async {
      final cubit = await pumpStudio(tester);
      final before = cubit.state.activeColor.hsluv.lightness;
      final strip = tester.getRect(reelStrip(2));

      await tester.tapAt(strip.center - Offset(0, strip.height * 0.3));
      await tester.pumpAndSettle();

      final after = cubit.state.activeColor.hsluv.lightness;
      expect(after, greaterThan(before + 10));
      expect(isOnBand(after, 5), isTrue, reason: 'rested at $after');
    });

    testWidgets('typing a value sets the channel exactly', (tester) async {
      final cubit = await pumpStudio(tester);

      await tester.tap(
        find.descendant(of: reel(0), matching: find.text('Hue')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();

      expect(cubit.state.activeColor.hsluv.hue, 123);
    });

    testWidgets('switching colour space renames the reels', (tester) async {
      final cubit = await pumpStudio(tester);

      await tester.tap(find.text('OKLCH'));
      await tester.pumpAndSettle();
      expect(cubit.state.activeSpace, ColorSpaceMode.oklch);
      expect(find.text('Chroma'), findsOneWidget);

      await tester.tap(find.text('HCT'));
      await tester.pumpAndSettle();
      expect(cubit.state.activeSpace, ColorSpaceMode.hct);
      expect(
        find.descendant(of: reel(2), matching: find.text('Tone')),
        findsOneWidget,
      );
    });

    testWidgets('spectrum spins every space together', (tester) async {
      final cubit = await pumpStudio(tester);

      await tester.tap(find.byTooltip('Spectrum'));
      await tester.pumpAndSettle();
      expect(find.text('HSL'), findsNWidgets(2));

      final before = cubit.state.activeColor.hsluv.hue;
      await tester.fling(
        find.byKey(const ValueKey<String>('spectrum_gesture_canvas')),
        const Offset(-180, 0),
        900,
      );
      await tester.pumpAndSettle();

      final after = cubit.state.activeColor.hsluv.hue;
      expect(after, isNot(before));
      expect(isOnBand(after, 20), isTrue, reason: 'rested at $after');
    });

    testWidgets('dragging a spectrum strip picks from that strip', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);

      await tester.tap(find.byTooltip('Spectrum'));
      await tester.pumpAndSettle();

      final before = cubit.state.activeColor.hsluv;
      await tester.dragFrom(
        tester.getCenter(find.text('HSL').last) + const Offset(0, 60),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();

      final picked = cubit.state.activeColor;
      expect(cubit.state.activeSpace, ColorSpaceMode.hsl);
      expect(isOnBand(picked.hsl.hue, 20), isTrue, reason: '${picked.hsl.hue}');
      expect(picked.hsl.saturation * 100, closeTo(before.saturation, 0.01));
      expect(picked.hsl.lightness * 100, closeTo(before.lightness, 0.01));
    });

    testWidgets('the solid turns sideways and lifts its slice', (tester) async {
      final cubit = await pumpStudio(tester);

      await tester.tap(find.byTooltip('Solid'));
      await tester.pumpAndSettle();
      final solid = find.byKey(const ValueKey<String>('gamut_solid_canvas'));
      final edge = tester.getTopLeft(solid) + const Offset(24, 24);
      final before = cubit.state.activeColor;

      await tester.dragFrom(edge, const Offset(140, 0));
      await tester.pumpAndSettle();
      expect(cubit.state.activeColor, before, reason: 'turning only looks');

      await tester.dragFrom(edge, const Offset(0, 80));
      await tester.pumpAndSettle();
      final lowered = cubit.state.activeColor.hsluv;
      expect(lowered.lightness, lessThan(before.hsluv.lightness));
      expect(lowered.hue, closeTo(before.hsluv.hue, 0.01));

      await tester.tapAt(tester.getCenter(solid));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(cubit.state.activeColor.hsluv.lightness, lowered.lightness);
    });

    testWidgets('the solid slider changes only saturation and can be undone', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      await tester.tap(find.byTooltip('Solid'));
      await tester.pumpAndSettle();

      final before = cubit.state.activeColor;
      final slider = tester.getRect(find.byType(Slider));
      await tester.tapAt(slider.centerLeft + Offset(slider.width * 0.3, 0));
      await tester.pumpAndSettle();

      final after = cubit.state.activeColor.hsluv;
      expect(after.saturation, lessThan(before.hsluv.saturation));
      expect(after.hue, closeTo(before.hsluv.hue, 0.01));
      expect(after.lightness, before.hsluv.lightness);
      cubit.undo();
      expect(cubit.state.activeColor, before);
    });

    test('chroma survives a trip to full lightness', () {
      for (final space in [ColorSpaceMode.oklch, ColorSpaceMode.hct]) {
        final start = StudioColor.fromSpace(
          space,
          hue: 250,
          saturationPct: 80,
          lightnessPct: 60,
        );
        final white = start.withChannelValue(space, 2, 100);
        expect(white.channelsFor(space)[1].value, 80, reason: '$space');
        expect(white.channelsFor(space)[1].max, 100, reason: '$space');
        expect(white.withChannelValue(space, 2, 60).color, start.color);
      }
    });

    testWidgets('a harmony fills the palette', (tester) async {
      final cubit = await pumpStudio(tester);

      await tester.tap(find.byTooltip('Palette'));
      await tester.pumpAndSettle();
      expect(find.text('50'), findsOneWidget);
      expect(find.text('950'), findsOneWidget);
      for (final label in ['Tailwind', 'Hex', 'CSS', 'Flutter']) {
        expect(find.text(label), findsOneWidget);
      }

      final before = cubit.state.palette.map((c) => c.hex).toList();
      await tester.tap(find.text('Triadic'));
      await tester.pumpAndSettle();
      expect(cubit.state.palette.map((c) => c.hex).toList(), isNot(before));
    });

    testWidgets('CSS copy emits Display P3 values for the palette', (
      tester,
    ) async {
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final cubit = await pumpStudio(tester);
      await tester.tap(find.byTooltip('Palette'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Display P3'));
      await tester.pumpAndSettle();

      expect(
        RegExp(r'color\(display-p3 [\d.]+ [\d.]+ [\d.]+\)').allMatches(copied!),
        hasLength(cubit.state.palette.length),
      );
    });

    testWidgets('shuffle changes the palette and can be undone', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      final before = cubit.state.palette.map((c) => c.hex).toList();

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pumpAndSettle();
      final shuffled = cubit.state.palette.map((c) => c.hex).toList();
      expect(shuffled, isNot(before));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(cubit.state.palette.map((c) => c.hex).toList(), isNot(shuffled));

      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pumpAndSettle();
      expect(cubit.state.palette.map((c) => c.hex).toList(), before);
    });

    testWidgets('lens and space tabs have equal heights across layouts', (
      tester,
    ) async {
      await pumpStudio(tester);
      final selectors = find.byWidgetPredicate(
        (widget) => widget is StudioPillSelector,
      );

      for (final width in [1280.0, 900.0, 390.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        final lens = tester.getRect(selectors.at(0));
        final space = tester.getRect(selectors.at(1));
        expect(
          lens.height,
          closeTo(space.height, 0.01),
          reason: 'width $width',
        );
        expect(lens.height, closeTo(40, 0.01), reason: 'width $width');
      }
    });

    testWidgets('the compact layout fits a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(StudioApp(cubit: StudioCubit()));
      await tester.pumpAndSettle();
      for (final lens in ['Spectrum', 'Solid', 'Palette', 'Reels']) {
        await tester.tap(find.byTooltip(lens));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: lens);
      }
      expect(find.byType(ChannelReel), findsNWidgets(3));
    });
  });
}
