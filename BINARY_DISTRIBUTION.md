# Binary Distribution

This repository can produce an Apple Silicon macOS app bundle for local or
public distribution. The app currently targets macOS 14.0 or later on `arm64`.
The default Apple Silicon Homebrew `open62541` dependency is arm64-only, so the
generated app is not universal.

## Current Local Artifact Strategy

- Build configuration: Release
- Architecture: arm64
- Minimum macOS version: 14.0
- Runtime dependency: `libopen62541.*.dylib` bundled in
  `OPC UA Client.app/Contents/Frameworks`
- Code signing: ad-hoc for local testing unless a Developer ID Application
  certificate is supplied
- Notarization: required for a smooth public download experience

Create a local package with:

```sh
Tools/package_macos_release.sh
```

For a public package, use a Developer ID Application identity:

```sh
PUBLIC_RELEASE=1 \
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="OPCUAClient" \
  Tools/package_macos_release.sh
```

The script writes generated files to `dist/` and temporary build products to
`build/`; both are local artifacts and should not be committed.

Store the notary profile once on the release machine. This command prompts for
the app-specific password instead of putting the password in the repository or
shell history:

```sh
xcrun notarytool store-credentials "OPCUAClient" \
  --apple-id "you@example.com" \
  --team-id "TEAMID"
```

For `PUBLIC_RELEASE=1`, the script refuses to continue unless:

- A Developer ID Application signing identity is supplied.
- A notarytool keychain profile is supplied.
- The bundled `open62541` dylib was built for a macOS version no newer than the
  release minimum.

If your local Homebrew `open62541` bottle was built for a newer macOS, build a
release dependency prefix with:

```sh
Tools/build_open62541_release.sh
```

That helper downloads the upstream source tarball, verifies its SHA-256 digest,
and installs an `arm64` dylib compiled with:

```sh
CMAKE_OSX_ARCHITECTURES=arm64
CMAKE_OSX_DEPLOYMENT_TARGET=14.0
```

Then package with the printed prefix:

```sh
OPEN62541_PREFIX=/path/to/open62541-prefix \
PUBLIC_RELEASE=1 \
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="OPCUAClient" \
Tools/package_macos_release.sh
```

## Public Release Requirement

For a server-hosted download that ordinary macOS users can open without
Gatekeeper workarounds, the packaging script signs the app with hardened
runtime, notarizes and staples the app bundle, signs the DMG, notarizes and
staples the DMG, runs `spctl` assessment, and writes SHA-256 checksums.

The manual equivalent is to sign nested Mach-O code first, then sign the app:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  "path/to/OPC UA Client.app/Contents/Frameworks"/libopen62541.*.dylib

codesign --force --options runtime --timestamp \
  --entitlements Resources/OpcUaClient.entitlements \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  "path/to/OPC UA Client.app"

xcrun notarytool submit path/to/OPC-UA-Client.dmg \
  --keychain-profile "OPCUAClient" \
  --wait

xcrun stapler staple path/to/OPC-UA-Client.dmg

xcrun stapler validate path/to/OPC-UA-Client.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 path/to/OPC-UA-Client.dmg
```

Apple Development certificates and ad-hoc signatures are useful for local
testing, but they are not enough for a polished public download.

## Intel And Universal Builds

The default `/opt/homebrew` `open62541` library is arm64. To ship a universal
app, provide a universal `libopen62541.dylib` or build separate arm64 and
x86_64 packages, then test each package on matching hardware.
