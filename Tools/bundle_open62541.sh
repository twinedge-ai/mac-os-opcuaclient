#!/usr/bin/env bash
set -euo pipefail

OPEN62541_PREFIX="${OPEN62541_PREFIX:-/opt/homebrew/opt/open62541}"
MIN_OPEN62541_VERSION="${MIN_OPEN62541_VERSION:-1.5.4}"
LIB_LINK="$OPEN62541_PREFIX/lib/libopen62541.dylib"

fail() {
  echo "error: $*" >&2
  exit 1
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

open62541_version() {
  local pc_file="$OPEN62541_PREFIX/lib/pkgconfig/open62541.pc"
  if [ -f "$pc_file" ]; then
    /usr/bin/awk -F': *' '/^Version:/ { print $2; exit }' "$pc_file"
    return
  fi

  local config_header="$OPEN62541_PREFIX/include/open62541/config.h"
  if [ -f "$config_header" ]; then
    local major minor patch
    major="$(/usr/bin/awk '/UA_OPEN62541_VER_MAJOR/ { print $3; exit }' "$config_header")"
    minor="$(/usr/bin/awk '/UA_OPEN62541_VER_MINOR/ { print $3; exit }' "$config_header")"
    patch="$(/usr/bin/awk '/UA_OPEN62541_VER_PATCH/ { print $3; exit }' "$config_header")"
    if [ -n "$major" ] && [ -n "$minor" ] && [ -n "$patch" ]; then
      printf '%s.%s.%s\n' "$major" "$minor" "$patch"
    fi
  fi
}

if [ ! -e "$LIB_LINK" ]; then
  fail "open62541 dylib not found at $LIB_LINK"
fi

OPEN62541_DETECTED_VERSION="$(open62541_version)"
if [ -z "$OPEN62541_DETECTED_VERSION" ]; then
  fail "could not determine open62541 version under OPEN62541_PREFIX=$OPEN62541_PREFIX"
fi
if semver_lt "$OPEN62541_DETECTED_VERSION" "$MIN_OPEN62541_VERSION"; then
  fail "open62541 $OPEN62541_DETECTED_VERSION is below required $MIN_OPEN62541_VERSION"
fi

LIB_ID="$(/usr/bin/otool -D "$LIB_LINK" | /usr/bin/awk 'NR == 2 { print $1 }')"
if [ -z "$LIB_ID" ]; then
  fail "could not read open62541 install name from $LIB_LINK"
fi

LIB_REAL="$LIB_LINK"
while [ -L "$LIB_REAL" ]; do
  target="$(/usr/bin/readlink "$LIB_REAL")"
  case "$target" in
    /*) LIB_REAL="$target" ;;
    *) LIB_REAL="$(/usr/bin/dirname "$LIB_REAL")/$target" ;;
  esac
done

LIB_NAME="$(/usr/bin/basename "$LIB_ID")"
BUNDLE_LIB="@executable_path/../Frameworks/$LIB_NAME"
DEST_DIR="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
APP_CONTENTS_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
APP_MACOS_DIR="$APP_CONTENTS_DIR/MacOS"

patch_macho_load_command() {
  local binary="$1"
  [ -f "$binary" ] || return 0
  /usr/bin/file "$binary" | /usr/bin/grep -q "Mach-O" || return 0

  /usr/bin/install_name_tool -change "$LIB_ID" "$BUNDLE_LIB" "$binary" 2>/dev/null || true
  /usr/bin/install_name_tool -delete_rpath "$OPEN62541_PREFIX/lib" "$binary" 2>/dev/null || true
}

/bin/mkdir -p "$DEST_DIR"
/bin/cp -f "$LIB_REAL" "$DEST_DIR/$LIB_NAME"
/usr/bin/install_name_tool -id "$BUNDLE_LIB" "$DEST_DIR/$LIB_NAME"

if [ -d "$APP_MACOS_DIR" ]; then
  while IFS= read -r -d '' mach_o; do
    patch_macho_load_command "$mach_o"
  done < <(/usr/bin/find "$APP_MACOS_DIR" -type f -print0)
else
  patch_macho_load_command "$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
fi

found_bundle_ref=0
external_refs=()
if [ -d "$APP_MACOS_DIR" ]; then
  while IFS= read -r -d '' mach_o; do
    /usr/bin/file "$mach_o" | /usr/bin/grep -q "Mach-O" || continue
    while IFS= read -r link_line; do
      case "$link_line" in
        *"$BUNDLE_LIB"*) found_bundle_ref=1 ;;
        *"$LIB_ID"*|*"$OPEN62541_PREFIX/lib"*) external_refs+=("$mach_o: $link_line") ;;
      esac
    done < <(/usr/bin/otool -L "$mach_o" 2>/dev/null || true)
  done < <(/usr/bin/find "$APP_MACOS_DIR" -type f -print0)
fi

if [ "${#external_refs[@]}" -gt 0 ]; then
  echo "error: app still links to external open62541:" >&2
  printf '  %s\n' "${external_refs[@]}" >&2
  exit 1
fi

if [ "$found_bundle_ref" -eq 0 ]; then
  echo "error: app is not linked to bundled $LIB_NAME" >&2
  exit 1
fi

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] &&
   [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] &&
   [ "${EXPANDED_CODE_SIGN_IDENTITY:-}" != "-" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime --timestamp=none "$DEST_DIR/$LIB_NAME"
fi
