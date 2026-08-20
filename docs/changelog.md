# Changelog

All notable changes to **Crona for macOS** are documented here.

## Unreleased

No unreleased changes.

## [1.0.0-beta.15] - 2026-08-20

Crona for macOS v1.0.0-beta.15 improves hard-limit decision making and strengthens release validation.

### Added

- Contextual session-time summaries on hard-limit decision, extension, and commit screens.
- Main-branch and pull-request CI for the macOS unit test suite.

### Changed

- Hard-limit actions now distinguish between deciding whether to continue, choosing an extension, and committing completed work while showing the same authoritative spent and limit values.
- Popup sizing keeps the new context visible without introducing scrolling.
- Custom semantic status colors and transient popup surfaces continue to adapt to the surface underneath them.

### Fixed

- Committing a paused or running stopwatch session now decodes the daemon's timer-state response correctly instead of reporting a missing `ok` field.

### Compatibility

- The Apple marketing version remains `1.0.0`; the build number is `16`.
- The daemon must report protocol version `1.5` during handshake.

## [1.0.0-beta.14] - 2026-08-18

Crona for macOS v1.0.0-beta.14 expands habit management in the menu-bar companion and updates the daemon protocol contract.

### Added

- Habit creation, editing, and explicit deletion confirmation from the menu-bar popover.
- Habit detail, kebab, and secondary-click actions for viewing and managing habits.
- Native habit schedule selection for daily, weekday, and custom schedules.
- Repository and stream selection for habits using the issue-style destination picker.
- A dedicated Stats calendar with historical month navigation and daily focus-score heat-map data.

### Changed

- Habit rows now use compact completion/failure controls and a dedicated action menu.
- Habit creation and editing forms provide descriptive schedule subtitles and custom weekday chips.
- The companion now targets daemon protocol version `1.5`.
- Opening the popover now reconciles the companion's functional date with the daemon before rendering date-scoped tabs.
- Calendar navigation cannot move into future months and loads the complete focus-score range for each historical month.

### Fixed

- Removed SwiftUI publishing warnings caused by direct schedule Picker bindings during view updates.
- Habit destination and schedule controls now remain stable while switching options.
- Historical calendar data no longer jumps between dates or resets to an unrelated month when the calendar opens.

### Compatibility

- The daemon must report protocol version `1.5` during handshake.
- The matching daemon must support the existing `habit.create`, `habit.update`, and `habit.delete` IPC methods.
- The matching daemon must support `dashboard.focus_score_range` for the Stats calendar.

## [1.0.0-beta.13] - 2026-08-16

Crona for macOS v1.0.0-beta.13 expands the menu-bar companion into a faster daily-work surface, adds daemon-backed historical Stats data, and prepares the UI for continued feature growth.

### Added

- Manual session logging from issue cards, including date, duration, break, timing, and notes.
- Issue editing and explicit issue deletion flows from the issue action menu and secondary-click menu.
- Away Mode controls in Settings, including rules, adhoc Away mode, and core date-display configuration.
- Date-range focus-score IPC support for the Stats calendar.
- Calendar-based historical Stats browsing with cached daily scores, heat-map treatment, Away-day states, and a return-to-today control.
- Configured date formatting across Issues, Habits, Wellbeing, and Stats surfaces.

### Changed

- The menu-bar popover now keeps Add Issue only on the Issues tab and exposes Stats calendar navigation on Stats.
- Stats, Issues, Habits, and Wellbeing surfaces received denser layouts, aligned metadata, status-specific indicators, and improved liquid-glass controls.
- Away/rest states use positive green treatment consistently across the calendar, Stats, and companion surfaces.
- The floating timer hides while a hard-limit decision popup is active and returns when focus continues.
- Hard-limit prompts and modal input surfaces were repositioned and refined for clearer action-oriented decisions.
- Notifications for Pomodoro session switches and five-second end reminders now remain companion-fallback-only when a companion surface is present.
- Menubar popover dismissal resets the next opening state to Issues and closes any active Stats calendar presentation.
- Menubar and Settings SwiftUI code is organized into dedicated Tabs, Views, Components, and Models modules.

### Fixed

- Stats calendar days now load the complete requested date range instead of jumping between individual dates.
- Stats date navigation remains centered when the Return-to-Today control appears.
- Issue and habit card content no longer overflows the popover or wraps key status controls unexpectedly.
- Menu and card controls now use stable hit targets, hover feedback, and supported macOS SF Symbols.

### Compatibility

- The companion now targets daemon protocol version `1.4`.
- The daemon must support the `dashboard.focus_score_range` date-range event and the manual session/issue mutation methods used by this release.

## [1.0.0-beta.12] - 2026-08-15

