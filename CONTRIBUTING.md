# Contributing

## Development setup

1. Install Xcode 26 or newer.
2. Open `InternetSpeed.xcodeproj`.
3. Run `swift test`.
4. Run an app build with:

```bash
xcodebuild -project InternetSpeed.xcodeproj -target InternetSpeed -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Pull requests

- Keep the app menu-bar-first and lightweight.
- Prefer native macOS APIs over third-party dependencies unless the gain is clear.
- Add or update tests for scheduler, persistence, parsing, or UI-facing state changes.
- Keep user-facing strings concise and consistent with the existing app tone.

## Reporting issues

- Include your macOS version.
- Include whether a VPN is active.
- Include the configured auto-test interval.
- Include the diagnostics report copied from the app's right-click menu when relevant.
