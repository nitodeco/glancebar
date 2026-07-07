# Contributing

GlanceBar is intentionally small. Keep changes focused on a native, low-overhead macOS menu bar app.

## Development

Use SwiftPM:

```sh
swift test
swift build
./Scripts/build-app.sh
```

Run all three commands before opening a pull request.

## Scope

In scope:

- CPU, optional GPU, RAM, SSD, and network throughput display.
- Native AppKit menu bar behavior.
- Compact settings for polling intervals, warning thresholds, and color presets.
- Small reliability, formatting, packaging, and test improvements.

Out of scope for v1:

- Popovers, charts, histories, and dashboards.
- Process lists, sensors, or notifications.
- Electron or web runtimes.

## Code Style

- Prefer simple AppKit and SwiftPM conventions.
- Keep the idle app cheap to run.
- Avoid comments unless the code is hard to understand without one.
- Add focused tests for formatting, timing, and metric calculations.
