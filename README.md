# Crona for macOS

Crona for macOS is the native macOS client for Crona. It connects to the local Crona daemon runtime, exposes focus and break workflows as native windows and notifications, and ships as a signed macOS app with Sparkle updates.

This repository contains the SwiftUI/AppKit client. The core Crona daemon, CLI, and terminal UI live in the main Crona repository:

- Core repo: <https://github.com/webxsid/crona>
- Core docs: <https://github.com/webxsid/crona/tree/main/docs>

## What Lives Here

- native macOS app shell
- daemon discovery and connection plumbing
- notifications, break screens, and timer surfaces
- diagnostics and updater integration
- release packaging for DMG and Sparkle distribution

## Install

Use the docs in this repository for the macOS app itself:

- [Docs Index](docs/README.md)
- [Install](docs/install.md)
- [Runtime](docs/runtime.md)
- [Development](docs/development.md)
- [Release](docs/release.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Changelog](docs/changelog.md)

The macOS app expects a local Crona runtime directory with daemon discovery metadata. Shared product concepts, CLI usage, and daemon behavior are documented in the main Crona repo rather than duplicated here.

## Support

- macOS app releases: <https://github.com/webxsid/crona-macos/releases>
- core project issues and discussions: <https://github.com/webxsid/crona>

## License

[MIT](LICENSE)
