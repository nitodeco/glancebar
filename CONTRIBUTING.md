# Contributing

GlanceBar is intentionally small. Keep changes focused on a native, low-overhead macOS menu bar app.

## Development

Use SwiftPM:

```sh
swift test
swift build
./Scripts/build-app.sh
```

Verify that all three pass before opening a pull request.

## Making changes

- Keep commit messages short and simple
- Add or modify tests if changing behavior
- Ensure every keep ressource footprint minimal
