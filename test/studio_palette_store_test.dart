import 'dart:async';
import 'dart:convert';

import 'package:chroma_folio/models/color_spaces.dart';
import 'package:chroma_folio/studio_palette_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the studio restores the first palette and subsequent edits', () async {
    String? cache;
    var writes = 0;
    final editsSaved = Completer<void>();
    final store = StudioPaletteStore(
      read: () async => cache,
      write: (snapshot) async {
        cache = snapshot;
        if (++writes == 3) editsSaved.complete();
      },
    );

    final first = await store.open();
    expect(
      List.generate(studioStarterPalettes.length, studioStarterPaletteAt),
      contains(equals(first.state.palette)),
    );
    expect(first.state.selectedIndex, 0);
    expect(writes, 1);
    final reopened = await store.open();
    expect(reopened.state.palette, first.state.palette);
    expect(writes, 1);
    await reopened.close();

    final lastSlot = first.state.palette.length - 1;
    first.selectSlot(lastSlot);
    // Black has no visible chroma, but the reel must remember this setting.
    final edited = StudioColor.fromSpace(
      ColorSpaceMode.oklch,
      hue: 42.5,
      saturationPct: 73.25,
      lightnessPct: 0,
    );
    first.setActiveColor(edited);
    await editsSaved.future;
    await first.close();

    final restored = await store.open();
    expect(restored.state.selectedIndex, lastSlot);
    expect(restored.state.palette, first.state.palette);
    expect(restored.state.activeColor, edited);
    expect(restored.state.canUndo, isFalse);
    expect(writes, 3);
    await restored.close();
  });

  test('old presets update unless their colors were edited', () async {
    String? cache;
    var writes = 0;
    final oldPresetSaved = Completer<void>();
    final store = StudioPaletteStore(
      read: () async => cache,
      write: (snapshot) async {
        cache = snapshot;
        if (++writes == 3) oldPresetSaved.complete();
      },
    );
    final first = await store.open();
    final oldPreset = [
      for (final hex
          in 'CD5E89 DD789E E6A3B4 F4CBD0 B84FA1 945877 FFE8DB 4B2E40'.split(
            ' ',
          ))
        StudioColor.fromColor(parseColorInput('#$hex')!),
    ];
    first.applyColorsToPalette(oldPreset);
    first.selectSlot(2);
    await oldPresetSaved.future;
    await first.close();
    final originalSnapshot = cache!;

    final updated = await store.open();
    final bubblegum = studioStarterPalettes.indexWhere(
      (starter) => starter.name == 'Bubblegum',
    );
    expect(updated.state.palette, studioStarterPaletteAt(bubblegum));
    expect(updated.state.selectedIndex, 0);
    expect(writes, 4);
    await updated.close();

    // An edit can change the underlying coordinates without changing the hex.
    final edited = jsonDecode(originalSnapshot) as Map<String, dynamic>;
    edited['colors'][0][2][3] = 24;
    cache = jsonEncode(edited);
    final restored = await store.open();
    expect(restored.state.palette.first.hex, oldPreset.first.hex);
    expect(restored.state.palette.first.oklch.relativePercent, 24);
    expect(writes, 4);
    await restored.close();
  });

  test('a smaller palette is restored at its own size', () async {
    String? cache;
    var writes = 0;
    final saved = Completer<void>();
    final store = StudioPaletteStore(
      read: () async => cache,
      write: (snapshot) async {
        cache = snapshot;
        if (++writes == 2) saved.complete();
      },
    );
    final first = await store.open();
    final signal = studioStarterPalettes.indexWhere(
      (starter) => starter.name == 'Signal',
    );
    first.applyColorsToPalette(studioStarterPaletteAt(signal));
    await saved.future;
    await first.close();

    final restored = await store.open();
    expect(restored.state.palette, studioStarterPaletteAt(signal));
    await restored.close();
  });
}
