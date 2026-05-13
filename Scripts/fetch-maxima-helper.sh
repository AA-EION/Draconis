#!/bin/bash
# Fetches MaximaHelper.app from the latest AA-EION/Maxima-Draconis release and
# copies it into the built Draconis.app's Resources directory.
#
# We cannot rely on Xcode's "Copy Bundle Resources" phase because the .app
# does not exist at `xcodegen generate` time — with `optional: true`,
# XcodeGen omits the PBX reference and the resource is never copied. So this
# script handles the copy itself, into BUILT_PRODUCTS_DIR.
#
# Caches by tag name — re-downloads only when a new release is published.
set -euo pipefail

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

if [ -n "${BUILT_PRODUCTS_DIR:-}" ] && [ -n "${PRODUCT_NAME:-}" ]; then
    BUNDLE_RESOURCES="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
    mkdir -p "$BUNDLE_RESOURCES"
    rm -rf "$BUNDLE_RESOURCES/MaximaHelper.app"
    cp -R "$CACHE_DIR" "$BUNDLE_RESOURCES/MaximaHelper.app"
    echo "==> MaximaHelper copied into ${BUNDLE_RESOURCES}/MaximaHelper.app"
else
    echo "==> BUILT_PRODUCTS_DIR not set; skipping bundle copy (cache-only run)."
fi
