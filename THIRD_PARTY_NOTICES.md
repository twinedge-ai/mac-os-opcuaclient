# Third-Party Notices

This document summarizes third-party dependencies used by OPC UA Client.
It is a release aid, not a replacement for the license texts distributed by
each dependency.

## open62541

- Project: open62541
- Homepage: https://open62541.org/
- Source: https://github.com/open62541/open62541
- License: Mozilla Public License 2.0 (MPL-2.0)
- Use in this repository: external Homebrew library linked by
  `build_config.xcconfig` with `-lopen62541`
- Vendored source: no
- Local source modifications: none

For binary app distribution, either document the Homebrew runtime requirement
or bundle the exact `libopen62541.dylib` used and include the MPL-2.0 notice,
license text, and source-code link for that build.

## Swift Package Dependencies

The Xcode project resolves Swift package dependencies through:

```text
OpcUaClient.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

Current resolved packages:

| Package | Source | License |
| --- | --- | --- |
| swift-nio | https://github.com/apple/swift-nio.git | Apache-2.0 |
| swift-atomics | https://github.com/apple/swift-atomics.git | Apache-2.0 |
| swift-collections | https://github.com/apple/swift-collections.git | Apache-2.0 |
| swift-system | https://github.com/apple/swift-system.git | Apache-2.0 |

SwiftNIO includes its own `NOTICE.txt`; include that upstream notice when
shipping binary distributions that include SwiftNIO code.

## Apple SDKs And Frameworks

The app uses Apple SDK frameworks through Xcode and the macOS SDK. Those
frameworks are subject to Apple's developer and SDK license terms and are not
vendored in this repository.
