# GlanceBar Spec

GlanceBar is a lightweight native macOS menu bar app for glanceable resource usage.

## Goals

- Show only CPU, RAM, SSD, and network throughput.
- Use a native AppKit `NSStatusItem`.
- Keep idle CPU near zero.
- Avoid popovers, charts, histories, top-process lists, sensors, and GPU polling.
- Keep v1 hardcoded with no settings UI and no config file.

## Layout

Metrics are arranged like Stats.

- CPU: label above percentage.
- RAM: label above percentage used.
- SSD: label above percentage used.
- Network: upload and download values stacked on top of each other.

Example:

```text
CPU   RAM   SSD    ↑ 3 KB/s
13%   72%   81%    ↓ 10 KB/s
```

## Metrics

- CPU uses total system CPU usage.
- RAM uses percent used.
- SSD uses percent used on the Data volume.
- Network uses current throughput in bytes per second, shown as upload and download.

## Polling

- CPU, RAM, and network update every 3 seconds.
- SSD usage updates every 30 seconds.

## Interaction

- Clicking the menu bar item opens a tiny menu with Settings and Quit.
- Clicking Settings opens a lightweight settings window.
- No popover or secondary dashboard.

## Settings

- Polling interval.
- Threshold when CPU, RAM, and SSD values use the warning color.
- Warning color for CPU, RAM, and SSD values above the threshold.
- Upload and download colors for network values.

## Non-Goals

- No auto-launch at login in v1.
- No charts.
- No process list.
- No sensors.
- No GPU display.
- No notifications.
- No Electron or web runtime.