Crona for macOS v1.0.0-beta.12 rebuilds Settings around a purpose-built native window shell and makes Crona easier to reach from the menu bar or a global shortcut.

### Added

- A toggle for showing or hiding Crona's menu-bar item.
- An optional global shortcut recorder for opening Settings, with live key feedback while recording.

### Changed

- Settings now use a dedicated translucent sidebar, native traffic lights, and a compact work-area toolbar.
- Opening Crona from the app bundle presents the menu-bar popup when enabled, or Settings when the menu-bar item is hidden.

### Fixed

- The Settings shortcut recorder is surfaced in General settings and clearly confirms the captured key combination.

## [1.0.0-beta.11] - 2026-08-14

Crona for macOS v1.0.0-beta.11 refines the floating timer and hardens wellbeing’s empty-day handling.

### Added

- Configurable floating timer size presets with Compact, Regular, and Spacious layouts.
- A six-dot default-position picker for the floating timer, defaulting to Bottom Center.
- A live floating timer preview in Menu Bar settings.

### Changed

- Compact timer actions now appear inside the timer surface on hover instead of floating outside the panel.
- Floating timer End now presents and restores its inline commit flow reliably.
- Menu-bar popup presentation uses a fixed viewport with stable AppKit ownership and outside-click dismissal.

### Fixed

- A day without a wellbeing check-in no longer appears as an invalid-response error.
- Wellbeing IPC now distinguishes a valid `result: null` from a malformed response.
- Floating timer controls remain clickable and are not clipped in Compact mode.

## [1.0.0-beta.10] - 2026-08-13

Crona for macOS v1.0.0-beta.10 adds daily wellbeing check-ins, an optional floating timer, and fast issue creation directly from the menu bar.

### Added

- A Wellbeing tab for recording and updating today's mood, energy, stress, sleep quality, and note through the daemon.
- An optional floating timer HUD that keeps the active timer visible outside the menu-bar popover.
- A full-surface issue creator for creating issues in a selected repo and stream without opening the terminal UI.
- Flexible estimate entry using the same minute and `HhMmSs` formats accepted by the TUI.
- An option to add newly created issues to today's plan, with a follow-up action to start focus immediately.

### Changed

- Issue creation replaces the menu-bar dashboard with a dedicated navigation surface instead of appearing as a modal over it.
- Repo and stream selection now uses a searchable two-column picker.
- Settings use a consolidated sidebar and detail layout with clearer grouping and system toolbar treatment.
- Menu-bar popup sizing and transitions are coordinated with the native panel to avoid repeated resizing during issue creation.

### Fixed

- Quick-create controls no longer collide with the menu-bar view tabs.
- Expanding destination selection or additional issue fields no longer causes the outer panel to jump between sizes.
- Interrupted issue-creator transitions no longer reveal stale or interactive hidden content.

## [1.0.0-beta.9] - 2026-08-09

Crona for macOS v1.0.0-beta.9 moves break deferral authority into the daemon and refreshes the companion’s release and protocol integration.

### Added

- A dedicated documentation set for the macOS client, covering installation, runtime behavior, development, release process, and troubleshooting.
- A user-facing General setting to hide Crona from the Dock when no app window is open.
- A branded DMG background and checked-in `dmgbuild` layout configuration for release packaging.
- Away Today controls with a dedicated recovery view and daemon-owned live state.
- Historical away-day summaries and red away dates in the Stats calendar.
- Issue Breakdown, Total Time, and Focus Score options for idle menu-bar text.

### Changed

- Daemon startup now treats discovery as a hint instead of a guarantee and can launch the daemon when discovery is missing or stale.
- Daemon launch resolution now follows the core Crona project's candidate order, including repo-local dev binaries and repo-local `go run` fallback.
- Repeated daemon launch failures now latch the companion into the existing connection error state instead of reconnecting indefinitely.
- Dock activation now returns release builds to menu-bar-only mode when the Settings window closes, unless the new Dock preference disables that behavior.
- Release packaging now builds a styled DMG with pinned `dmgbuild` and an isolated virtualenv in CI.
- The companion now targets daemon protocol version `1.3` for the daemon-owned break-deferral handoff.
- The Stats Target card now uses the daemon's estimate-derived `targetWorkedSeconds` value.
- Connected core settings reload from `settings.changed`, popup opening, and app activation.
- Away dates use a non-color calendar marker, localized date presentation, and richer VoiceOver labels.
- The popup adapts Stats animations and calendar contrast to macOS accessibility display settings.
- Release CI builds the Release-optimized test products without launching GUI XCTest infrastructure before importing signing credentials.

### Fixed

