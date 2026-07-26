# macOS App Releases

Crona for macOS is released independently from the Crona engine and TUI.

## Channels

- Stable tags use `vX.Y.Z`.
- Beta tags use `vX.Y.Z-beta.N`.
- Beta installations receive beta and stable releases.
- Stable installations receive stable releases only.
- Moving from Beta to Stable does not downgrade the installed application.

The signed Sparkle appcast is published at:

`https://webxsid.github.io/crona-macos/appcast.xml`

## Distribution artifacts

Every stable and beta GitHub release publishes:

- `Crona-<version>-macOS.dmg` for direct installation.
- `Crona-<version>-macOS.zip` for Sparkle updates.
- `Crona-<version>-dSYMs.zip` for crash symbolication.
- `checksums.txt` covering all three artifacts.

The DMG is the user-facing download. Open it and drag `Crona.app` to the
Applications shortcut. The ZIP is consumed by Sparkle and is not intended for
manual installation.

## One-time repository setup

Enable GitHub Pages with **GitHub Actions** as its source and configure:

Repository variable:

- `SPARKLE_PUBLIC_ED_KEY`

Repository secrets:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_PASSWORD`
- `RELEASE_KEYCHAIN_PASSWORD`
- `APPLE_NOTARY_API_KEY_P8`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `SPARKLE_EDDSA_PRIVATE_KEY`

Generate the Sparkle key pair once with Sparkle’s `generate_keys` tool. Put the
public key in the repository variable and the private key in the repository
secret. Keep the same key for all future releases.

## Cutting a release

1. Set the numeric `MARKETING_VERSION` to the tag’s `X.Y.Z` portion. For
   `v1.0.0-beta.1`, use `1.0.0`.
2. Increment `CURRENT_PROJECT_VERSION`. It must be greater than every build in
   the published appcast.
3. Run the macOS unit tests with the Release configuration.
4. Commit the release metadata.
5. Create and push the version tag.

The release workflow builds a universal app, signs it with Developer ID,
notarizes and staples it, then creates both distribution containers. The DMG is
signed, notarized, stapled, mounted, and inspected before publication. The ZIP
is signed by Sparkle when the appcast is generated. The workflow publishes the
GitHub release and deploys the updated feed to GitHub Pages.

Beta identity is stored separately from Apple’s numeric bundle version. The
workflow injects `CRONA_RELEASE_CHANNEL` and the complete
`CRONA_RELEASE_VERSION` from the tag while keeping
`CFBundleShortVersionString` in Apple’s required `X.Y.Z` format.

## Release validation

The workflow verifies the code signatures, notarization tickets, universal
architectures, bundle identifier, version, DMG contents, and checksums. A
release can also be inspected locally with:

```sh
codesign --verify --strict --verbose=2 Crona-<version>-macOS.dmg
xcrun stapler validate Crona-<version>-macOS.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 \
  Crona-<version>-macOS.dmg
```

Homebrew distribution is intentionally limited to the Crona terminal utility.
The native macOS app is distributed through the DMG and updated through
Sparkle.
