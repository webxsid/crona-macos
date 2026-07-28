# Runtime

## Terminology

The macOS codebase still uses `kernel` in several type and config names. User-facing docs should read that as the local Crona daemon/runtime.

Examples:

- discovery file: `kernel.json`
- default socket path: `kernel.sock`
- executable names: `crona-daemon`, `crona-daemon-dev`

## Runtime Directory Resolution

At launch, the app resolves the runtime directory in this order:

1. `CRONA_HOME` environment override
2. bundled `CRONA_RUNTIME_DIR` value from the active build configuration

Current defaults:

- Debug: `~/Library/Application Support/Crona Dev`
- Release: `~/Library/Application Support/Crona`

## Discovery and Connection

`CronaConfigLoader` builds runtime config from the bundle and environment, then attempts to load discovery metadata from:

- `<runtime>/kernel.json`

It also derives the default socket path:

- `<runtime>/kernel.sock`

If the discovery file is missing, the app still boots, but runtime-backed surfaces will not be fully available until the daemon becomes discoverable.

## Diagnostics Surface

The diagnostics service reports:

- connection state
- protocol version
- daemon version/channel
- runtime directory
- health summary
- last reconnect time
- endpoint
- transport
- alert backend
- last error

That snapshot is the first place to check when the app appears connected visually but runtime-backed features are not behaving correctly.

## Build-Time Runtime Settings

The app currently ships with these base config values:

- `CRONA_DAEMON_LABEL = crona`
- `CRONA_KERNEL_EXECUTABLE = crona-daemon`
- `CRONA_KERNEL_DEV_EXECUTABLE = crona-daemon-dev`
- `CRONA_RELEASE_CHANNEL = stable`
- `CRONA_RELEASE_VERSION = $(MARKETING_VERSION)`

Those values come from the Xcode config files in [`Config`](../Config).
