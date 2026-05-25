# Repository Guidelines

## Project Structure & Module Organization
- `App/` contains the SwiftUI app entrypoint and application state.
- `Core/` contains domain models, SwiftData persistence, configuration import/export, and utilities.
- `OPCUA/` contains the C bridge, Swift clients, OPC UA services, and certificate handling.
- `Features/` groups SwiftUI screens by product area.
- `SharedUI/` contains the design system and shared components.
- `Resources/` contains assets and entitlements.
- `OpcUaClient.xcodeproj/` is the Xcode project configuration.
- `build_config.xcconfig` defines Homebrew include/library paths and links `open62541`.
- `Tools/` contains standalone client/server test scripts and sample utilities.

## Build, Test, and Development Commands
- `open OpcUaClient.xcodeproj` to build/run in Xcode (recommended for UI work).
- `xcodebuild -project OpcUaClient.xcodeproj -scheme OpcUaClient -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build` for a CLI build.
- `clang Tools/CClients/test_client.c -I/opt/homebrew/include -L/opt/homebrew/lib -lopen62541 -o Tools/CClients/test_client` to build a sample C client.
- `python3 Tools/PythonClients/test_python_client.py` to run a Python client example.

## Coding Style & Naming Conventions
- Swift: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for vars/functions.
- C: 4-space indentation, `snake_case` for functions/locals where applicable.
- Keep file names descriptive (e.g., `ContentView.swift`, `test_opcua_browse.c`).
- Prefer small, focused functions and explicit error handling (see `App/OpcUaClientApp.swift`).

## Testing Guidelines
- There is no unified test runner; tests are example programs and scripts.
- Name new tests with the `test_` prefix and a clear suffix (e.g., `test_subscription.c`).
- Verify connectivity using a local OPC UA server before running client tests.

## Commit & Pull Request Guidelines
- Commit messages are sentence-style and descriptive (no enforced prefix).
- PRs should include: a short summary, steps to verify, and UI screenshots when relevant.
- Link related issues or tasks in the PR description when applicable.

## Configuration & Dependencies
- `open62541` is required via Homebrew: `brew install open62541`.
- Do not vendor the upstream `open62541` checkout in this repository unless the dependency strategy changes.
- Override `OPEN62541_PREFIX` or update `build_config.xcconfig` if include/library locations change.
