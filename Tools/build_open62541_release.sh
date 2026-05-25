#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

OPEN62541_VERSION="${OPEN62541_VERSION:-1.5.4}"
MIN_OPEN62541_VERSION="${MIN_OPEN62541_VERSION:-1.5.4}"
OPEN62541_SHA256="${OPEN62541_SHA256:-fb5aafc19c67a91368d1f71d9ee4acf0f4b47a0d65c66db4ed738691828779c7}"
OPEN62541_SOURCE_URL="${OPEN62541_SOURCE_URL:-https://github.com/open62541/open62541/archive/refs/tags/v$OPEN62541_VERSION.tar.gz}"
OPEN62541_CRYPTO_BACKEND="${OPEN62541_CRYPTO_BACKEND:-OPENSSL}"
OPENSSL_ROOT_DIR="${OPENSSL_ROOT_DIR:-}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.6.2}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
ARCH="${ARCH:-arm64}"
BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/build/open62541-release}"
PREFIX="${OPEN62541_PREFIX:-$REPO_ROOT/build/open62541-$OPEN62541_VERSION-macos-$MIN_MACOS_VERSION-$ARCH}"
LINK_FATAL_WARNINGS="${LINK_FATAL_WARNINGS:-1}"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
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

if semver_lt "$OPEN62541_VERSION" "$MIN_OPEN62541_VERSION"; then
  fail "open62541 $OPEN62541_VERSION is below required $MIN_OPEN62541_VERSION"
fi

require_command cmake
require_command curl
require_command shasum
require_command tar
require_command vtool

cmake_crypto_args=("-DUA_ENABLE_ENCRYPTION=$OPEN62541_CRYPTO_BACKEND")
if [ "$OPEN62541_CRYPTO_BACKEND" = "OPENSSL" ]; then
  LOCAL_OPENSSL_ROOT="$REPO_ROOT/build/openssl-$OPENSSL_VERSION-macos-$MIN_MACOS_VERSION-$ARCH"
  if [ -z "$OPENSSL_ROOT_DIR" ] && [ -d "$LOCAL_OPENSSL_ROOT" ]; then
    OPENSSL_ROOT_DIR="$LOCAL_OPENSSL_ROOT"
  fi
  if [ -z "$OPENSSL_ROOT_DIR" ] && command -v brew >/dev/null 2>&1; then
    OPENSSL_ROOT_DIR="$(brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null || true)"
  fi
  cmake_crypto_args+=("-DOPENSSL_USE_STATIC_LIBS=TRUE")
  if [ -n "$OPENSSL_ROOT_DIR" ]; then
    cmake_crypto_args+=("-DOPENSSL_ROOT_DIR=$OPENSSL_ROOT_DIR")
    [ -f "$OPENSSL_ROOT_DIR/lib/libssl.a" ] && cmake_crypto_args+=("-DOPENSSL_SSL_LIBRARY=$OPENSSL_ROOT_DIR/lib/libssl.a")
    [ -f "$OPENSSL_ROOT_DIR/lib/libcrypto.a" ] && cmake_crypto_args+=("-DOPENSSL_CRYPTO_LIBRARY=$OPENSSL_ROOT_DIR/lib/libcrypto.a")
  fi
fi

cmake_linker_args=()
if [ "$LINK_FATAL_WARNINGS" = "1" ]; then
  cmake_linker_args+=("-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-fatal_warnings")
fi

ARCHIVE="$BUILD_ROOT/open62541-$OPEN62541_VERSION.tar.gz"
SOURCE_DIR="$BUILD_ROOT/open62541-$OPEN62541_VERSION"
CMAKE_BUILD_DIR="$BUILD_ROOT/cmake-$OPEN62541_VERSION-macos-$MIN_MACOS_VERSION-$ARCH"

mkdir -p "$BUILD_ROOT"

if [ ! -f "$ARCHIVE" ]; then
  curl --fail --location --output "$ARCHIVE" "$OPEN62541_SOURCE_URL"
fi

actual_sha="$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')"
if [ "$actual_sha" != "$OPEN62541_SHA256" ]; then
  fail "checksum mismatch for $ARCHIVE: expected $OPEN62541_SHA256, got $actual_sha"
fi

rm -rf "$SOURCE_DIR" "$CMAKE_BUILD_DIR" "$PREFIX"
tar -xzf "$ARCHIVE" -C "$BUILD_ROOT"

cmake -S "$SOURCE_DIR" -B "$CMAKE_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS_VERSION" \
  -DBUILD_SHARED_LIBS=ON \
  -DUA_BUILD_EXAMPLES=OFF \
  -DUA_BUILD_UNIT_TESTS=OFF \
  -DUA_ENABLE_AMALGAMATION=OFF \
  "${cmake_linker_args[@]}" \
  "${cmake_crypto_args[@]}"

cmake --build "$CMAKE_BUILD_DIR" --parallel
cmake --install "$CMAKE_BUILD_DIR"

if ! grep -Eq '^#define UA_ENABLE_ENCRYPTION_(OPENSSL|MBEDTLS|LIBRESSL)\b' "$PREFIX/include/open62541/config.h"; then
  fail "built open62541 does not expose encryption support in $PREFIX/include/open62541/config.h"
fi

if [ "$OPEN62541_CRYPTO_BACKEND" = "OPENSSL" ] &&
   otool -L "$PREFIX/lib/libopen62541.dylib" | grep -Eq 'lib(ssl|crypto)\.[0-9].*dylib|/(opt/homebrew|usr/local)/opt/openssl'; then
  otool -L "$PREFIX/lib/libopen62541.dylib" >&2
  fail "built open62541 dynamically links OpenSSL; rebuild with static OpenSSL libraries or bundle OpenSSL explicitly"
fi

mkdir -p "$PREFIX/share/open62541"
cp "$SOURCE_DIR/LICENSE" "$PREFIX/share/open62541/LICENSE"
[ -f "$SOURCE_DIR/LICENSE-CC0" ] && cp "$SOURCE_DIR/LICENSE-CC0" "$PREFIX/share/open62541/LICENSE-CC0"
if [ "$OPEN62541_CRYPTO_BACKEND" = "OPENSSL" ] && [ -n "$OPENSSL_ROOT_DIR" ]; then
  mkdir -p "$PREFIX/share/openssl"
  if [ -f "$OPENSSL_ROOT_DIR/share/openssl/LICENSE.txt" ]; then
    cp "$OPENSSL_ROOT_DIR/share/openssl/LICENSE.txt" "$PREFIX/share/openssl/LICENSE.txt"
  elif [ -f "$OPENSSL_ROOT_DIR/LICENSE.txt" ]; then
    cp "$OPENSSL_ROOT_DIR/LICENSE.txt" "$PREFIX/share/openssl/LICENSE.txt"
  else
    fail "OpenSSL license not found under OPENSSL_ROOT_DIR=$OPENSSL_ROOT_DIR"
  fi
  [ -f "$OPENSSL_ROOT_DIR/share/openssl/NOTICE.txt" ] && cp "$OPENSSL_ROOT_DIR/share/openssl/NOTICE.txt" "$PREFIX/share/openssl/NOTICE.txt"
fi

echo "Built open62541 prefix:"
echo "  $PREFIX"
echo
vtool -show-build "$PREFIX/lib/libopen62541.dylib"
echo
echo "Package with:"
echo "  OPEN62541_PREFIX=\"$PREFIX\" Tools/package_macos_release.sh"
