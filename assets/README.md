# Portly icons

The app and menu bar share a network socket mark. The app icon uses a teal
background and warm contacts; the menu bar uses a monochrome template that
macOS tints for the current appearance.

- `AppIcon.png`: 1024-pixel preview.
- `AppIcon.iconset/`: standard macOS icon sizes, including Retina variants.
- `AppIcon.icns`: icon bundled by `scripts/build-app.sh`.
- `../Sources/Portly/Resources/MenuBarIcon.pdf`: 18-point vector menu bar template.

Regenerate the assets from the repository root on macOS:

```sh
swift scripts/generate-icons.swift
```

The editable drawing source is `scripts/generate-icons.swift`. Build a local app
without installing it with `scripts/build-app.sh --build-only`.
