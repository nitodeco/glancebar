<div align="center">
  <h1>
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/glancebar-icon-dark.png">
      <source media="(prefers-color-scheme: light)" srcset="docs/glancebar-icon-light.png">
      <img alt="GlanceBar app icon" src="docs/glancebar-icon-light.png" width="64" height="64" align="absmiddle">
    </picture>&nbsp;GlanceBar
  </h1>
  <p><strong>Lightweight system stats in the menu bar. <a href="https://github.com/nitodeco/glancebar/releases/latest/download/GlanceBar.dmg">Download GlanceBar for macOS.</a></strong></p>
</div>

![GlanceBar menu bar stats](docs/glancebar-screenshot.webp)

## Features

- CPU, optional GPU, RAM, and SSD usage as compact percentages.
- Upload and download throughput with fixed-width network layout.
- Per-metric visibility and drag-and-drop ordering.
- Configurable polling interval, GPU polling multiplier, warning threshold, and critical threshold.
- Color presets plus advanced per-color HSL tuning.
- Auto contrast that follows the current menu bar appearance.
- Launch-at-login support.

## Settings

- Metrics can be enabled, disabled, and reordered.
- Launch at login can be enabled or disabled.
- CPU, GPU, RAM, and SSD values can turn yellow above the warning threshold and red above the critical threshold.
- GPU polling is optional and runs at a fixed multiple of the standard polling interval.
- Network upload and download colors are configured separately from threshold colors.
- Base text and label text colors can be set manually, or Auto contrast can adapt them to the menu bar appearance.

## Behavior

- CPU, RAM, and network throughput update at the configured polling interval.
- GPU display is optional and polls at a configurable multiple of the standard polling interval.
- SSD usage updates every 30 seconds.
- Network units are shown as `KB` or `MB`, with up to one decimal place.
- Threshold colors apply to CPU, GPU, RAM, and SSD values only. Network values keep their configured upload and download colors.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
