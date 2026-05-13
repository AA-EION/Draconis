#!/bin/bash
# Fetches MaximaHelper.app from the latest AA-EION/Maxima-Draconis release.
# Caches by tag name — re-downloads only when a new release is published.
# Run automatically as a pre-build phase by Xcode.
set -euo pipefail

DEST="${SRCROOT}/Draconis/Resources/MaximaHelper.app"
CACHE_TAG_FILE="${SRCROOT}/Draconis/Resources/.maxima_helper_version"
API_URL="https://api.github.com/repos/AA-EION/Maxima-Draconis/releases/latest"

echo "==> Checking latest Maxima-Draconis release…"

RELEASE=$(curl -sf \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: Draconis-Build" \
    "$API_URL")

LATEST_TAG=$(echo "$RELEASE" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['tag_name'])")

DOWNLOAD_URL=$(echo "$RELEASE" | python3 -c \
    "import sys,json; assets=json.load(sys.stdin)['assets']; \
     print(next(a['browser_download_url'] for a in assets if a['name']=='MaximaHelper.zip'))")

CACHED_TAG=""
if [ -f "$CACHE_TAG_FILE" ]; then
    CACHED_TAG=$(cat "$CACHE_TAG_FILE")
fi

if [ "$CACHED_TAG" = "$LATEST_TAG" ] && [ -d "$DEST" ]; then
    echo "==> MaximaHelper already at $LATEST_TAG — skipping download."
    exit 0
fi

echo "==> Downloading MaximaHelper $LATEST_TAG…"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -sL "$DOWNLOAD_URL" -o "$TMP/MaximaHelper.zip"
rm -rf "$DEST"
unzip -q "$TMP/MaximaHelper.zip" -d "$TMP"
cp -R "$TMP/MaximaHelper.app" "$DEST"
echo "$LATEST_TAG" > "$CACHE_TAG_FILE"
echo "==> MaximaHelper $LATEST_TAG installed at $DEST"
