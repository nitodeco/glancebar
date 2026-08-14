# GlanceBar

GlanceBar is a lightweight native macOS menu bar app for glanceable resource usage. It keeps CPU, GPU, memory, storage, and network activity visible without charts, popovers, notifications, or a web runtime.

![GlanceBar menu bar stats](docs/glancebar-stats.png)

**[Download GlanceBar for macOS](https://github.com/nitodeco/glancebar/releases/latest/download/GlanceBar.dmg)**

## Features

- CPU, optional GPU, RAM, and SSD usage as compact percentages.
- Upload and download throughput with fixed-width network layout.
- Per-metric visibility and drag-and-drop ordering.
- Configurable polling interval, GPU polling multiplier, warning threshold, and critical threshold.
- Color presets plus advanced per-color HSL tuning.
- Auto contrast that follows the current menu bar appearance.
- Launch-at-login support.

## Requirements

- macOS 14 or newer
- Swift 6.2 or newer

## Quick Start

Download [GlanceBar.dmg](https://github.com/nitodeco/glancebar/releases/latest/download/GlanceBar.dmg), open it, and drag `GlanceBar.app` to Applications. A [ZIP archive](https://github.com/nitodeco/glancebar/releases/latest/download/GlanceBar.app.zip) is also available.

GlanceBar releases are Developer ID signed and notarized so macOS can verify them on first launch.

## Development

```sh
./Scripts/build-app.sh
open .build/release/GlanceBar.app
```

Click the menu bar item to open the menu. Choose Settings to configure metrics, colors, thresholds, and polling.

Build the executable:

```sh
swift build
```

Create a release `.app` bundle:

```sh
./Scripts/build-app.sh
```

Sign a release `.app` bundle:

```sh
GLANCEBAR_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/sign-app.sh
```

Create a signed release disk image:

```sh
GLANCEBAR_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/package-app.sh
```

Run tests:

```sh
swift test
```

## Settings

- Metrics can be enabled, disabled, and reordered.
- Launch at login can be enabled or disabled.
- CPU, GPU, RAM, and SSD values can turn yellow above the warning threshold and red above the critical threshold.
- GPU polling is optional and runs at a fixed multiple of the standard polling interval.
- Network upload and download colors are configured separately from threshold colors.
- Base text and label text colors can be set manually, or Auto contrast can adapt them to the menu bar appearance.

## Packaging

`./Scripts/build-app.sh` writes the app bundle to:

```text
.build/release/GlanceBar.app
```

`./Scripts/package-app.sh` writes the signed release disk image to:

```text
dist/GlanceBar.dmg
```

Release disk images contain `GlanceBar.app` and an Applications shortcut. Pushing a tag like `v0.1.0` signs and notarizes the disk image, staples both the disk image and app, and uploads `GlanceBar.dmg` plus `GlanceBar.app.zip`.

GitHub release signing expects these repository secrets:

- `APPLE_CODESIGN_CERTIFICATE_BASE64`: Base64-encoded `.p12` signing certificate.
- `APPLE_CODESIGN_CERTIFICATE_PASSWORD`: Password for that `.p12`.
- `APPLE_NOTARY_ISSUER_ID`: App Store Connect API issuer ID.
- `APPLE_NOTARY_KEY_BASE64`: Base64-encoded App Store Connect API private key.
- `APPLE_NOTARY_KEY_ID`: App Store Connect API key ID.

Set the repository variable `GLANCEBAR_SIGNING_IDENTITY` if the certificate identity is not uniquely matched by `Developer ID Application`.

## Behavior

- CPU, RAM, and network throughput update at the configured polling interval.
- GPU display is optional and polls at a configurable multiple of the standard polling interval.
- SSD usage updates every 30 seconds.
- Network units are shown as `KB` or `MB`, with up to one decimal place.
- Threshold colors apply to CPU, GPU, RAM, and SSD values only. Network values keep their configured upload and download colors.

## License

MIT. See `LICENSE`.
