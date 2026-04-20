# macspanso

A macOS menu bar app for managing [espanso](https://espanso.org) text expansion matches — no YAML editing required.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![License: MIT](https://img.shields.io/badge/license-MIT-green)

---

## What it does

espanso is a powerful cross-platform text expander, but its configuration lives in YAML files. macspanso gives you a native macOS GUI to create, edit, search, and organise your matches without touching a text editor.

- **Create matches** — type a trigger, type the replacement, save
- **Form matches** — add `[[placeholders]]` and espanso will show a fill-in popup before expanding
- **Variables** — attach date, shell, clipboard, random, and other variable types to any match
- **Multi-trigger & regex** — one match, many triggers; or match by regular expression
- **File tree view** — see which YAML file each match lives in, browse by file or flat list
- **External edit detection** — banner appears when a file changes outside the app, with reload/keep options
- **Menu bar controls** — enable, disable, or restart espanso without leaving the keyboard

---

## Requirements

- macOS 13 Ventura or later
- [espanso](https://espanso.org/install/mac/) installed and running

---

## Installation

### Homebrew (recommended)

```bash
brew install --cask jeffcaldwellca/tap/macspanso
```

See [docs/distribution.md](docs/distribution.md) for tap setup. Homebrew automatically installs espanso as a dependency if it isn't already present.

### Direct download

Download the latest `.dmg` from the [Releases](../../releases) page, open it, and drag macspanso to your Applications folder.

---

## Building from source

**Prerequisites:** Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/jeffcaldwellca/macspanso.git
cd macspanso
xcodegen generate
open macspanso.xcodeproj
```

Build and run the `macspanso` scheme. The app reads your espanso match directory automatically on launch.

### Running tests

```bash
xcodebuild test -scheme macspanso -destination 'platform=macOS'
```

---

## Usage

macspanso lives in your menu bar. Click the icon to:

| Action | How |
|--------|-----|
| Open match manager | Click **Open Match Manager…** or press ⌘M |
| Create a match | Click **New Match…**, press ⌘N, or press **+** in the match list |
| Edit a match | Select it in the list — the editor opens on the right |
| Delete a match | Select it and press **−** in the toolbar |
| Enable / disable espanso | Toggle **Espanso Enabled** in the menu |
| Restart espanso | Click **Restart Espanso** |

### Match types

**Text replacement** — the trigger expands to a fixed string. Supports variables (date, clipboard, shell output, etc.) referenced as `{{varname}}`.

**Form with placeholders** — the trigger shows a native popup with fill-in fields before expanding. Write the template with `[[fieldname]]` placeholders. Each field can be a plain text input or a dropdown list.

### Search

Type in the search bar at the top of the match list to filter by trigger text, replacement preview, or label.

### File tree

Click the **Files** toggle in the toolbar to switch from a flat list to a tree grouped by YAML file. Useful when you have multiple match files or installed packages.

---

## Project structure

```
macspanso/
  App/          — AppDelegate, entry point, Info.plist
  MenuBar/      — NSStatusItem, menu construction, actions
  Model/        — EspansoMatch, EspansoVar, FormField, MatchFile
  Store/        — EspansoConfigStore (load/save/watch), FileWatcher, EspansoProcessManager
  Utilities/    — YAMLSerializer (Yams wrapper), MatchValidator
  Views/        — SwiftUI views
macspansoTests/ — YAML parsing/serialization and validation unit tests
docs/           — Distribution guide (Homebrew Cask pipeline)
```

---

## Contributing

Bug reports and pull requests are welcome. Please open an issue first for significant changes.

---

## License

MIT — see [LICENSE](LICENSE).
