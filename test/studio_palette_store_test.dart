import 'dart:async';

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
    expect(first.state.palette.map((color) => color.hex).toSet(), hasLength(8));
    expect(writes, 1);
    final reopened = await store.open();
    expect(reopened.state.palette, first.state.palette);
    expect(writes, 1);
    await reopened.close();

    first.selectSlot(3);
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
    expect(restored.state.selectedIndex, 3);
    expect(restored.state.palette, first.state.palette);
    expect(restored.state.activeColor, edited);
    expect(restored.state.canUndo, isFalse);
    expect(writes, 3);
    await restored.close();
  });
}
