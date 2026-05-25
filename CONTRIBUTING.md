# Contributing

Thanks for contributing to OPC UA Client.

## Development Setup

1. Install Xcode 26.5 or newer.
2. Install open62541:

```sh
brew install open62541
```

3. Build the app:

```sh
xcodebuild -project OpcUaClient.xcodeproj \
  -scheme OpcUaClient \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS=arm64 \
  build
```

## Pull Requests

- Keep changes focused and explain the user-facing behavior.
- Include verification steps in the PR description.
- Add or update examples under `Tools/` when changing OPC UA behavior.
- Keep `OpcUaClient.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  when Swift package dependencies change.
- Update `NOTICE`, `THIRD_PARTY_NOTICES.md`, and `README.md` when adding,
  removing, or changing third-party dependencies.
- Do not commit local Xcode state, logs, compiled sample binaries, certificates,
  private keys, provisioning profiles, or generated build output.

## Security-Sensitive Changes

Treat connection credentials, private keys, certificates, and OPC UA server
addresses as sensitive. New persistence code should avoid writing secrets to
plain JSON, UserDefaults, SwiftData, or logs.
