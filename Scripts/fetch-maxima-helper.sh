#!/bin/bash
# Fetches MaximaHelper.app from the latest AA-EION/Maxima-Draconis release
# into Draconis/Resources/. Must run BEFORE `xcodegen generate` so XcodeGen
# sees the .app at project generation time and adds it as a regular Copy
# Bundle Resources entry — that way xcodebuild's CodeSign phase signs the
# helper coherently with the parent app (sealed Info.plist, valid parent
# seal, etc.).
#
# Caches by tag name — re-downloads only when a new release is published.
set -euo pipefail

# Default SRCROOT to this script's parent dir so it works standalone
# (./bootstrap.sh, CI pre-build step) and as a build phase.
: "${SRCROOT:=$(cd "$(dirname "$0")/.." && pwd)}"

CACHE_DIR="${SRCROOT}/Draconis/Resources/MaximaHelper.app"
CACHE_TAG_FILE="${SRCROOT}/Draconis/Resources/.maxima_helper_version"
API_URL="https://api.github.com/repos/AA-EION/Maxima-Draconis/releases/latest"

echo "==> Checking latest Maxima-Draconis release..."

if [ -n "${GH_TOKEN:-}" ]; then
    RELEASE=$(curl -sf \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: Draconis-Build" \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        "$API_URL") || { echo "ERROR: GitHub API request failed (authenticated)" >&2; exit 1; }
else
    RELEASE=$(curl -sf \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: Draconis-Build" \
        "$API_URL") || { echo "ERROR: GitHub API request failed (unauthenticated — set GH_TOKEN to avoid rate limits)" >&2; exit 1; }
fi

LATEST_TAG=$(echo "$RELEASE" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['tag_name'])") \
    || { echo "ERROR: Failed to parse release tag from API response" >&2; exit 1; }

DOWNLOAD_URL=$(echo "$RELEASE" | python3 -c \
    "import sys,json; assets=json.load(sys.stdin)['assets']; \
     print(next(a['browser_download_url'] for a in assets if a['name']=='MaximaHelper.zip'))") \
    || { echo "ERROR: MaximaHelper.zip not found in release assets" >&2; exit 1; }

CACHED_TAG=""
if [ -f "$CACHE_TAG_FILE" ]; then
    CACHED_TAG=$(cat "$CACHE_TAG_FILE")
fi

if [ "$CACHED_TAG" = "$LATEST_TAG" ] && [ -d "$CACHE_DIR" ]; then
    echo "==> MaximaHelper already cached at ${LATEST_TAG}."
else
    echo "==> Downloading MaximaHelper ${LATEST_TAG}..."
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    curl -sL "$DOWNLOAD_URL" -o "$TMP/MaximaHelper.zip"
    rm -rf "$CACHE_DIR"
    unzip -q "$TMP/MaximaHelper.zip" -d "$TMP"
    cp -R "$TMP/MaximaHelper.app" "$CACHE_DIR"
    echo "$LATEST_TAG" > "$CACHE_TAG_FILE"
    echo "==> MaximaHelper ${LATEST_TAG} cached at ${CACHE_DIR}"
fi

# Re-sign the cached helper so its Info.plist is sealed into the signature.
# The upstream MaximaHelper.zip ships linker-signed only (`Info.plist=not
# bound`, `Sealed Resources=none`), and LaunchServices won't honor the
# qrc:// CFBundleURLTypes claim from an unsealed Info.plist. xcodebuild will
# pick this signed copy up as a bundle resource and re-seal it again as part
# of the parent app's signature.
codesign --force --deep --sign - "$CACHE_DIR" >/dev/null
echo "==> MaximaHelper ready at ${CACHE_DIR} (Info.plist sealed)"
