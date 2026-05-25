# Release Checklist

Use this checklist before tagging a release or publishing a binary. Do not use
it as legal advice.

## Source Release

- Confirm `git status --short` only shows intentional changes.
- Confirm no credentials, certificates, private keys, provisioning profiles,
  local endpoints, logs, or build products are committed.
- Build from a clean checkout with the README build command.
- Verify `Package.resolved` is committed for reproducible Swift package
  resolution.
- Include `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md`, `TRADEMARKS.md`,
  `CONTRIBUTING.md`, and `SECURITY.md`.
- Confirm the README states the supported macOS/Xcode/open62541 setup.

## Binary App Release

- Confirm the release target is `arm64` with `MACOSX_DEPLOYMENT_TARGET = 14.0`
  unless the release notes intentionally state another Apple Silicon minimum.
- Decide whether the app requires Homebrew `open62541` at runtime or bundles
  `libopen62541.dylib`.
- If bundling `libopen62541.dylib`, include the MPL-2.0 notice, license text,
  and a source-code link for the exact open62541 build.
- Confirm the bundled `libopen62541.dylib` was built for a macOS minimum no
  newer than the app's deployment target.
- Use `Tools/build_open62541_release.sh` when the installed Homebrew bottle was
  built for a newer macOS than the release minimum.
- If modifying open62541 source, publish those modified source files under
  MPL-2.0.
- Include Apache-2.0 notices for Swift package dependencies, including
  SwiftNIO's upstream `NOTICE.txt`.
- Store notarization credentials with `xcrun notarytool store-credentials`;
  do not commit Apple IDs, app-specific passwords, certificates, or keychain
  exports.
- Build the public package with `PUBLIC_RELEASE=1`,
  `SIGN_IDENTITY="Developer ID Application: ..."`, and
  `NOTARY_KEYCHAIN_PROFILE=...`.
- Verify the packaged app and DMG with `codesign --verify --deep --strict`,
  `xcrun stapler validate`, and `spctl --assess`.
- Publish checksums for downloadable artifacts and regenerate them after every
  packaging change.
- Test launch on a clean machine or clean user account with the documented
  open62541 runtime strategy.

## Project Claims

- Do not state that the app is OPC Foundation certified unless certification
  has been completed.
- Do not use OPC Foundation logos or certification marks without permission.
- Use "OPC UA client" descriptively, not as an endorsement or affiliation claim.
