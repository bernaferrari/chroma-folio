#!/usr/bin/env bash
# Renders build/showreel/chroma_folio_showreel.mp4. Needs flutter and ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/../.."

fonts=build/showreel_fonts
mkdir -p "$fonts"
base=https://github.com/google/fonts/raw/main/ofl
fetch() { [[ -f "$fonts/$1" ]] || curl -fsSL "$2" -o "$fonts/$1"; }
fetch InstrumentSerif-Regular.ttf "$base/instrumentserif/InstrumentSerif-Regular.ttf"
fetch InstrumentSerif-Italic.ttf "$base/instrumentserif/InstrumentSerif-Italic.ttf"
fetch JetBrainsMono.ttf "$base/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"
fetch PlusJakartaSans.ttf "$base/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf"

flutter_root="$(dirname "$(dirname "$(command -v flutter)")")"
cp "$flutter_root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf" "$fonts/"

rm -rf build/showreel
flutter test tool/showreel/render_showreel.dart
echo "→ build/showreel/chroma_folio_showreel.mp4"
