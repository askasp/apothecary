#!/bin/bash
set -euo pipefail

# Build a clean Burrito release and publish to GitHub.
# Usage:
#   ./release.sh          # auto-bump patch (0.1.0 -> 0.1.1)
#   ./release.sh 0.2.0    # set explicit version

REPO="askasp/apothecary"
MIX_FILE="mix.exs"

# --- Determine version ---
CURRENT=$(grep 'version:' "$MIX_FILE" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -n "${1:-}" ]; then
  VERSION="$1"
else
  # Auto-bump patch
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
  PATCH=$((PATCH + 1))
  VERSION="${MAJOR}.${MINOR}.${PATCH}"
fi

TAG="v${VERSION}"
echo "==> Building release ${TAG} (was ${CURRENT})"

# --- Bump version in mix.exs ---
if [ "$VERSION" != "$CURRENT" ]; then
  sed -i "s/version: \"${CURRENT}\"/version: \"${VERSION}\"/" "$MIX_FILE"
  echo "==> Bumped version in mix.exs to ${VERSION}"
fi

# --- Clean build ---
echo "==> Cleaning build artifacts..."
rm -rf _build/prod burrito_out

echo "==> Building assets..."
MIX_ENV=prod mix assets.deploy

echo "==> Compiling and building Burrito release..."
MIX_ENV=prod mix release

echo "==> Build complete. Binaries:"
ls -lh burrito_out/

# --- Commit version bump ---
if ! git diff --quiet "$MIX_FILE"; then
  git add "$MIX_FILE"
  git commit -m "Bump version to ${VERSION}"
fi

# --- Create GitHub release ---
echo "==> Creating GitHub release ${TAG}..."
gh release create "$TAG" \
  --repo "$REPO" \
  --title "$TAG" \
  --generate-notes \
  burrito_out/apothecary_linux \
  burrito_out/apothecary_linux_aarch64 \
  burrito_out/apothecary_macos \
  burrito_out/apothecary_macos_aarch64

echo "==> Done! Release ${TAG} published."
echo "    https://github.com/${REPO}/releases/tag/${TAG}"
