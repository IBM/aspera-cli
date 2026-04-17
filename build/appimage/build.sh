#!/usr/bin/env bash
# This script runs inside the container to build Ruby and create the AppImage
set -euo pipefail
APP_PATH="$1"
OUTPUT_PATH="$2"
RUBY_VERSION="$3"
ARCH="$4"

# Build directory for Ruby compilation (inside container, not persisted)
BUILD_DIR="/tmp/build"
mkdir -p "$BUILD_DIR"

apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
build-essential \
wget \
libssl-dev \
libreadline-dev \
zlib1g-dev \
libyaml-dev \
libffi-dev \
squashfs-tools \
libfuse2 \
libglib2.0-0 \
libglib2.0-dev

echo "== Building Ruby $RUBY_VERSION =="
pushd "$BUILD_DIR"
wget -q https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz
tar xf ruby-${RUBY_VERSION}.tar.gz
pushd ruby-${RUBY_VERSION}
./configure --prefix="$APP_PATH/usr" --disable-install-doc
make -j$(nproc)
make install
popd
popd

echo "== Installing aspera-cli =="
export GEM_HOME="$APP_PATH/usr/lib/gems"
export GEM_PATH="$GEM_HOME"
"$APP_PATH/usr/bin/gem" install aspera-cli --no-document

echo "== Copying system libraries =="
mkdir -p "$APP_PATH/usr/lib"
cp -P /usr/lib/${ARCH}-linux-gnu/libssl.so* "$APP_PATH/usr/lib/" || true
cp -P /usr/lib/${ARCH}-linux-gnu/libcrypto.so* "$APP_PATH/usr/lib/" || true
cp -P /usr/lib/${ARCH}-linux-gnu/libyaml-*.so* "$APP_PATH/usr/lib/" || true

echo "== Building AppImage =="
pushd "$BUILD_DIR"
wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage
chmod +x appimagetool-${ARCH}.AppImage
./appimagetool-${ARCH}.AppImage --appimage-extract-and-run "$APP_PATH" "${OUTPUT_PATH}"
popd

rm -fr "$BUILD_DIR"
echo "== Done =="
