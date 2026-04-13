# Setting Up the Homebrew Tap

This is a one-time setup. After this, the release workflow updates the cask automatically.

## 1. Create the tap repo

1. Go to github.com/jeffcaldwellca and create a new **public** repository named exactly `homebrew-tap`
2. Clone it locally:
   ```bash
   git clone https://github.com/jeffcaldwellca/homebrew-tap.git
   cd homebrew-tap
   ```

## 2. Add the cask

Copy `Casks/macspanso.rb` from this repo into the tap:

```bash
mkdir Casks
cp /path/to/macspanso/Casks/macspanso.rb Casks/macspanso.rb
git add Casks/macspanso.rb
git commit -m "Add macspanso cask"
git push
```

The `sha256` and `version` fields are placeholders — the release workflow fills them in automatically when you push a version tag.

## 3. Create the TAP_TOKEN secret

The release workflow needs write access to the tap repo to update the cask SHA on each release.

1. Go to github.com/settings/tokens → **Generate new token (classic)**
2. Name it `macspanso-tap-update`
3. Select the `repo` scope
4. Copy the token

5. In the **macspanso** repo → Settings → Secrets and variables → Actions → **New repository secret**:
   - Name: `TAP_TOKEN`
   - Value: the token you just copied

## 4. Add the other required secrets

In the macspanso repo → Settings → Secrets and variables → Actions, add:

| Secret | Value |
|--------|-------|
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application .p12 (see below) |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the .p12 |
| `KEYCHAIN_PASSWORD` | Any strong password — used for the temporary CI keychain |
| `NOTARIZATION_APPLE_ID` | Your Apple ID email |
| `NOTARIZATION_PASSWORD` | App-specific password from appleid.apple.com |

### Exporting the certificate as base64

In Keychain Access, export your **Developer ID Application** certificate as a `.p12` file, then:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Paste the result as the `MACOS_CERTIFICATE` secret value.

## 5. Ship a release

```bash
# Bump CFBundleShortVersionString in project.yml, then:
xcodegen generate
git add project.yml macspanso.xcodeproj/project.pbxproj
git commit -m "Bump version to 1.0.0"
git tag v1.0.0
git push origin main --tags
```

The release workflow runs automatically, produces a notarized DMG, creates the GitHub Release, and updates `Casks/macspanso.rb` in the tap. Users can then install or upgrade with:

```bash
brew install --cask jeffcaldwellca/tap/macspanso
brew upgrade --cask macspanso
```
