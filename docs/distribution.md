# Distributing macspanso via Homebrew

macOS GUI apps are distributed through **Homebrew Casks** (not formulas). The full pipeline:

```
Build → Sign → Notarize → Package DMG → Publish GitHub release → Write cask
```

---

## Prerequisites

- Apple Developer account ($99/yr) — required for code signing and notarization
- Your **Developer ID Application** certificate installed in Keychain
- `create-dmg` for packaging: `brew install create-dmg`

Update `project.yml` with your real team ID before archiving:

```yaml
settings:
  base:
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: 88ZPCYS252   # from developer.apple.com
    CODE_SIGN_IDENTITY: "Developer ID Application"
```

Run `xcodegen generate` after changing `project.yml`.

---

## Step 1: Archive and export

```bash
# Archive
xcodebuild archive \
  -scheme macspanso \
  -archivePath build/macspanso.xcarchive

# Export signed .app
xcodebuild -exportArchive \
  -archivePath build/macspanso.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

`ExportOptions.plist` at the repo root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>88ZPCYS252</string>
</dict>
</plist>
```

---

## Step 2: Package as DMG

```bash
create-dmg \
  --volname "macspanso" \
  --window-size 540 380 \
  --app-drop-link 380 160 \
  "build/macspanso-1.0.0.dmg" \
  "build/export/macspanso.app"
```

---

## Step 3: Notarize and staple

Create an app-specific password at [appleid.apple.com](https://appleid.apple.com) (under Security → App-Specific Passwords).

```bash
# Submit for notarization (--wait blocks until Apple responds)
xcrun notarytool submit build/macspanso-1.0.0.dmg \
  --apple-id your-apple-id@example.com \
  --team-id 88ZPCYS252 \
  --password YOUR_APP_SPECIFIC_PASSWORD \
  --wait

# Staple the ticket to the DMG
xcrun stapler staple build/macspanso-1.0.0.dmg

# Get SHA256 — needed for the cask file
shasum -a 256 build/macspanso-1.0.0.dmg
```

---

## Step 4: Publish a GitHub release

1. Tag the commit: `git tag v1.0.0 && git push origin v1.0.0`
2. Create a release on GitHub at that tag
3. Upload `macspanso-1.0.0.dmg` as the release asset

The download URL will be:
```
https://github.com/jeffcaldwellca/macspanso/releases/download/v1.0.0/macspanso-1.0.0.dmg
```

---

## Step 5: Create your Homebrew tap

Create a new **public** GitHub repo named exactly `homebrew-tap`. Inside it, create `Casks/macspanso.rb`:

```ruby
cask "macspanso" do
  version "1.0.0"
  sha256 "paste_shasum_output_here"

  url "https://github.com/jeffcaldwellca/macspanso/releases/download/v#{version}/macspanso-#{version}.dmg"
  name "macspanso"
  desc "macOS GUI for the espanso text expander"
  homepage "https://github.com/jeffcaldwellca/macspanso"

  depends_on cask: "espanso"   # installs espanso automatically if not present

  app "macspanso.app"

  zap trash: [
    "~/Library/Preferences/com.macspanso.plist",
  ]
end
```

The `depends_on cask: "espanso"` line means Homebrew will install espanso before macspanso if it isn't already present.

---

## Installing and upgrading

```bash
# First install
brew install --cask jeffcaldwellca/tap/macspanso

# Upgrade to a new version
brew upgrade --cask macspanso
```

---

## Releasing a new version

1. Bump `CFBundleShortVersionString` in `project.yml`
2. Run through Steps 1–4 above with the new version number
3. In `Casks/macspanso.rb`, update `version` and `sha256`
4. Commit and push the tap repo — Homebrew picks it up immediately

---

## Automating with GitHub Actions (optional)

A release workflow can handle building, notarizing, packaging, and updating the cask SHA automatically whenever you push a version tag. The workflow would need:

- `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` stored as GitHub Actions secrets
- A step that uses `xcrun notarytool` and then commits the updated SHA back to the tap repo

This is worth setting up once you're shipping regularly.
