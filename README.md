# GlanceBar

GlanceBar is a lightweight native macOS menu bar app for glanceable resource usage.

It shows CPU, optional GPU, RAM, SSD usage, and network throughput in a compact `NSStatusItem`. There are no charts, popovers, sensors, process lists, notifications, or web runtimes.

## Requirements

- macOS 14 or newer
- Swift 6.2 or newer

## Build

```sh
swift build
```

To create a `.app` bundle:

```sh
./Scripts/build-app.sh
```

The bundle is written to:

```text
.build/release/GlanceBar.app
```

## Run

```sh
open .build/release/GlanceBar.app
```

Click the menu bar item to open the menu. Choose Settings to open the settings window.

## Test

```sh
swift test
```

## Behavior

- CPU, RAM, and network throughput update every 3 seconds.
- GPU display is optional and polls at a configurable multiple of the standard polling interval.
- SSD usage updates every 30 seconds.
- CPU, GPU, RAM, and SSD values turn yellow above 60 percent and red above 80 percent by default.
- Upload is purple, download is blue.
- Polling interval, GPU polling multiplier, yellow threshold, red threshold, indicator color presets, upload color preset, and download color preset are configurable.

## License

MIT. See `LICENSE`.
