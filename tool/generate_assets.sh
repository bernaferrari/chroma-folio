#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fonts="build/readme_fonts"
mkdir -p "$fonts"
fetch_font() {
  [ -f "$fonts/$1" ] || curl -fsSL "https://github.com/google/fonts/raw/main/ofl/$2" -o "$fonts/$1"
}
fetch_font InstrumentSerif-Regular.ttf "instrumentserif/InstrumentSerif-Regular.ttf"
fetch_font JetBrainsMono.ttf "jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"

rm -rf build/readme_frames
flutter test tool/render_readme_assets.dart

src="build/readme_frames/oklch_vs_hsl_solid"
scaled="build/readme_frames/oklch_vs_hsl_solid_960"
mkdir -p "$scaled"
ffmpeg -y -loglevel error -i "$src/frame_%04d.png" -vf "scale=960:-1:flags=lanczos" -pix_fmt rgba "$scaled/frame_%04d.png"
img2webp -kmin 3 -kmax 4 -loop 0 -d 33 -lossy -q 84 -m 4 "$scaled"/frame_*.png -o "docs/screenshots/oklch_vs_hsl_solid.webp"

rm -rf build/readme_frames
ls -lh docs/screenshots/oklch_vs_hsl_solid.webp
