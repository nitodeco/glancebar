# GlanceBar

GlanceBar is a lightweight native macOS menu bar app for glanceable resource usage.

It shows CPU, RAM, SSD usage, and network throughput in a compact `NSStatusItem`. There are no charts, popovers, settings, sensors, process lists, notifications, or web runtimes.

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

Click the menu bar item to open the menu. The only menu action is Quit.

## Test

```sh
swift test
```

## Behavior

- CPU, RAM, and network throughput update every 3 seconds.
- SSD usage updates every 30 seconds.
- CPU, RAM, and SSD values turn red above 80 percent.
- Upload is purple, download is blue.

## License

MIT. See `LICENSE`.
