# Build from source

```bash
git clone https://github.com/woolson/VibeGo
cd VibeGo
./build.sh            # builds build/VibeGo.app
./build.sh --dmg      # also produces build/VibeGo.dmg
```
Requires the Xcode Command Line Tools (`xcode-select --install`).

## Sparkle updates without Developer ID

VibeGo can use Sparkle for automatic updates without an Apple Developer ID. In
that mode Sparkle verifies update archives with an EdDSA key and can replace the
app, but macOS still treats the app as an unsigned/unnotarized download. First
install users may need to right-click Open or approve the app in System Settings.

The Sparkle private key is stored in the maintainer's login Keychain. The public
key is stored in `.sparkle-public-ed-key` and injected into `Info.plist` at build
time.

Builds enable Sparkle when both of these exist:

- `vendor/Sparkle/Sparkle.framework`
- `.sparkle-public-ed-key` or `SPARKLE_PUBLIC_ED_KEY`

The default appcast URL is:

```text
https://raw.githubusercontent.com/woolson/VibeGo/main/appcast.xml
```

Override it for testing or a real host:

```bash
SPARKLE_FEED_URL="https://example.com/vibego/appcast.xml" ./build.sh --dmg
```

To publish a Sparkle update:

```bash
DOWNLOAD_URL="https://example.com/releases/VibeGo-0.1.9.dmg" scripts/make-sparkle-release.sh
```

Then upload `build/VibeGo.dmg` to that URL and publish the generated
`appcast.xml` at the feed URL compiled into the previous released app.

---
Back to the [README](../README.md).
