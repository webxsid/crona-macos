# Install

## Distribution Model

Crona for macOS is released independently from the core Crona daemon and terminal surfaces.

Every GitHub release publishes:

- `Crona-<version>-macOS.dmg` for direct installation
- `Crona-<version>-macOS.zip` for Sparkle updates
- `Crona-<version>-dSYMs.zip` for crash symbolication
- `checksums.txt` for artifact verification

The DMG is the user-facing installer. The ZIP exists for Sparkle and is not the intended manual install artifact.

Releases are published here:

- <https://github.com/webxsid/crona-macos/releases>

## Release Channels

- stable tags use `vX.Y.Z`
- beta tags use `vX.Y.Z-beta.N`
- beta installations receive beta and stable releases
- stable installations receive stable releases only

The app embeds both the Apple marketing version and a separate Crona release channel/version for update routing.

## Runtime Requirement

The macOS app is a client for the local Crona runtime. It expects a runtime directory that contains:

- `kernel.json` for discovery metadata
- `kernel.sock` for the local socket endpoint, unless discovery points elsewhere

By default the app looks in:

- production: `~/Library/Application Support/Crona`
- development: `~/Library/Application Support/Crona Dev`

You can override the runtime directory with `CRONA_HOME`.

## First Run Expectation

If the runtime is missing or not running, the app can still launch, but daemon-backed features will remain degraded until discovery succeeds and the socket becomes reachable.

For shared daemon installation and provisioning guidance, use the core Crona install docs:

- <https://github.com/webxsid/crona/blob/main/docs/install.md>

## Updates

The app uses Sparkle for in-app updates. The signed appcast feed is published at:

- <https://webxsid.github.io/crona-macos/appcast.xml>

Use the DMG for manual upgrades. Sparkle consumes the ZIP artifact and appcast feed automatically.
