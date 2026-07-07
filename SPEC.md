# GlanceBar Spec

GlanceBar is a lightweight native macOS menu bar app for glanceable resource usage.

## Goals

- Show CPU, optional GPU, RAM, SSD, and network throughput.
- Use a native AppKit `NSStatusItem`.
- Keep idle CPU near zero.
- Avoid popovers, charts, histories, top-process lists, and sensors.

## Layout

Metrics are arranged like Stats.

- CPU: label above percentage.
- GPU: label above percentage, shown between CPU and RAM when enabled.
- RAM: label above percentage used.
- SSD: label above percentage used.
- Network: upload and download values stacked on top of each other.

Example:

```text
CPU   GPU   RAM   SSD    ↑ 3 KB/s
13%   24%   72%   81%    ↓ 10 KB/s
```

## Metrics

- CPU uses total system CPU usage.
- GPU uses total GPU device utilization when available.
- RAM uses percent used.
- SSD uses percent used on the Data volume.
- Network uses current throughput in bytes per second, shown as upload and download.

## Polling

- CPU, RAM, and network update every 3 seconds.
- GPU has an independent configurable update interval.
- SSD usage updates every 30 seconds.

## Interaction

- Clicking the menu bar item opens a tiny menu with Settings and Quit.
- Clicking Settings opens a lightweight settings window.
- No popover or secondary dashboard.

## Settings

- Polling interval.
- GPU enabled.
- GPU polling interval.
- Threshold when CPU, GPU, RAM, and SSD values use the warning color.
- Warning color preset for CPU, GPU, RAM, and SSD values above the threshold.
- Upload and download color presets for network values.

## Non-Goals

- No auto-launch at login in v1.
- No charts.
- No process list.
- No sensors.
- No notifications.
- No Electron or web runtime.
