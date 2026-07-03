# HRSenseSimulator App Shell

This directory stores the macOS App shell for the simulator UI.

## Current layout

- `HRSenseSimulator.xcodeproj` builds the native macOS app shell.
- `HRSenseSimulatorApp.swift` provides the `@main` entry point.
- `Info.plist` contains the Bluetooth usage description required by the simulator shell.
- `HRSenseSimulator.entitlements` declares the Bluetooth entitlement for the sandboxed app.
- `Assets.xcassets` stores the app icon and accent assets used by the macOS app target.

## Runtime modes

- GUI mode uses the native macOS app target inside `HRSenseSimulator.xcodeproj`.
- CLI/headless mode stays available through `swift run HRSenseSimulator`.
- Both entry points reuse the shared `HRSenseSimulatorKit` and `HRSenseSimulatorUI` modules from the root package.
