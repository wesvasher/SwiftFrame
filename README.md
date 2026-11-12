# SwiftFrame

A native macOS app for making stop motion animation.

Each SwiftFrame window is a capture window for one project. It shows the live camera with an onion skin of your last frames, keeps every frame in a filmstrip you can edit, and plays the animation back at full speed whenever you want to check it. You can have as many capture windows open as you like, each with its own camera.

> Status: early development.

## Features

- **Live capture**: pick any connected camera (built-in, USB, or Continuity Camera), mirror it if you like, and tap ⌘ to capture a frame.
- **Onion skin**: show up to five earlier frames over the live camera, fading with age, at the opacity you choose.
- **Real-time preview**: press Space to play and pause the animation at 12 or 24 fps, or any custom rate from 1 to 60, chosen with the switch on the capture bar, looping or once, with the playing frame shown in the filmstrip.
- **Frame editing**: click a frame to review it. Shift- or Command-click to select more, drag a frame by its handle to reorder, right-click for more, and duplicate, delete, reverse, or hold frames for longer (×2 for shooting "on twos"). Every edit can be undone.
- **Navigator**: when the timeline is zoomed in, a miniature of every frame above it outlines the part in view. Drag the box to move along the timeline, or click to jump.
- **Playhead**: a line across the filmstrip at the frame showing, gliding along while it plays with a trail of fire streaming off the back (turn it off in Settings). Drag it, or click or drag in the strip above the frames, to scrub; past the last frame is the live camera.
- **Back to capturing**: click the Capture tile at the right of the timeline, press → past the last frame, or press ⌘L.
- **Import pictures**: drop image files onto the filmstrip, or use Frame → Add Pictures.
- **Export**: save a QuickTime movie in H.264, HEVC, or ProRes 422.
- **Settings**: choose Auto, Light or Dark appearance, whether the viewer flashes when you capture, and whether the playhead trails fire.
- **Projects**: each project is a `.swiftframe` package that holds its frames as JPEGs, so you can save, reopen, and keep working.

## Keyboard

| Key | Action |
| --- | --- |
| ⌘ (tap on its own) | Capture a frame |
| Space | Play / pause |
| ← → | Previous / next frame (→ past the end goes live) |
| ⌘L | Go live |
| ⌘D | Duplicate selected frames |
| ⌘] / ⌘[ | Hold longer / shorter |
| Delete | Delete selected frames |
| ⌥⌘A | Select all frames |
| ⇧⌘I | Add pictures |
| ⌘E | Export movie |
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
