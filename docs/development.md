# Development

## Repository Scope

This repository contains the native macOS client. The core daemon, CLI, and terminal UI are maintained in the main Crona repo:

- <https://github.com/webxsid/crona>

When a change touches daemon behavior, protocol, or shared product language, confirm the corresponding source of truth in the core repo instead of drifting the macOS client docs or assumptions.

## Requirements

- Xcode with macOS SDK support
- access to the Crona runtime if you need to exercise live daemon-backed flows

The app resolves Swift package dependencies through Xcode.

## Local Build

Open `crona.xcodeproj` in Xcode and run the `crona` scheme, or build from the command line:

```sh
xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug -sdk macosx build
```

Debug builds target:

- `~/Library/Application Support/Crona Dev`

Release builds target:

- `~/Library/Application Support/Crona`

Use `CRONA_HOME` when you need to point the app at a different runtime directory during testing.

## Tests

Run the macOS tests with:

```sh
xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug -sdk macosx -destination "platform=macOS" test
```

For release validation, run the same test suite in `Release` before tagging.

## Documentation Boundaries

Keep this repo's docs focused on:

- native app behavior
- runtime discovery and diagnostics
- release packaging and update flow

Do not duplicate shared concepts, CLI usage, or daemon internals that already belong to the main Crona docs set.
