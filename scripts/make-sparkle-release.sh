#!/bin/bash
# Builds the current DMG and writes appcast.xml for Sparkle.
#
# Usage:
#   DOWNLOAD_URL="https://example.com/VibeGo-0.1.9.dmg" scripts/make-sparkle-release.sh
#   scripts/make-sparkle-release.sh "https://example.com/VibeGo-0.1.9.dmg" build/VibeGo.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

DOWNLOAD_URL="${1:-${DOWNLOAD_URL:-}}"
ARCHIVE="${2:-build/VibeGo.dmg}"
SPARKLE_SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-vendor/Sparkle/bin/sign_update}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-}"

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "Missing download URL."
  echo "Pass it as the first argument or set DOWNLOAD_URL=..."
  exit 1
fi

if [[ ! -x "$SPARKLE_SIGN_UPDATE" ]]; then
  echo "Missing Sparkle sign_update tool at $SPARKLE_SIGN_UPDATE"
  echo "Install Sparkle into vendor/Sparkle first."
  exit 1
fi

./build.sh --dmg

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Archive not found: $ARCHIVE"
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/VibeGo.app/Contents/Info.plist)"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/VibeGo.app/Contents/Info.plist)"
SIGN_ARGS=()
if [[ -n "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  SIGN_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi
# ${ARR[@]+"${ARR[@]}"} — not "${ARR[@]}": the latter trips "unbound variable"
# under `set -u` on bash 3.2 (macOS's stock /bin/bash) when the array is empty,
# which is the default path (no SPARKLE_PRIVATE_KEY_FILE → key from keychain).
SIGNATURE_AND_LENGTH="$("$SPARKLE_SIGN_UPDATE" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$ARCHIVE" | awk '/sparkle:edSignature=/ { print }')"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>VibeGo Updates</title>
    <link>https://github.com/woolson/VibeGo</link>
    <description>VibeGo app updates</description>
    <language>en</language>
    <item>
      <title>VibeGo ${VERSION}</title>
      <sparkle:version>${BUILD_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url="${DOWNLOAD_URL}"
        ${SIGNATURE_AND_LENGTH}
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

echo "Wrote appcast.xml for VibeGo $VERSION"
echo "Upload $ARCHIVE to:"
echo "  $DOWNLOAD_URL"
echo "Commit or publish appcast.xml at the URL configured by SPARKLE_FEED_URL."
