# Troubleshooting

## The App Opens But Does Not Connect

Check the runtime directory first:

- production builds expect `~/Library/Application Support/Crona`
- debug builds expect `~/Library/Application Support/Crona Dev`
- `CRONA_HOME` overrides both

Confirm the runtime contains `kernel.json` and that the socket endpoint it describes is live. If discovery is missing, the app can still launch, but daemon-backed flows will remain unavailable.

## Break Screens Or Focus Popups Do Not Behave Correctly

These surfaces depend on the app being connected to the local runtime and receiving the right timer or alert state transitions. Start with diagnostics:

- verify connection state
- verify endpoint and transport
- verify alert backend
- verify last error

If diagnostics show stale connection metadata, restart the daemon runtime before debugging the UI layer.

## Notifications Do Not Fire

Check both macOS notification permissions and the diagnostics snapshot's reported alert backend. A healthy daemon connection with a missing or degraded alert backend usually indicates an OS permission problem or a runtime-side alert issue.

## Updates Do Not Appear

Confirm:

- the app is on the intended channel, stable or beta
- the appcast feed is reachable: <https://webxsid.github.io/crona-macos/appcast.xml>
- the embedded release version is older than the published version

Remember that beta installs can see both beta and stable releases, while stable installs only see stable releases.

## Release Build Validation Fails

Check the release workflow assumptions:

- `MARKETING_VERSION` must match the tag's base `X.Y.Z`
- `CURRENT_PROJECT_VERSION` must be greater than the latest appcast build
- the Sparkle public key must decode to 32 bytes
- notarization credentials and Developer ID certificate must be valid

## Support Snapshot

When filing a bug, capture the diagnostics snapshot first. It includes runtime directory, endpoint, transport, daemon version, alert backend, and last error, which materially reduces guesswork during triage.
