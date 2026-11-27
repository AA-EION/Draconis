#!/usr/bin/env bash
# Installs the Swift toolchain and GTK 4 headers on Ubuntu 24.04 (CI and
# local Linux builds). Swift goes to /opt/swift and onto GITHUB_PATH/PATH.
set -euo pipefail
VERSION="${SWIFT_VERSION:-6.4.3}"
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev \
  libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config \
  tzdata unzip zlib1g-dev libgtk-4-dev
if [ ! -x /opt/swift/usr/bin/swift ]; then
  url="https://download.swift.org/swift-${VERSION}-release/ubuntu2404/swift-${VERSION}-RELEASE/swift-${VERSION}-RELEASE-ubuntu24.04.tar.gz"
  curl -fsSL "$url" -o /tmp/swift.tar.gz
  sudo mkdir -p /opt/swift
  sudo tar -xzf /tmp/swift.tar.gz -C /opt/swift --strip-components=1
fi
if [ -n "${GITHUB_PATH:-}" ]; then echo /opt/swift/usr/bin >> "$GITHUB_PATH"; fi
/opt/swift/usr/bin/swift --version
