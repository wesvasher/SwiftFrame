# SwiftFrame

A native macOS app for making stop motion animation.

Each SwiftFrame window is a capture window for one project. It shows the live camera with an onion skin of your last frames, keeps every frame in a filmstrip you can edit, and plays the animation back at full speed whenever you want to check it. You can have as many capture windows open as you like, each with its own camera.

> Status: early development.

## Features

- **Live capture**: pick any connected camera (built-in, USB, or Continuity Camera), mirror it if you like, and tap ⌘ to capture a frame.
- **Onion skin**: show up to five earlier frames over the live camera, fading with age, at the opacity you choose.
- **Real-time preview**: press Space to play and pause the animation at any rate from 1 to 60 fps, set in the inspector, looping or once, with the playing frame shown in the filmstrip. Drag the ends of the bar above the frames (or press I and O) to play or loop just part of it.
- **Frame editing**: click a frame to review it. Shift- or Command-click to select more, drag a frame by its handle to reorder, right-click for more, and duplicate, delete, reverse, or hold frames for longer (×2 for shooting "on twos"). Every edit can be undone.
- **Navigator**: when the timeline is zoomed in, a miniature of every frame above it outlines the part in view. Drag the box to move along the timeline, or click to jump.
- **Playhead**: a line across the filmstrip at the frame showing, gliding along while it plays and, with Habanero Mode on in Settings, a trail of fire streaming off the back. Drag it, or click or drag in the strip above the frames, to scrub; past the last frame is the live camera.
- **Back to capturing**: click the Capture tile at the right of the timeline, press → past the last frame, or press ⌘L.
- **Import pictures**: drop image files onto the filmstrip, or use Frame → Add Pictures.
- **Crop**: crop new frames to a shape from the middle of the camera's picture without squeezing it, such as a6600 1620×1080 (3:2, the shape of its photos, from a 1920×1080 HDMI signal), 4:3, square, vertical or scope.
- **Camera shutter**: capture from a Sony camera over HDMI and fire its shutter over Bluetooth with each frame, so the camera also saves a full-size photo (a6600 and other cameras that work with Sony's RMT-P1BT remote).
- **Export**: a movie in H.264, HEVC, or ProRes (422 Proxy, LT, 422, HQ, or 4444) as .mov or .mp4, an animated GIF, or an image sequence (PNG, JPEG, or TIFF), at full size or scaled to 4K, 1080p, 720p, 480p, or 360p.
- **Settings**: choose Auto, Light or Dark appearance, whether the viewer flashes when you capture, and Habanero Mode (fire off the playhead).
- **Projects**: each project is a `.swiftframe` package that holds its frames as JPEGs, so you can save, reopen, and keep working.

## Keyboard

| Key | Action |
| --- | --- |
| ⌘ (tap on its own) | Capture a frame |
| Space | Play / pause |
| ← → | Previous / next frame (→ past the end goes live) |
| I / O | Start / stop playback at the frame showing |
| ⌥X | Play all frames again (clear in and out) |
| ⌘L | Go live |
| ⌘D | Duplicate selected frames |
| ⌥← / ⌥→ | Move selected frames one place left / right (add ⇧ for 10) |
| ⌘] / ⌘[ | Hold longer / shorter |
| Delete | Move selected frames to the recycle bin (left sidebar) |
| ⌥⌘A | Select all frames |
| ⇧⌘I | Add pictures |
| ⌘E | Export |
| ⌘N | New capture window |

## Download

Get the latest `.dmg` from [Releases](../../releases/latest). Requires macOS 27 or later.

Builds are not yet notarized by Apple. On first launch, right-click SwiftFrame.app → **Open**, or allow it under System Settings → Privacy & Security.

## Building from source

Requirements: Xcode 27+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/build.sh        # Debug build, then launch
scripts/test.sh         # unit tests
scripts/make-dmg.sh     # Release build → dist/SwiftFrame-<version>.dmg
```

The Xcode project is generated from `project.yml`. Run `xcodegen generate` and open `SwiftFrame.xcodeproj` if you want to work in Xcode.

## Releasing

Push a version tag and GitHub Actions builds the DMG and attaches it to a GitHub Release, with the tagged commit's message as the notes:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE), with an added permission: anyone may use SwiftFrame to make animations for any purpose, including commercial work, and what you make is yours. You may download, use, change and share SwiftFrame for noncommercial purposes, but not sell it, charge for it, or use its code in anything sold or offered commercially.
