#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
ARCH="${ARCH:-arm64}"
OPEN62541_PREFIX="${OPEN62541_PREFIX:-}"
MIN_OPEN62541_VERSION="${MIN_OPEN62541_VERSION:-1.5.4}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_PRODUCT_NAME="${APP_PRODUCT_NAME:-OPC UA Client}"
ARTIFACT_BASENAME="${ARTIFACT_BASENAME:-OPC-UA-Client}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-twinedgeai.com.MacOpcUaClient}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
PUBLIC_RELEASE="${PUBLIC_RELEASE:-0}"
NOTARIZE="${NOTARIZE:-$PUBLIC_RELEASE}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEY="${NOTARY_KEY:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${NOTARY_ISSUER:-}"
ALLOW_INCOMPATIBLE_OPEN62541="${ALLOW_INCOMPATIBLE_OPEN62541:-0}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$REPO_ROOT/build/release-derived-data}"
SWIFTPM_CHECKOUTS="${SWIFTPM_CHECKOUTS:-$DERIVED_DATA_DIR/SourcePackages/checkouts}"

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

version_number() {
  local version="$1"
  local major=0 minor=0 patch=0
  IFS=. read -r major minor patch <<< "$version"
  printf '%d%03d%03d\n' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

version_gt() {
  [ "$(version_number "$1")" -gt "$(version_number "$2")" ]
}

semver_number() {
  local version="$1"
  local major=0 minor=0 patch=0
  IFS=. read -r major minor patch <<< "$version"
  major="${major%%[^0-9]*}"
  minor="${minor%%[^0-9]*}"
  patch="${patch%%[^0-9]*}"
  printf '%d%03d%03d\n' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

semver_lt() {
  [ "$(semver_number "$1")" -lt "$(semver_number "$2")" ]
}

dylib_min_macos() {
  vtool -show-build "$1" 2>/dev/null | awk '/minos/ { print $2; exit }'
}

open62541_has_encryption() {
  local config_header="$OPEN62541_PREFIX/include/open62541/config.h"
  [ -f "$config_header" ] &&
    grep -Eq '^#define UA_ENABLE_ENCRYPTION_(OPENSSL|MBEDTLS|LIBRESSL)\b' "$config_header"
}

open62541_uses_openssl() {
  local config_header="$OPEN62541_PREFIX/include/open62541/config.h"
  [ -f "$config_header" ] &&
    grep -Eq '^#define UA_ENABLE_ENCRYPTION_OPENSSL\b' "$config_header"
}

open62541_version() {
  local pc_file="$OPEN62541_PREFIX/lib/pkgconfig/open62541.pc"
  if [ -f "$pc_file" ]; then
    awk -F': *' '/^Version:/ { print $2; exit }' "$pc_file"
    return
  fi

  local config_header="$OPEN62541_PREFIX/include/open62541/config.h"
  if [ -f "$config_header" ]; then
    local major minor patch
    major="$(awk '/UA_OPEN62541_VER_MAJOR/ { print $3; exit }' "$config_header")"
    minor="$(awk '/UA_OPEN62541_VER_MINOR/ { print $3; exit }' "$config_header")"
    patch="$(awk '/UA_OPEN62541_VER_PATCH/ { print $3; exit }' "$config_header")"
    if [ -n "$major" ] && [ -n "$minor" ] && [ -n "$patch" ]; then
      printf '%s.%s.%s\n' "$major" "$minor" "$patch"
    fi
  fi
}

has_notary_credentials() {
  [ -n "$NOTARY_KEYCHAIN_PROFILE" ] ||
    { [ -n "$NOTARY_KEY" ] && [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER" ]; }
}

notarize_artifact() {
  local submit_path="$1"
  local staple_path="$2"
  local notary_args=()

  if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
    notary_args=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
  elif [ -n "$NOTARY_KEY" ] && [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER" ]; then
    notary_args=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  else
    fail "notarization requires NOTARY_KEYCHAIN_PROFILE or NOTARY_KEY, NOTARY_KEY_ID, and NOTARY_ISSUER"
  fi

  echo "Submitting for notarization: $submit_path"
  xcrun notarytool submit "$submit_path" "${notary_args[@]}" --wait

  echo "Stapling notarization ticket: $staple_path"
  xcrun stapler staple "$staple_path"
  xcrun stapler validate "$staple_path"
}

require_command xcodebuild
require_command otool
require_command vtool
require_command install_name_tool
require_command codesign
require_command ditto
require_command hdiutil
require_command shasum
require_command xcrun

if [ -z "$OPEN62541_PREFIX" ]; then
  require_command brew
  OPEN62541_PREFIX="$(brew --prefix open62541)"
fi

OPEN62541_DETECTED_VERSION="$(open62541_version)"
if [ -z "$OPEN62541_DETECTED_VERSION" ]; then
  fail "could not determine open62541 version under OPEN62541_PREFIX=$OPEN62541_PREFIX"
fi
if semver_lt "$OPEN62541_DETECTED_VERSION" "$MIN_OPEN62541_VERSION"; then
  fail "open62541 $OPEN62541_DETECTED_VERSION is below required $MIN_OPEN62541_VERSION"
fi

if truthy "$PUBLIC_RELEASE"; then
  truthy "$NOTARIZE" || fail "PUBLIC_RELEASE=1 requires notarization"
  [ "$SIGN_IDENTITY" != "-" ] || fail "PUBLIC_RELEASE=1 requires SIGN_IDENTITY='Developer ID Application: ...'"
fi

if truthy "$NOTARIZE"; then
  [ "$SIGN_IDENTITY" != "-" ] || fail "NOTARIZE=1 requires SIGN_IDENTITY='Developer ID Application: ...'"
  has_notary_credentials || fail "NOTARIZE=1 requires NOTARY_KEYCHAIN_PROFILE or NOTARY_KEY, NOTARY_KEY_ID, and NOTARY_ISSUER"
fi

if [ "$SIGN_IDENTITY" != "-" ]; then
  require_command security
  security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null \
    || fail "signing identity not found in keychain: $SIGN_IDENTITY"
fi

OPEN62541_LIB_SYMLINK="$OPEN62541_PREFIX/lib/libopen62541.dylib"
if ! open62541_has_encryption; then
  fail "open62541 at OPEN62541_PREFIX=$OPEN62541_PREFIX was built without encryption support. Run Tools/build_open62541_release.sh and package with its OPEN62541_PREFIX output."
fi

OPEN62541_ID="$(otool -D "$OPEN62541_LIB_SYMLINK" | awk 'NR == 2 { print $1 }')"
if [ -z "$OPEN62541_ID" ]; then
  echo "Could not read open62541 install name from $OPEN62541_LIB_SYMLINK" >&2
  exit 1
fi

OPEN62541_REAL="$OPEN62541_LIB_SYMLINK"
while [ -L "$OPEN62541_REAL" ]; do
  target="$(readlink "$OPEN62541_REAL")"
  case "$target" in
    /*) OPEN62541_REAL="$target" ;;
    *) OPEN62541_REAL="$(dirname "$OPEN62541_REAL")/$target" ;;
  esac
done

OPEN62541_MIN_OS="$(dylib_min_macos "$OPEN62541_REAL")"
if [ -n "$OPEN62541_MIN_OS" ] && version_gt "$OPEN62541_MIN_OS" "$MIN_MACOS_VERSION"; then
  message="open62541 at $OPEN62541_REAL was built for macOS $OPEN62541_MIN_OS, newer than release minimum $MIN_MACOS_VERSION"
  if truthy "$PUBLIC_RELEASE" && ! truthy "$ALLOW_INCOMPATIBLE_OPEN62541"; then
    fail "$message. Build or provide an OPEN62541_PREFIX compiled with CMAKE_OSX_DEPLOYMENT_TARGET=$MIN_MACOS_VERSION."
  fi
  echo "Warning: $message." >&2
fi

external_open62541_dependencies=()
while IFS= read -r link_line; do
  case "$link_line" in
    *"libssl."*|*"libcrypto."*|*"/opt/homebrew/opt/openssl"*|*"/usr/local/opt/openssl"*)
      external_open62541_dependencies+=("$link_line")
      ;;
  esac
done < <(otool -L "$OPEN62541_REAL" 2>/dev/null || true)

if [ "${#external_open62541_dependencies[@]}" -gt 0 ]; then
  printf '  %s\n' "${external_open62541_dependencies[@]}" >&2
  fail "open62541 has unbundled OpenSSL runtime dependencies; rebuild it with Tools/build_open62541_release.sh"
fi

OPEN62541_BUNDLE_NAME="$(basename "$OPEN62541_ID")"
OPEN62541_BUNDLE_PATH="@executable_path/../Frameworks/$OPEN62541_BUNDLE_NAME"
OPEN62541_LICENSE="$(find "$OPEN62541_PREFIX" -maxdepth 5 -type f -name LICENSE 2>/dev/null | sort | tail -n 1 || true)"
OPEN62541_LICENSE_CC0="$(find "$OPEN62541_PREFIX" -maxdepth 5 -type f -name LICENSE-CC0 2>/dev/null | sort | tail -n 1 || true)"
OPENSSL_LICENSE="$(find "$OPEN62541_PREFIX" -maxdepth 6 -type f -path '*/share/openssl/LICENSE.txt' 2>/dev/null | sort | tail -n 1 || true)"
OPENSSL_NOTICE="$(find "$OPEN62541_PREFIX" -maxdepth 6 -type f -path '*/share/openssl/NOTICE.txt' 2>/dev/null | sort | tail -n 1 || true)"

if { [ -z "$OPEN62541_LICENSE" ] || [ -z "$OPEN62541_LICENSE_CC0" ]; } && command -v brew >/dev/null 2>&1; then
  OPEN62541_CELLAR="$(brew --cellar open62541 2>/dev/null || true)"
  if [ -n "$OPEN62541_CELLAR" ]; then
    [ -n "$OPEN62541_LICENSE" ] || OPEN62541_LICENSE="$(find "$OPEN62541_CELLAR" -maxdepth 3 -type f -name LICENSE 2>/dev/null | sort | tail -n 1 || true)"
    [ -n "$OPEN62541_LICENSE_CC0" ] || OPEN62541_LICENSE_CC0="$(find "$OPEN62541_CELLAR" -maxdepth 3 -type f -name LICENSE-CC0 2>/dev/null | sort | tail -n 1 || true)"
  fi
fi

if truthy "$PUBLIC_RELEASE" && [ -z "$OPEN62541_LICENSE" ]; then
  fail "could not find open62541 LICENSE under OPEN62541_PREFIX=$OPEN62541_PREFIX"
fi

if open62541_uses_openssl && [ -z "$OPENSSL_LICENSE" ]; then
  fail "open62541 was built with OpenSSL, but OpenSSL LICENSE.txt was not found under OPEN62541_PREFIX=$OPEN62541_PREFIX"
fi

xcodebuild \
  -project OpcUaClient.xcodeproj \
  -scheme OpcUaClient \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=$ARCH" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  OPEN62541_PREFIX="$OPEN62541_PREFIX" \
  MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS_VERSION" \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS="$ARCH" \
  build

APP_SRC="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_PRODUCT_NAME.app"
if [ ! -d "$APP_SRC" ]; then
  echo "Built app not found at $APP_SRC" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_SRC/Contents/Info.plist" 2>/dev/null || echo 1.0)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP_SRC/Contents/Info.plist" 2>/dev/null || echo 1)"
APP_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP_SRC/Contents/Info.plist" 2>/dev/null || echo "$APP_PRODUCT_NAME")"
NAME="$ARTIFACT_BASENAME-$VERSION-$BUILD-macOS-$ARCH"
STAGE="$DIST_DIR/$NAME"
DMG_STAGE="$DIST_DIR/$NAME-dmg"
ZIP="$DIST_DIR/$NAME.zip"
DMG="$DIST_DIR/$NAME.dmg"
APP_NOTARY_ZIP="$DIST_DIR/$NAME-app-notary.zip"

rm -rf "$STAGE" "$DMG_STAGE" "$ZIP" "$DMG" "$APP_NOTARY_ZIP" "$DIST_DIR/SHA256SUMS.txt"
mkdir -p "$STAGE" "$STAGE/ThirdPartyLicenses"
ditto "$APP_SRC" "$STAGE/$APP_PRODUCT_NAME.app"
ln -s /Applications "$STAGE/Applications"

cp LICENSE NOTICE README.md THIRD_PARTY_NOTICES.md TRADEMARKS.md BINARY_DISTRIBUTION.md RELEASE_CHECKLIST.md "$STAGE/"
[ -n "$OPEN62541_LICENSE" ] && cp "$OPEN62541_LICENSE" "$STAGE/ThirdPartyLicenses/open62541-MPL-2.0-LICENSE"
[ -n "$OPEN62541_LICENSE_CC0" ] && cp "$OPEN62541_LICENSE_CC0" "$STAGE/ThirdPartyLicenses/open62541-CC0-LICENSE"
[ -n "$OPENSSL_LICENSE" ] && cp "$OPENSSL_LICENSE" "$STAGE/ThirdPartyLicenses/OpenSSL-Apache-2.0-LICENSE.txt"
[ -n "$OPENSSL_NOTICE" ] && cp "$OPENSSL_NOTICE" "$STAGE/ThirdPartyLicenses/OpenSSL-NOTICE.txt"
cp "$SWIFTPM_CHECKOUTS/swift-nio/LICENSE.txt" "$STAGE/ThirdPartyLicenses/swift-nio-Apache-2.0-LICENSE.txt"
cp "$SWIFTPM_CHECKOUTS/swift-nio/NOTICE.txt" "$STAGE/ThirdPartyLicenses/swift-nio-NOTICE.txt"
cp "$SWIFTPM_CHECKOUTS/swift-atomics/LICENSE.txt" "$STAGE/ThirdPartyLicenses/swift-atomics-Apache-2.0-LICENSE.txt"
cp "$SWIFTPM_CHECKOUTS/swift-collections/LICENSE.txt" "$STAGE/ThirdPartyLicenses/swift-collections-Apache-2.0-LICENSE.txt"
cp "$SWIFTPM_CHECKOUTS/swift-system/LICENSE.txt" "$STAGE/ThirdPartyLicenses/swift-system-Apache-2.0-LICENSE.txt"

APP="$STAGE/$APP_PRODUCT_NAME.app"
APP_BINARY="$APP/Contents/MacOS/$APP_EXECUTABLE"
APP_LEGAL_DIR="$APP/Contents/Resources/Legal"
mkdir -p "$APP_LEGAL_DIR"
cp LICENSE NOTICE README.md THIRD_PARTY_NOTICES.md TRADEMARKS.md BINARY_DISTRIBUTION.md RELEASE_CHECKLIST.md "$APP_LEGAL_DIR/"
ditto "$STAGE/ThirdPartyLicenses" "$APP_LEGAL_DIR/ThirdPartyLicenses"
mkdir -p "$APP/Contents/Frameworks"
cp "$OPEN62541_REAL" "$APP/Contents/Frameworks/$OPEN62541_BUNDLE_NAME"
install_name_tool -id "$OPEN62541_BUNDLE_PATH" "$APP/Contents/Frameworks/$OPEN62541_BUNDLE_NAME"

while IFS= read -r -d '' mach_o; do
  if file "$mach_o" | sed -n '1p' | grep -q 'Mach-O'; then
    install_name_tool -change "$OPEN62541_ID" "$OPEN62541_BUNDLE_PATH" "$mach_o" 2>/dev/null || true
    install_name_tool -delete_rpath "$OPEN62541_PREFIX/lib" "$mach_o" 2>/dev/null || true
  fi
done < <(find "$APP/Contents/MacOS" -type f -print0)

found_open62541_bundle_ref=0
external_open62541_refs=()
while IFS= read -r -d '' mach_o; do
  file "$mach_o" | sed -n '1p' | grep -q 'Mach-O' || continue
  while IFS= read -r link_line; do
    case "$link_line" in
      *"$OPEN62541_BUNDLE_PATH"*) found_open62541_bundle_ref=1 ;;
      *"$OPEN62541_ID"*|*"$OPEN62541_PREFIX/lib"*) external_open62541_refs+=("$mach_o: $link_line") ;;
    esac
  done < <(otool -L "$mach_o" 2>/dev/null || true)
done < <(find "$APP/Contents/MacOS" -type f -print0)

if [ "${#external_open62541_refs[@]}" -gt 0 ]; then
  printf '  %s\n' "${external_open62541_refs[@]}" >&2
  fail "packaged app still links to external open62541"
fi

if [ "$found_open62541_bundle_ref" -eq 0 ]; then
  fail "packaged app is not linked to bundled $OPEN62541_BUNDLE_NAME"
fi

codesign_args=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign_args+=(--options runtime --timestamp)
fi

while IFS= read -r -d '' mach_o; do
  if file "$mach_o" | sed -n '1p' | grep -q 'Mach-O'; then
    codesign "${codesign_args[@]}" "$mach_o"
  fi
done < <(find "$APP/Contents/Frameworks" -type f -print0)

if [ -d "$APP/Contents/Resources/swift-nio_NIOPosix.bundle" ]; then
  codesign "${codesign_args[@]}" "$APP/Contents/Resources/swift-nio_NIOPosix.bundle"
fi
codesign "${codesign_args[@]}" --entitlements Resources/OpcUaClient.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if truthy "$NOTARIZE"; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_NOTARY_ZIP"
  notarize_artifact "$APP_NOTARY_ZIP" "$APP"
  rm -f "$APP_NOTARY_ZIP"
  spctl --assess --type execute --verbose=4 "$APP"
fi

ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"
mkdir -p "$DMG_STAGE"
ditto "$APP" "$DMG_STAGE/$APP_PRODUCT_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_PRODUCT_NAME $VERSION" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG"
if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_IDENTIFIER.dmg" --timestamp "$DMG"
fi

if truthy "$NOTARIZE"; then
  notarize_artifact "$DMG" "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
fi

shasum -a 256 "$ZIP" "$DMG" > "$DIST_DIR/SHA256SUMS.txt"

echo "Created:"
echo "  $DMG"
echo "  $ZIP"
echo "  $DIST_DIR/SHA256SUMS.txt"

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo
  echo "Warning: app was ad-hoc signed. Use SIGN_IDENTITY='Developer ID Application: ...' and notarize before public distribution."
fi
