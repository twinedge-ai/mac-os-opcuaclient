#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

OPENSSL_VERSION="${OPENSSL_VERSION:-3.6.2}"
OPENSSL_SHA256="${OPENSSL_SHA256:-aaf51a1fe064384f811daeaeb4ec4dce7340ec8bd893027eee676af31e83a04f}"
OPENSSL_SOURCE_URL="${OPENSSL_SOURCE_URL:-https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
ARCH="${ARCH:-arm64}"
BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/build/openssl-release}"
PREFIX="${OPENSSL_ROOT_DIR:-$REPO_ROOT/build/openssl-$OPENSSL_VERSION-macos-$MIN_MACOS_VERSION-$ARCH}"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

case "$ARCH" in
  arm64) OPENSSL_TARGET="darwin64-arm64-cc" ;;
  x86_64) OPENSSL_TARGET="darwin64-x86_64-cc" ;;
  *) fail "unsupported ARCH=$ARCH" ;;
esac

require_command curl
require_command make
require_command perl
require_command shasum
require_command tar

ARCHIVE="$BUILD_ROOT/openssl-$OPENSSL_VERSION.tar.gz"
SOURCE_DIR="$BUILD_ROOT/openssl-$OPENSSL_VERSION"

mkdir -p "$BUILD_ROOT"

if [ ! -f "$ARCHIVE" ]; then
  curl --fail --location --output "$ARCHIVE" "$OPENSSL_SOURCE_URL"
fi

actual_sha="$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')"
if [ "$actual_sha" != "$OPENSSL_SHA256" ]; then
  fail "checksum mismatch for $ARCHIVE: expected $OPENSSL_SHA256, got $actual_sha"
fi

rm -rf "$SOURCE_DIR" "$PREFIX"
tar -xzf "$ARCHIVE" -C "$BUILD_ROOT"

(
  cd "$SOURCE_DIR"
  export CFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS_VERSION -O2"
  export LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS_VERSION"
  ./Configure "$OPENSSL_TARGET" \
    no-shared \
    no-tests \
    no-apps \
    --prefix="$PREFIX" \
    --openssldir="$PREFIX/ssl"
  make -j"$(sysctl -n hw.ncpu)"
  make install_sw
)

[ -f "$PREFIX/lib/libssl.a" ] || fail "missing $PREFIX/lib/libssl.a"
[ -f "$PREFIX/lib/libcrypto.a" ] || fail "missing $PREFIX/lib/libcrypto.a"

mkdir -p "$PREFIX/share/openssl"
cp "$SOURCE_DIR/LICENSE.txt" "$PREFIX/share/openssl/LICENSE.txt"
[ -f "$SOURCE_DIR/NOTICE.txt" ] && cp "$SOURCE_DIR/NOTICE.txt" "$PREFIX/share/openssl/NOTICE.txt"

echo "Built OpenSSL prefix:"
echo "  $PREFIX"
echo
echo "Build open62541 with:"
echo "  OPENSSL_ROOT_DIR=\"$PREFIX\" Tools/build_open62541_release.sh"
