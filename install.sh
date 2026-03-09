#!/bin/bash
set -euo pipefail

REPO="askasp/apothecary"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [ "$OS" = "darwin" ] && [ "$ARCH" = "arm64" ]; then
  BINARY="apothecary_macos_aarch64"
elif [ "$OS" = "darwin" ]; then
  BINARY="apothecary_macos"
elif [ "$OS" = "linux" ] && [ "$ARCH" = "aarch64" ]; then
  BINARY="apothecary_linux_aarch64"
elif [ "$OS" = "linux" ]; then
  BINARY="apothecary_linux"
else
  echo "Unsupported platform: $OS $ARCH" >&2
  exit 1
fi

URL="https://github.com/${REPO}/releases/latest/download/${BINARY}"

echo "Downloading apothecary for ${OS}/${ARCH}..."
curl -fSL "$URL" -o apothecary
chmod +x apothecary

if [ -w "$INSTALL_DIR" ]; then
  mv apothecary "$INSTALL_DIR/apothecary"
else
  echo "Moving to ${INSTALL_DIR} (requires sudo)..."
  sudo mv apothecary "$INSTALL_DIR/apothecary"
fi

echo "Installed apothecary to ${INSTALL_DIR}/apothecary"
