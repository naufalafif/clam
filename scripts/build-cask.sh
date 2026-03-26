#!/bin/bash
set -euo pipefail

# Generates and pushes a Homebrew cask for Clam
# Expects: VERSION, SHA256, TAP_TOKEN env vars

VERSION="${VERSION:-}"
SHA256="${SHA256:-}"
TAP_TOKEN="${TAP_TOKEN:-}"

[ -z "$VERSION" ] && { echo "VERSION required"; exit 1; }
[ -z "$SHA256" ] && { echo "SHA256 required"; exit 1; }
[ -z "$TAP_TOKEN" ] && { echo "TAP_TOKEN required"; exit 1; }

REPO="naufalafif/homebrew-tap"
CASK_FILE="Casks/clam.rb"
DOWNLOAD_URL="https://github.com/naufalafif/clam/releases/download/${VERSION}/Clam.zip"

CASK=$(cat <<EOF
cask "clam" do
  version "${VERSION#v}"
  sha256 "${SHA256}"

  url "${DOWNLOAD_URL}"
  name "Clam"
  desc "Native macOS menu bar app for managing Claude Code sessions"
  homepage "https://github.com/naufalafif/clam"

  app "Clam.app"
end
EOF
)

# Push to tap repo
TMPDIR=$(mktemp -d)
git clone "https://x-access-token:${TAP_TOKEN}@github.com/${REPO}.git" "$TMPDIR/tap"
mkdir -p "$TMPDIR/tap/Casks"
echo "$CASK" > "$TMPDIR/tap/$CASK_FILE"
cd "$TMPDIR/tap"
git config user.email "actions@github.com"
git config user.name "GitHub Actions"
git add "$CASK_FILE"
git commit -m "chore: update clam to ${VERSION}"
git push
rm -rf "$TMPDIR"
echo "Homebrew cask updated for ${VERSION}"
