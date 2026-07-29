# Repository Guidelines

## Project Structure & Module Organization

`crona/` contains the macOS app source, split by responsibility: `App/` for app lifecycle, `Features/` for user-facing flows, `Platform/` for AppKit and windowing code, `Services/` for app services, `IPC/` for daemon communication, and `Shared/` for cross-cutting models and helpers. Tests live in `cronaTests/` and `cronaUITests/`. Release assets and packaging inputs live under `assets/release/` and `scripts/`. Project docs, release notes, and changelog entries live in `docs/`.

## Build, Test, and Development Commands

- `xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug build`  
  Builds the macOS app locally.
- `xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug test -destination "platform=macOS"`  
  Runs the full local test suite.
- `xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug test -destination "platform=macOS" -only-testing:cronaTests`  
  Runs unit tests only; use this for most code changes.
- `git diff --check`  
  Verifies patch hygiene before committing.

## Coding Style & Naming Conventions

Use Swift conventions already present in the repo: types in `UpperCamelCase`, functions and properties in `lowerCamelCase`, and descriptive enum cases. Match the surrounding file style rather than introducing new patterns. Keep edits scoped and prefer existing services/helpers over new abstractions. Use ASCII by default. Add comments only where the intent is not obvious from the code.

## Testing Guidelines

Tests use `XCTest`. Add or update focused tests in `cronaTests/` for behavior changes in services, popup positioning, daemon connectivity, or release-channel logic. Follow the existing naming pattern: `test<BehaviorDescription>()`, for example `testInactivityPopupPositionerStagesCenteredPopupsOffscreen()`. Prefer narrow unit coverage over broad fixture-heavy tests unless a shared workflow changes.

## Commit & Pull Request Guidelines

Recent history uses short, imperative commit subjects, for example `Switch DMG packaging to dmgbuild` and `Use virtualenv for dmgbuild in release workflow`. Keep commit messages specific to the user-visible or operational change. For pull requests, include: a brief summary, testing performed, linked issue or release context, and screenshots when UI or DMG presentation changes.

## Release & Configuration Notes

The GitHub Actions release workflow in `.github/workflows/release.yml` builds, signs, notarizes, and publishes the app. DMG layout is configured in `scripts/dmgbuild_settings.py`. Version metadata lives in `crona.xcodeproj/project.pbxproj`; update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` deliberately when cutting releases.

## macOS Window Chrome Notes

- For the Settings window, prefer scene-level toolbar styling first. `Settings` needs an explicit `windowToolbarStyle(...)` on the scene to get the system toolbar surface to render correctly.
- If the toolbar background reads as fully transparent, apply `toolbarBackground(.regularMaterial, for: .windowToolbar)` and `toolbarBackgroundVisibility(.visible, for: .windowToolbar)` on the view tree, not on the `Scene`.
- `WindowService.registerSettingsWindow(_:)` should only adjust AppKit-level window behavior that the scene cannot express, such as `titlebarAppearsTransparent`, `backgroundColor`, `toolbarStyle`, and `titlebarSeparatorStyle`.
- Keep the toolbar split by OS version narrow and verify against screenshots before adding custom chrome. If the system toolbar still does not paint a real background, switch to a custom toolbar rather than stacking more translucent overlays.
