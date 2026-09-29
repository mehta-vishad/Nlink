# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ENlink is a fork of [BetterBlue](https://github.com/schmidtwmark/BetterBlue) (MIT, by Mark Schmidt),
reduced to a single-vehicle iOS app plus a home screen widget for a 2025 Hyundai Elantra N.
Built with SwiftUI, SwiftData, and powered by the
[BetterBlueKit](https://github.com/schmidtwmark/BetterBlueKit) Swift package.

The plan of record is `workorder.md` at the repo root. Read it before making structural changes.

### What this fork removed, and why

The app is signed with a **free Apple Developer Personal Team**, which cannot sign
iCloud, Push Notifications, or a Watch app. Phase 1 of the work order therefore deleted:

- the `BetterBlueWatch Watch App` and `WatchWidgetExtension` targets
- `LiveActivityBackend` (the serverless push backend) and all ActivityKit code
- the `aps-environment` and iCloud/CloudKit entitlements
- CloudKit-backed SwiftData storage and the CloudKit sync diagnostics

Do not reintroduce any of these unless the project moves to a paid account
(work order Phase 9). Two targets remain: `BetterBlue` and `WidgetExtension`.

### BetterBlueKit Submodule

BetterBlueKit is included as a **git submodule** in the `BetterBlueKit/` directory. This allows local development and testing of BetterBlueKit changes without pushing to GitHub. The project is configured to use the local package via `XCLocalSwiftPackageReference`.

To initialize or update the submodule after cloning:
```bash
git submodule update --init --recursive
```

**Important**: The local submodule has the SwiftLint plugin commented out in `Package.swift` to avoid build conflicts with the main project. When pushing BetterBlueKit changes upstream, you may need to uncomment the plugin configuration in the standalone repository.

## Build Commands

### Building the Project
If `xcode-select -p` points at `/Library/Developer/CommandLineTools`, either fix it
(`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`) or set
`DEVELOPER_DIR` per-command — the latter needs no password:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

```bash
# Open in Xcode
open BetterBlue.xcodeproj

# Build for iOS simulator (no signing needed — use this to check compilation)
xcodebuild -scheme BetterBlue -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build

# Build for device (requires Config/Local.xcconfig — create it with scripts/setup-signing.sh)
xcodebuild -scheme BetterBlue -destination 'generic/platform=iOS' build

# Build Widget extension
xcodebuild -scheme WidgetExtension build
```

Building the `BetterBlue` scheme also builds and embeds `WidgetExtension.appex`,
so it is the single check that covers both targets.

### Linting
SwiftLint has been removed from the project to avoid plugin conflicts when BetterBlueKit is used as a local package. You can run SwiftLint manually if needed:
```bash
swiftlint lint
```

## Architecture

### Multi-Target Structure
Two targets share a common SwiftData container:
- **BetterBlue** (main iOS app)
- **WidgetExtension** (home screen, lock screen, and Control Center widgets)
- **BetterBlueKit** (local Swift package submodule for API communication)

Both targets use Xcode's *file system synchronized groups*: any file added under
`BetterBlue/` or `Widget/` joins that target automatically. To compile a file from
`BetterBlue/` into `WidgetExtension` as well, add it to that target's
`PBXFileSystemSynchronizedBuildFileExceptionSet` in the project file.

### Data Persistence Layer

#### SwiftData Models
All models are in `BetterBlue/Models/`:
- `BBAccount.swift` - User accounts with credentials and brand/region
- `BBVehicle.swift` - Vehicle data with status, settings, and climate presets
- `HTTPLog.swift` - HTTP request/response logging
- `ClimatePreset.swift` - User-defined climate control presets

#### Shared Model Container
`SharedModelContainer.swift` provides the critical `createSharedModelContainer()` function.
Storage is **local-only** — there is no CloudKit sync:
- **Simulator**: uses `/tmp/BetterBlue_Shared` to work around App Group isolation
- **Device**: App Group container when available, otherwise a per-process store
  under Application Support (`getLocalStoreURL()`)
- Both targets must use this function to ensure data sharing
- The App Group identifier comes from `AppIdentifiers` (`BetterBlue/Utility/AppIdentifiers.swift`),
  which reads an Info.plist key injected from `Config/Shared.xcconfig` (default
  `group.com.betterblue.shared`; per-machine overrides in gitignored `Config/Local.xcconfig`).
  Never hardcode this string in source — use `AppIdentifiers`.

**Gate G1 passed (2026-09-28):** the App Group entitlement signs on the Personal Team,
and on device the store lives in the App Group container (verified: no fallback store in
the app's own Application Support). App and widget share one store. The per-process
fallback remains only as a safety net; if it were ever needed for real, the widget would
also need its own credentials (`Config/Secrets.example.swift`) — that part is not built.

### API Client Architecture

#### Layered API Design (see `BetterBlue/Utility/`)
1. **BetterBlueKit Package** - Core API clients (Hyundai, Kia, Fake) implementing `APIClientProtocol`
2. **CachedAPIClient** (`CachedAPIClient.swift`) - Request deduplication and 5-second caching wrapper
3. **APIClientFactory** (`APIClientFactory.swift`) - Creates appropriate API client based on brand
4. **BBAccount Model** - SwiftData wrapper managing API client lifecycle, auth tokens, and command execution

#### Key Points
- API clients are `@Transient` (not persisted) and lazy-initialized on first use
- `CachedAPIClient` prevents duplicate simultaneous requests and caches responses
- Invalid session/credentials trigger automatic re-initialization via `handleInvalidVehicleSession()`
- Kia vehicles require `vehicleKey` field for commands (auto-fetched if missing)

### Status Change Waiting Pattern

`BBVehicle.waitForStatusChange()` implements an interruptible polling mechanism:
- Used after commands to wait for vehicle state changes (lock/unlock/climate)
- Polls status at intervals with configurable retry count
- Can be woken up early via `wakeUpStatusWaiters()` when status updates arrive
- Uses continuation-based async pattern with `StatusWaitingManager` actor

### App Intents & Widgets

`Widget/VehicleAppIntents.swift` provides Siri shortcuts, Control Center widgets, and app intents:
- **Lock/Unlock**: `LockVehicleIntent`, `UnlockVehicleIntent` with status waiting
- **Climate**: `StartClimateIntent`, `StopClimateIntent` (start uses selected climate preset)
- **Status**: `RefreshVehicleStatusIntent`, `GetVehicleStatusIntent`

Control Center widgets use `ControlConfigurationIntent` for user-configured vehicle selection.
Notifications are **local only**; there is no remote push registration.

### ENlink widget

`Widget/ENlinkWidget.swift` is this fork's home screen widget (systemMedium, registered first
in `BetterBlueWidgetBundle`). It reuses `VehicleTimelineProvider.loadVehicle(_:)` for data and
the existing `*ControlIntent`s for its buttons. Visual tokens live in `ENlinkStyle`; the
Performance Blue values were measured from the car photo. Check changes in every rendering
mode: full color draws its own glass background, while Clear/Tinted home screens replace the
container background with system Liquid Glass and render content in a single tint.

The car image comes from `scripts/cutout-car.swift` (Vision subject lifting),
`scripts/neutralize-car.swift` (studio-style tone) and `scripts/make-car-asset.swift` (sizing;
`--fade-left` only for photos cropped at the rear). It is CC BY-SA 4.0 — keep the README
credit if it is replaced or regenerated. Do not use Hyundai, EVOX/KBB or other manufacturer or
stock renders: they are copyrighted and the repo is public. The car faces left, so the layout
puts text on the left and the car on the right.

When no vehicle is configured, surfaces use `BBVehicle.primary(in:)` /
`VehicleQuery.defaultResult()`, which put Fake Vehicle Mode accounts last.

### Fake Vehicle Mode

Testing without real vehicles is supported via `Brand.fake`:
- `SwiftDataFakeVehicleProvider` (`BetterBlue/Utility/`) stores fake vehicle state in SwiftData
- `BBDebugConfiguration` struct enables simulating various failure modes
- Fake accounts automatically created for test credentials (see `APIClientFactory.isTestAccount()`)
- A fake account starts with **no cars**: add them under *Fake Vehicles* on the Add Account
  screen (or later in the account's info screen) before tapping Add
- In the Simulator, build **signed** (omit `CODE_SIGNING_ALLOWED=NO`): an unsigned widget
  extension never renders and stays on its placeholder

## Key Concepts

### SwiftData Relationships
- `BBAccount` ←→ `BBVehicle`: One-to-many with cascade delete
- `BBVehicle` ←→ `ClimatePreset`: One-to-many with cascade delete
- Use `safeVehicles` and `safeClimatePresets` properties to safely unwrap optional relationships

### HTTP Logging
`HTTPLogSinkManager` singleton coordinates logging across all targets:
- Must be configured with `createSharedModelContainer()` and device type
- Creates `HTTPLogSink` instances for API clients to inject logs
- Logs viewable in Settings > HTTP Logs
- `HTTPLogMirror` also appends each (already redacted) log as a JSON line to
  `Library/Logs/http-<source>.jsonl` in the App Group container, one file per process,
  rotated at 5 MB. `./scripts/pull-phone-logs.sh` copies those files off a connected
  iPhone into gitignored `.phone-logs/` and prints a summary. Never pull the SwiftData
  store itself: `ZBBACCOUNT` holds the Bluelink password and PIN in plain text.

### Distance & Temperature Units
`AppSettings` manages user preferences (stored in UserDefaults):
- `preferredDistanceUnit`: miles or kilometers
- `preferredTemperatureUnit`: Fahrenheit or Celsius
- Used throughout UI and in VehicleEntity for App Intents

### Account Initialization Pattern
Always initialize accounts before use:
```swift
try await account.initialize(modelContext: modelContext)
```
This ensures API client is created and login is performed.

### Vehicle Updates
`BBAccount.updateVehicles()` syncs fetched vehicles with SwiftData:
- Updates existing vehicles while preserving UI state (custom names, colors, sort order)
- Creates new vehicles with auto-incrementing sort order
- Removes vehicles no longer returned by API

## Common Workflows

### Adding a New Vehicle Command
1. Add to `VehicleCommand` enum in BetterBlueKit
2. Implement in BetterBlueKit API clients (Hyundai/Kia/Fake)
3. Add convenience method in `BBAccount` extensions (see `lockVehicle()`, etc.)
4. Create App Intent in `VehicleAppIntents.swift` if needed
5. Update fake vehicle provider in `SwiftDataFakeVehicleProvider.executeCommand()`

### Creating a New Widget
1. Create widget view conforming to `Widget` protocol in `Widget/`
2. Register in `BetterBlueWidgetBundle.swift`
3. Use `createSharedModelContainer()` in timeline provider
4. Query `BBVehicle` with proper predicates for filtering

### Credentials
Never commit credentials. `Secrets.swift` is gitignored everywhere in the tree;
`Config/Secrets.example.swift` is the committed template. Verify with
`git check-ignore -v <path>` before a first push.

### Debugging Data Sync Issues
- Check device type detection in `HTTPLogSinkManager.detectMainAppDeviceType()`
- Verify App Group container is accessible: look for "App Group container not accessible"
  warnings — that message means the store fell back to the per-process location
- On simulator, check `/tmp/BetterBlue_Shared/BetterBlue.sqlite`
- Use Diagnostics view (Settings > About) to inspect accounts, vehicles, and store path

## File Organization

- `BetterBlue/Views/` - SwiftUI views for main app
- `BetterBlue/Views/Components/` - Reusable view components
- `BetterBlue/Models/` - SwiftData models
- `BetterBlue/Utility/` - Helper classes and utilities
- `Widget/` - Widget extension, widget views, and App Intents
- `Config/` - xcconfig signing overrides and the `Secrets.example.swift` template

## Important Conventions

- All API operations must pass `modelContext: ModelContext` parameter
- Use `@MainActor` for SwiftData operations and API client methods
- Vehicle commands should use status waiting pattern where state verification is needed
- Climate presets: selected preset takes precedence, fallback to first preset, then default options
- VIN is the primary identifier for vehicles across all operations
