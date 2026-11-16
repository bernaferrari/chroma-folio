#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf build/readme_frames
flutter test tool/render_readme_assets.dart

src="build/readme_frames/oklch_vs_hsl_solid"
scaled="build/readme_frames/oklch_vs_hsl_solid_960"
mkdir -p "$scaled"
ffmpeg -y -loglevel error -i "$src/frame_%04d.png" -vf "scale=960:-1:flags=lanczos" "$scaled/frame_%04d.png"
img2webp -min_size -loop 0 -d 33 -lossy -q 84 -m 4 "$scaled"/frame_*.png -o "docs/screenshots/oklch_vs_hsl_solid.webp"

rm -rf build/readme_frames
ls -lh docs/screenshots/oklch_vs_hsl_solid.webp