- Break deferral now follows the daemon’s five-second warning and authoritative timer transition instead of a companion-side activity timer.
- Alert delivery ACKs now carry the configured break-deferral action and extension seconds.
- Companion-owned per-session deferral caps and obsolete direct deferral requests were removed.
- Activity Guard again requests deferral only after recent keyboard or drag activity while the daemon remains authoritative.
- Live away state no longer remains enabled merely because the current date exists in historical `awayDates`.
- Idle menu-bar metrics remain anchored to today while browsing historical Stats dates.
- Today metrics and focus score update independently, so one failed daemon endpoint no longer leaves unrelated menu-bar values stale.
- Calendar score prefetching no longer overwrites already-cached daily metrics.

## [1.0.0-beta.8] - 2026-08-05

Crona for macOS v1.0.0-beta.8 improves Pomodoro behavior, daemon compatibility, and timer-driven UI reliability.

### Added

- Activity-aware break-screen deferral while typing or dragging, with configurable extension intervals and per-session caps.
- Pomodoro advance actions in the menu-bar popover for starting breaks early, starting focus, and ending breaks.
- A direct installation/update link when the companion detects a daemon protocol mismatch.

### Changed

- Timer projections, break screens, warning indicators, reminders, and contextual end times now follow the daemon's authoritative Pomodoro timeline.
- Notification delivery reconciliation and activation-policy updates are idempotent to prevent permission-related CPU feedback loops.
- The companion now targets protocol version `1.2` and Swift 6 concurrency semantics.

### Fixed

- Repeated notification-permission failures no longer trigger recursive state publications or sustained CPU usage.
- Warning countdowns no longer remain frozen at their initial value after timer transitions.
- Expired Pomodoro sessions no longer show stale end-time projections.

## [1.0.0-beta.7] - 2026-07-29

Crona for macOS v1.0.0-beta.7 is a hot-fix release focused on historical Stats navigation, popup sizing, and release packaging reliability.

### Added

- A month calendar in the menu-bar Stats tab for browsing historical focus summaries.
- Cached focus-score indicators and background prefetching for visible calendar days.

### Changed

- Stats navigation now supports returning directly to today and refreshes data for the selected logical date.
- Long Now and Stats popup content now adapts between fitting and scrolling layouts.
- DMG packaging validates and normalizes the 720x460 background before building.

### Fixed

- Historical Stats navigation no longer requires stepping through days one at a time.
- Release builds no longer use unsupported SwiftUI toolbar visibility modifiers.

## [1.0.0-beta.5] - 2026-07-28

Crona for macOS v1.0.0-beta.5 finishes the beta release polish around window presence and installer presentation, while keeping the daemon recovery and popup work from beta.4 intact.

### Added

- A General setting to keep Crona out of the Dock whenever no full app window is open.
- A branded DMG background asset and `dmgbuild` settings for drag-install releases.

### Changed

- Release builds now re-evaluate Dock visibility when the Settings window or other regular-window presentations close.
- The release DMG now opens with a restrained terminal-like background and curated drag-to-Applications layout generated by `dmgbuild`.

### Fixed

- Beta builds no longer linger in the Dock after the Settings window closes when the Dock-hiding preference is enabled.

## [1.0.0-beta.4] - 2026-07-28

Crona for macOS v1.0.0-beta.4 hardens daemon startup and recovery, smooths the popup surfaces, and establishes the first complete docs and release-notes structure for the repo.

### Added

- A top-level `README`, project `LICENSE`, docs index, and dedicated install, runtime, development, release, troubleshooting, and changelog documents for the macOS client.
- Public release-notes files under `docs/release-notes/` so macOS releases can ship curated release bodies instead of generated GitHub notes.
- Targeted tests covering daemon launch resolution, launch-failure latching, and manual reconnect recovery.

### Changed

- Popup presentation now uses smoother entry and exit transitions for centered, edge, and corner popup surfaces.
- The hard-limit popup positioning and popup shadow treatment have been refined to remove the visible offset and sharp edge artifacts.
- Default daemon binary names now use `crona-daemon` and `crona-daemon-dev`.
- Daemon launch resolution now mirrors the core Crona project by checking sibling binaries, installed binaries, repo-local `bin/` outputs, and repo-local `go run` fallback for development.
- The release workflow now prefers `docs/release-notes/<tag>.md` when publishing GitHub releases, while still falling back to generated notes if no curated file exists.

### Fixed

- Missing or stale discovery no longer leaves the companion passively disconnected when the daemon can be launched locally.
- Failed daemon launches now enter the existing error state and stop background retries until the user manually reconnects.
- GUI launch environments that do not expose Homebrew paths no longer cause false-positive daemon launch attempts through `/usr/bin/env`.
