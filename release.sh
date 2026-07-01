#!/bin/bash
# Cut a VibeGo release: generate the Sparkle EdDSA keypair (if missing), build the app,
# package it, sign the archive, and write appcast.xml. Run once per release in your terminal.
#
#   ./release.sh
#
# Afterwards: upload build/VibeGo-<version>.zip to the matching GitHub release, then
# commit the regenerated appcast.xml + .sparkle-public-ed-key and push.
set -euo pipefail
cd "$(dirname "$0")"

SPARKLE_DIR="vendor/Sparkle"
SPARKLE_VERSION="2.9.3"
SPARKLE_TAR_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
PUB_KEY=".sparkle-public-ed-key"
PRIV_KEY=".sparkle-private-ed-key"
APP="build/VibeGo.app"

# 1. Ensure the Sparkle framework + tools are present (mirrors build.sh's fetch).
fetch_sparkle() {
  echo "Fetching Sparkle ${SPARKLE_VERSION}…"
  mkdir -p "$SPARKLE_DIR"
  curl -fsSL "$SPARKLE_TAR_URL" -o /tmp/vibego-sparkle.tar.xz
  tar -xJf /tmp/vibego-sparkle.tar.xz -C "$SPARKLE_DIR" --strip-components=1
  rm -f /tmp/vibego-sparkle.tar.xz
  xattr -cr "$SPARKLE_DIR" 2>/dev/null || true   # drop macOS quarantine so tools can run
}
if [[ ! -d "$SPARKLE_DIR/Sparkle.framework" ]]; then fetch_sparkle; fi

# 2. Ensure a Sparkle EdDSA key exists in the Keychain. generate_keys is idempotent — it
#    reuses any existing key, or creates one on first run — and we keep .sparkle-public-ed-key
#    in sync (the build embeds that value as SUPublicEDKey). Signing uses the Keychain key.
echo "Ensuring Sparkle EdDSA key…"
"$SPARKLE_DIR/bin/generate_keys" >/dev/null 2>&1 || true
PUB="$("$SPARKLE_DIR/bin/generate_keys" -p 2>/dev/null | grep -oE '[A-Za-z0-9+/=]{30,}' | head -1)"
if [[ -z "$PUB" ]]; then
  echo "ERROR: no Sparkle EdDSA key in the Keychain. Run this once in an interactive terminal:" >&2
  echo "         $SPARKLE_DIR/bin/generate_keys" >&2; exit 1
fi
if [[ "$(tr -d '[:space:]' < "$PUB_KEY" 2>/dev/null)" != "$PUB" ]]; then
  printf '%s\n' "$PUB" > "$PUB_KEY"
  echo "  synced $PUB_KEY to match the Keychain key (commit this)"
fi

# 3. Build the app (auto-fetches Sparkle, embeds the framework, writes SU keys).
./build.sh

# 4. Read the version straight from the built bundle (single source of truth).
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="build/VibeGo-${VERSION}.zip"
ASSET_URL="https://github.com/woolson/VibeGo/releases/download/${VERSION}/VibeGo-${VERSION}.zip"
echo "Release version: $VERSION"

# 5. Package the app into a zip Sparkle can download and install.
echo "Packaging ${ZIP}…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 6. Sign the archive with the Keychain private key (falls back to a private-key file, e.g. for
#    CI). Clients verify this signature against SUPublicEDKey embedded in the app.
SIG_OUT=""
if SIG_OUT="$("$SPARKLE_DIR/bin/sign_update" "$ZIP" 2>/dev/null)" && [[ -n "$SIG_OUT" ]]; then
  :
elif [[ -f "$PRIV_KEY" ]] && SIG_OUT="$("$SPARKLE_DIR/bin/sign_update" "$ZIP" --ed-key-file "$PRIV_KEY" 2>/dev/null)" && [[ -n "$SIG_OUT" ]]; then
  :
else
  echo "ERROR: signing failed — no usable Keychain key or $PRIV_KEY." >&2; exit 1
fi
SIG="$(printf '%s' "$SIG_OUT" | sed -nE 's/.*edSignature="([^"]*)".*/\1/p')"
LEN="$(printf '%s' "$SIG_OUT" | sed -nE 's/.*length="([^"]*)".*/\1/p')"
if [[ -z "$SIG" || -z "$LEN" ]]; then
  echo "ERROR: could not parse sign_update output:" >&2; printf '%s\n' "$SIG_OUT" >&2; exit 1
fi

# 7. Write the signed appcast entry.
PUBDATE="$(LC_ALL=C date -R)"
cat > appcast.xml <<APPCAST
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>VibeGo</title>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:edSignature>${SIG}</sparkle:edSignature>
      <enclosure url="${ASSET_URL}" length="${LEN}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST

echo ""
echo "✓ Release ${VERSION} ready"
echo "    archive : $ZIP            ← upload to the '${VERSION}' GitHub release"
echo "    appcast : appcast.xml     ← commit + push"
echo "    pub key : $PUB_KEY        ← commit alongside appcast"
echo ""
echo "Next: create the ${VERSION} release on GitHub, attach the zip, then:"
echo "    git add appcast.xml $PUB_KEY && git commit -m 'release ${VERSION}' && git push"
