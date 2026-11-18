import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoSlidingSegmentedControl;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hsluv/hsluvcolor.dart';
import 'package:chroma_folio/blocs/studio_cubit.dart';
import 'package:chroma_folio/main.dart';
import 'package:chroma_folio/models/accessibility_utils.dart';
import 'package:chroma_folio/models/color_spaces.dart';
import 'package:chroma_folio/screens/picker_screen.dart';
import 'package:chroma_folio/widgets/channel_reel.dart';
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

    test('palettes can change size and keep a valid selection', () {
      final cubit = StudioCubit();
      expect(cubit.state.palette, hasLength(8));
      cubit.selectSlot(7);

      final bubblegum = studioStarterPalettes.indexWhere(
        (starter) => starter.name == 'Bubblegum',
      );
      cubit.applyColorsToPalette(studioStarterPaletteAt(bubblegum));
      expect(cubit.state.palette, hasLength(4));
      expect(cubit.state.selectedIndex, 3);

      cubit.shufflePalette();
      expect(cubit.state.palette, hasLength(4));

      cubit.undo();
      cubit.undo();
      expect(cubit.state.palette, hasLength(8));
      cubit.selectSlot(6);
      cubit.redo();
      expect(cubit.state.palette, hasLength(4));
      expect(cubit.state.selectedIndex, 3);
      cubit.close();
    });
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

    Finder tab(String label) => find
        .ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.inMutuallyExclusiveGroup == true,
          ),
        )
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
      expect(after, closeTo(during, 0.01), reason: 'rests where it is let go');
      expect(isOnBand(after, 5), isFalse, reason: 'no snapping to a band');
      expect(cubit.state.canUndo, isTrue);

      cubit.undo();
      expect(cubit.state.activeColor.hsluv.lightness, before);
    });

    testWidgets('a reel follows the finger band for band', (tester) async {
      final cubit = await pumpStudio(tester);
      final strip = tester.getRect(reelStrip(0));
      final bandLength = math.min(36.0, strip.height / 7);
      final before = cubit.state.activeColor.hsluv.hue;

      final gesture = await tester.startGesture(strip.center);
      await gesture.moveBy(Offset(0, -bandLength));
      await tester.pump();

      final travelled = cubit.state.activeColor.hsluv.hue - before;
      expect(travelled, closeTo(15, 0.01));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('pulling a reel past its end bumps once and pushes the lens', (
      tester,
    ) async {
      final haptics = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final cubit = await pumpStudio(tester);
      final lens = find
          .descendant(of: reel(2), matching: find.byType(AnimatedContainer))
          .first;
      final resting = tester.getCenter(lens);

      final gesture = await tester.startGesture(tester.getCenter(reelStrip(2)));
      for (var i = 0; i < 60; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      expect(cubit.state.activeColor.hsluv.lightness, closeTo(100, 0.01));
      final bump = haptics.indexOf('HapticFeedbackType.mediumImpact');
      expect(bump, isNot(-1));
      expect(
        haptics.skip(bump + 1),
        isEmpty,
        reason: 'the pinned value should not keep clicking',
      );
      final pushed = tester.getCenter(lens) - resting;
      expect(pushed.dx, closeTo(0, 1e-6));
      expect(pushed.dy, inExclusiveRange(4, 9.01));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getCenter(lens), offsetMoreOrLessEquals(resting));
    });

    testWidgets('flinging the hue reel keeps it spinning', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      final before = cubit.state.activeColor.hsluv.hue;

      await tester.fling(reelStrip(0), const Offset(0, -120), 1600);
      await tester.pumpAndSettle();

      final after = cubit.state.activeColor.hsluv.hue;
      const dragOnly = 120 / 32 * 15;
      expect((after - before).abs(), greaterThan(dragOnly));
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

      await tester.tap(find.text('Spectrum'));
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
    });

    testWidgets('dragging a spectrum strip picks from that strip', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);

      await tester.tap(find.text('Spectrum'));
      await tester.pumpAndSettle();

      final before = cubit.state.activeColor.hsluv;
      await tester.dragFrom(
        tester.getCenter(find.text('HSL').last) + const Offset(0, 60),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();

      final picked = cubit.state.activeColor;
      expect(cubit.state.activeSpace, ColorSpaceMode.hsl);
      expect(picked.hsl.hue, isNot(closeTo(before.hue, 0.01)));
      expect(picked.hsl.saturation * 100, closeTo(before.saturation, 0.01));
      expect(picked.hsl.lightness * 100, closeTo(before.lightness, 0.01));
    });

    Future<int> solidFrame(WidgetTester tester, Finder viewport) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(viewport);
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 0.25);
        try {
          final data = (await image.toByteData())!;
          return Object.hashAll(data.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }))!;
    }

    testWidgets('the solid turns sideways and lifts its slice', (tester) async {
      final cubit = await pumpStudio(tester);

      await tester.tap(find.text('Solid'));
      await tester.pumpAndSettle();
      final solid = find.byKey(const ValueKey<String>('gamut_solid_canvas'));
      final viewport = find.byKey(const ValueKey('gamut_solid_viewport'));
      final edge = tester.getTopLeft(solid) + const Offset(24, 24);
      final rotating = find.textContaining(RegExp(r'^Rotation \d{1,3}°$'));
      final lightness = find.textContaining(RegExp(r'^Lightness \d+$'));
      final before = cubit.state.activeColor;
      final original = await solidFrame(tester, viewport);
      expect(rotating, findsNothing);
      expect(lightness, findsNothing);

      final turn = await tester.startGesture(edge);
      await turn.moveBy(const Offset(140, 0));
      await tester.pump();
      expect(rotating, findsOneWidget);
      expect(lightness, findsNothing);
      expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
      final firstAngle = tester.widget<Text>(rotating).data;
      final readoutWidth = tester.getSize(rotating).width;
      await turn.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(tester.widget<Text>(rotating).data, isNot(firstAngle));
      expect(tester.getSize(rotating).width, readoutWidth);
      await turn.up();
      await tester.pumpAndSettle();
      expect(rotating, findsNothing);
      expect(await solidFrame(tester, viewport), isNot(original));
      expect(cubit.state.activeColor, before, reason: 'turning only looks');

      final lift = await tester.startGesture(edge);
      await lift.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(lightness, findsOneWidget);
      expect(rotating, findsNothing);
      expect(
        find.text(
          'Lightness ${cubit.state.activeColor.hsluv.lightness.round()}',
        ),
        findsOneWidget,
      );
      await lift.up();
      await tester.pumpAndSettle();
      expect(lightness, findsNothing);
      final lowered = cubit.state.activeColor.hsluv;
      expect(lowered.lightness, lessThan(before.hsluv.lightness));
      expect(lowered.hue, closeTo(before.hsluv.hue, 0.01));

      await tester.tapAt(tester.getCenter(solid));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(cubit.state.activeColor.hsluv.lightness, lowered.lightness);
    });

    testWidgets('a solid color drag follows the rim outside the slice', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      final before = StudioColor.fromSpace(
        ColorSpaceMode.hsluv,
        hue: 90,
        saturationPct: 50,
        lightnessPct: 50,
      );
      cubit.setActiveColor(before, recordHistory: false);
      await tester.tap(find.text('Solid'));
      await tester.pumpAndSettle();
      final solid = find.byKey(const ValueKey<String>('gamut_solid_canvas'));
      final center = tester.getCenter(solid);
      final outsideX = tester.getSize(solid).width / 2 + 20;

      final drag = await tester.startGesture(center + const Offset(0, 20));
      await drag.moveTo(center + const Offset(40, 0));
      await drag.moveTo(center + Offset(outsideX, 0));
      await tester.pump();
      final right = cubit.state.activeColor.hsluv;
      expect(right.saturation, closeTo(100, 0.01));
      expect(isOnBand(right.hue, 360), isTrue);

      await drag.moveTo(center - Offset(outsideX, 0));
      await tester.pump();
      final left = cubit.state.activeColor.hsluv;
      expect(left.saturation, closeTo(100, 0.01));
      expect(left.hue, closeTo(180, 0.01));
      expect(left.lightness, closeTo(50, 0.01));

      await drag.moveTo(center - const Offset(40, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        cubit.state.activeColor.hsluv.saturation,
        inExclusiveRange(0, 100),
      );

      cubit.undo();
      expect(cubit.state.activeColor, before);
      await tester.pumpAndSettle();
    });

    testWidgets('the solid retargets its morph and zooms with the wheel', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      await tester.tap(find.text('Solid'));
      await tester.pumpAndSettle();
      final viewport = find.byKey(const ValueKey('gamut_solid_viewport'));
      final before = cubit.state.activeColor;

      final original = await solidFrame(tester, viewport);
      await tester.tap(find.text('OKLCH'));
      await tester.pump();
      expect(await solidFrame(tester, viewport), original);
      await tester.pump(const Duration(milliseconds: 120));
      final halfway = await solidFrame(tester, viewport);
      expect(halfway, isNot(original));

      await tester.tap(find.text('HSL'));
      await tester.pump();
      expect(await solidFrame(tester, viewport), halfway);
      await tester.pumpAndSettle();
      final finished = await solidFrame(tester, viewport);
      expect(finished, isNot(halfway));

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(viewport),
          scrollDelta: const Offset(0, -180),
        ),
      );
      await tester.pump();
      expect(await solidFrame(tester, viewport), isNot(finished));
      expect(cubit.state.activeColor, before);
      expect(cubit.state.canUndo, isFalse);
    });

    testWidgets(
      'pinching the solid and easing back to reset only move the camera',
      (tester) async {
        final cubit = await pumpStudio(tester);
        await tester.tap(find.text('Solid'));
        await tester.pumpAndSettle();
        final viewport = find.byKey(const ValueKey('gamut_solid_viewport'));
        final before = cubit.state.activeColor;
        final original = await solidFrame(tester, viewport);
        final center = tester.getCenter(viewport);
        final reset = find.widgetWithIcon(
          IconButton,
          Icons.fit_screen_outlined,
        );
        bool canReset() => tester.widget<IconButton>(reset).onPressed != null;
        expect(canReset(), isFalse);

        final left = await tester.startGesture(center - const Offset(35, 0));
        final right = await tester.startGesture(center + const Offset(35, 0));
        await left.moveBy(const Offset(-35, 0));
        await right.moveBy(const Offset(35, 0));
        await tester.pump();
        final zoomed = await solidFrame(tester, viewport);
        expect(zoomed, isNot(original));

        await left.up();
        await right.moveBy(const Offset(0, 68));
        await right.up();
        await tester.pumpAndSettle();
        expect(await solidFrame(tester, viewport), zoomed);

        final edge = tester.getTopLeft(viewport) + const Offset(24, 24);
        await tester.dragFrom(edge, const Offset(140, 0));
        await tester.pumpAndSettle();
        final turned = await solidFrame(tester, viewport);
        expect(turned, isNot(zoomed));
        expect(canReset(), isTrue);

        expect(tester.getSize(reset).shortestSide, greaterThanOrEqualTo(44));
        final resetIcon = tester.element(
          find.byIcon(Icons.fit_screen_outlined),
        );
        final resetFocus = Focus.of(resetIcon)..requestFocus();
        await tester.pump();
        expect(resetFocus.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(await solidFrame(tester, viewport), turned);
        await tester.pump(const Duration(milliseconds: 130));
        expect(
          await solidFrame(tester, viewport),
          isNot(anyOf(turned, original)),
        );
        await tester.pumpAndSettle();
        expect(await solidFrame(tester, viewport), original);
        expect(canReset(), isFalse);
        expect(cubit.state.activeColor, before);
        expect(cubit.state.canUndo, isFalse);
      },
    );

    testWidgets(
      'the solid bottom reels adjust hue and saturation independently',
      (tester) async {
        final cubit = await pumpStudio(tester);
        await tester.tap(find.text('Solid'));
        await tester.pumpAndSettle();

        final before = cubit.state.activeColor;
        final reel = tester.getRect(find.byKey(const ValueKey('solid_1_reel')));
        await tester.tapAt(reel.centerLeft + Offset(reel.width * 0.3, 0));
        await tester.pumpAndSettle();

        final after = cubit.state.activeColor.hsluv;
        expect(after.saturation, lessThan(before.hsluv.saturation));
        expect(after.hue, closeTo(before.hsluv.hue, 0.01));
        expect(after.lightness, before.hsluv.lightness);
        cubit.undo();
        expect(cubit.state.activeColor, before);
        await tester.pumpAndSettle();

        final hueReel = tester.getRect(
          find.byKey(const ValueKey('solid_0_reel')),
        );
        expect(hueReel.width, closeTo(reel.width, 0.01));
        await tester.tapAt(
          hueReel.centerRight - Offset(hueReel.width * 0.2, 0),
        );
        await tester.pumpAndSettle();
        final huePick = cubit.state.activeColor.hsluv;
        expect(huePick.hue, isNot(before.hsluv.hue));
        expect(huePick.saturation, before.hsluv.saturation);
        expect(huePick.lightness, before.hsluv.lightness);
      },
    );

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

      await tester.tap(find.text('Palette'));
      await tester.pumpAndSettle();
      expect(find.text('50'), findsOneWidget);
      expect(find.text('950'), findsOneWidget);
      expect(find.text('Copy palette'), findsNothing);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      for (final label in [
        'Hex',
        'CSS · OKLCH',
        'CSS · Display P3',
        'Flutter',
        'Tailwind',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      final before = cubit.state.palette.map((c) => c.hex).toList();
      await tester.tap(find.text('Triadic'));
      await tester.pumpAndSettle();
      expect(cubit.state.palette.map((c) => c.hex).toList(), isNot(before));
    });

    Rect scaleStep(WidgetTester tester, String token) => tester.getRect(
      find
          .ancestor(of: find.text(token), matching: find.byType(DecoratedBox))
          .first,
    );

    testWidgets('a tapped scale step stands apart from its neighbours', (
      tester,
    ) async {
      await pumpStudio(tester);
      await tester.tap(find.text('Palette'));
      await tester.pumpAndSettle();
      expect(
        scaleStep(tester, '900').left,
        closeTo(scaleStep(tester, '800').right, 0.01),
      );

      await tester.tap(find.text('900'));
      await tester.pumpAndSettle();
      expect(
        scaleStep(tester, '900').left,
        greaterThan(scaleStep(tester, '800').right + 3),
      );
      expect(
        scaleStep(tester, '950').left,
        greaterThan(scaleStep(tester, '900').right + 3),
      );
    });

    testWidgets('sliding across the scale scrubs as one undo step', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      await tester.tap(find.text('Palette'));
      await tester.pumpAndSettle();
      final before = cubit.state.palette;
      final undoDepth = cubit.state.undoStack.length;

      final from = tester.getCenter(find.text('100'));
      final to = tester.getCenter(find.text('950'));
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 12; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 12)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(cubit.state.undoStack, hasLength(undoDepth + 1));
      expect(
        scaleStep(tester, '950').left,
        greaterThan(scaleStep(tester, '900').right + 3),
      );
      cubit.undo();
      expect(cubit.state.palette, before);
    });

    testWidgets('a starter palette can be previewed, applied, and undone', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      final before = cubit.state.palette;
      await tester.tap(find.text('Palette'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Starter palettes'));
      await tester.pumpAndSettle();
      for (final preset in studioStarterPalettes) {
        expect(find.text(preset.name), findsOneWidget);
      }
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      cubit.selectSlot(5);
      await tester.tap(find.text('Neon Arcade'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(cubit.state.palette, studioStarterPaletteAt(2));
      expect(cubit.state.selectedIndex, 0);
      await tester.tap(find.byIcon(Icons.undo_rounded));
      await tester.pumpAndSettle();
      expect(cubit.state.palette, before);

      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Starter palettes'));
      await tester.tap(find.text('Starter palettes'));
      await tester.pumpAndSettle();
      final lastPreset = find.text(studioStarterPalettes.last.name);
      await tester.ensureVisible(lastPreset);
      await tester.tap(lastPreset);
      await tester.pumpAndSettle();
      expect(
        cubit.state.palette,
        studioStarterPaletteAt(studioStarterPalettes.length - 1),
      );
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
      await tester.tap(find.text('Palette'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSS · Display P3'));
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
      final originalColor = cubit.state.activeColor.color;
      final specimen = find.byKey(const ValueKey('specimen_background'));
      Color? displayedColor() =>
          (tester.widget<Container>(specimen).decoration as BoxDecoration)
              .color;

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await tester.pump();
      expect(displayedColor(), originalColor);
      await tester.pump(const Duration(milliseconds: 70));
      expect(displayedColor(), isNot(originalColor));
      expect(displayedColor(), isNot(cubit.state.activeColor.color));
      await tester.pumpAndSettle();
      expect(displayedColor(), cubit.state.activeColor.color);
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

    testWidgets('studio tabs size to their labels at a shared height', (
      tester,
    ) async {
      await pumpStudio(tester);
      final selectors = find.byWidgetPredicate(
        (widget) => widget is CupertinoSlidingSegmentedControl,
      );

      for (final width in [1440.0, 1280.0, 900.0, 390.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        final lens = tester.getRect(selectors.at(0));
        final space = tester.getRect(selectors.at(1));
        if (width == 390) {
          expect(lens.width, closeTo(width - 28, 0.01));
          expect(space.width, closeTo(lens.width, 0.01));
        } else {
          expect(lens.right, lessThan(space.right), reason: 'width $width');
        }
        expect(
          tester.getSize(tab('Spectrum')).width,
          greaterThan(tester.getSize(tab('Reels')).width),
        );
        expect(
          lens.height,
          closeTo(space.height, 0.01),
          reason: 'width $width',
        );
        expect(lens.height, width == 390 ? 48 : 44, reason: 'width $width');
      }
    });

    testWidgets('switching lenses replaces the workspace on the next frame', (
      tester,
    ) async {
      await pumpStudio(tester);
      expect(find.byType(PickerScreen), findsOneWidget);
      await tester.tap(find.text('Solid'));
      await tester.pump();
      expect(find.byType(PickerScreen), findsNothing);
      expect(find.byKey(const ValueKey('gamut_solid_canvas')), findsOneWidget);
    });

    testWidgets('keyboard tabs activate without shuffling the palette', (
      tester,
    ) async {
      final cubit = await pumpStudio(tester);
      final revision = cubit.state.shuffleRevision;
      bool tabHasFocus(String label) {
        final focused = FocusManager.instance.primaryFocus?.context;
        final tabFocus = find
            .ancestor(of: tab(label), matching: find.byType(Focus))
            .first;
        return tabFocus.evaluate().single == focused;
      }

      for (var i = 0; i < 20 && !tabHasFocus('Reels'); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(tabHasFocus('Reels'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tabHasFocus('Solid'), isTrue);
      expect(find.byKey(const ValueKey('gamut_solid_canvas')), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(tabHasFocus('Spectrum'), isTrue);
      expect(find.byKey(const ValueKey('gamut_solid_canvas')), findsNothing);
      expect(cubit.state.shuffleRevision, revision);
    });

    testWidgets('the compact layout fits a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(StudioApp(cubit: StudioCubit()));
      await tester.pumpAndSettle();
      for (final lens in ['Spectrum', 'Solid', 'Palette', 'Reels']) {
        final target = tab(lens);
        final size = tester.getSize(target);
        expect(size.height, greaterThanOrEqualTo(44), reason: lens);
        expect(size.width, greaterThanOrEqualTo(44), reason: lens);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: lens);
      }
      expect(find.byType(ChannelReel), findsNWidgets(3));

      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();
      await tester.ensureVisible(tab('Palette'));
      await tester.tap(tab('Palette'));
      await tester.pumpAndSettle();
      final lastHarmony = find.text('Split complementary').hitTestable();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(lastHarmony, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
