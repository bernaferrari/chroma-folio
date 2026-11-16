<p align="center">
  <img src="docs/brand/app-icon.svg" width="80" height="80" alt="Chroma Folio app icon">
</p>

<h1 align="center">Chroma Folio</h1>

<p align="center"><strong>See the shape of a colour space.</strong></p>

<p align="center">Turn and slice a 3D colour solid, spin the reels to find a colour, then build a palette around it.</p>

<p align="center"><a href="https://bernaferrari.github.io/chroma-folio/"><strong>Try Chroma Folio ↗</strong></a> · <a href="#turn-colour-around">Explore the 3D view</a> · <a href="#run-from-source">Run the app</a> · <a href="#build-a-palette">Copy a palette</a></p>

<p align="center">
  <img src="docs/screenshots/colour-in-motion.webp" width="100%" alt="Dragging the lightness reel raises the OKLCH cut from 55% to 85% and brightens the blue specimen.">
  <br><sub>Raise the cut from 55% to 85% lightness.</sub>
</p>

## Turn colour around

In **Solid**, hue wraps around the axis, lightness rises from black to white, and chroma extends outward. Drag sideways to spin the solid, drag vertically (or use the lightness reel) to move the cut, and tap anywhere on the cut face to pick a colour.

<p align="center">
  <img src="docs/screenshots/oklch_vs_hsl_solid.webp" width="100%" alt="3D solid comparison of OKLCH vs HSL sweeping lightness between 40% and 85%">
</p>

**OKLCH** traces the true sRGB gamut while keeping perceived lightness constant across every hue on the cut. **HSL** forces every hue into a uniform cylinder, making yellow and green look far brighter than blue at the same slice height.

## See what a colour space changes

Give four colour spaces the same hue, saturation, and lightness and see how differently they render it. In **Spectrum**, the strips move together so you can compare a single hue across HSLuv, OKLCH, HCT, and HSL. Drag a strip to pick from that space.

![Four synchronized hue strips in Spectrum, with HSLuv selected and the app in dark mode](docs/screenshots/spectrum.png)

## Build a palette

Start with one colour and try its tonal scale or a harmony. Each harmony previews the base colour, two accents, and five supporting shades. Tap one to fill your eight swatches, then drag along the swatch strip to pick a colour to edit.

![A blue tonal scale above four harmony previews with accents and supporting shades](docs/screenshots/palette.png)

Copy the tonal scale for Tailwind or export your palette as hex, Flutter code, or CSS variables. For CSS, choose **OKLCH** or **Display P3**. The P3 option expresses the current sRGB colours in Display P3 coordinates.

## Spin the reels

<p align="center">
  <img src="docs/screenshots/reels.webp" width="100%" alt="The hue reel spins through blue and purple as the specimen changes colour">
</p>

- **Flick a reel** to spin it, or tap a band to bring it under the lens.
- **Tap a channel value** to enter it exactly. Use the pencil next to the hex code to paste a hex, RGB, or OKLCH colour.
- **Tap the hex code** to copy the current colour. Press **Space** to shuffle the palette, then use **Undo** to go back.

## Run from source

Install Flutter and Chrome.

```sh
git clone https://github.com/bernaferrari/chroma-folio.git
cd chroma-folio
flutter pub get
flutter run -d chrome
```

Run `flutter analyze` and `flutter test` to check the project. To build the static web app in `build/web`, run `flutter build web --release`.

Chroma Folio grew out of the [hsluv-dart example](https://github.com/bernaferrari/hsluv-dart) and uses [HSLuv from pub.dev](https://pub.dev/packages/hsluv). [MIT license](LICENSE).
