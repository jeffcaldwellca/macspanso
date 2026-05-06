# Changelog

## [1.3.5] - 2026-05-06

### Fixed
- **Match Manager window invisible after display changes** — when docking, undocking, or disconnecting an external monitor, opening Match Manager from the menu bar could fail silently because the window was being restored at coordinates no longer covered by any screen. The window now recenters if its frame doesn't intersect a visible screen.
- **Match Manager window stuck on another Space** — the panel now follows you to the active Space instead of staying on whichever Space it was last opened on.

## [1.3.0] - 2026-05-05

### Added
- **Duplicate match** — context menu and ⌘D create a copy with an auto-suffixed trigger.
- **Move match between files** — "Move to" submenu in row context menu, with atomic write and rollback on failure.
- **Choose destination file** — when creating a new match, pick which `.yml` file it lands in. New File… prompts a save panel. Last-used destination is remembered.
- **Live expansion preview** — read-only preview pane below the replacement field resolves date, echo, clipboard, and random variables. Shell and script values render as safe placeholders without executing.
- **Quick switcher (⌘P)** — Spotlight-style fuzzy finder over all triggers, labels, and replacements. Arrow keys to navigate, Enter to jump.
- **Empty-state onboarding** — first-run experience with starter chips for signature, current date, and clipboard paste.
- **Sort options** — flat list can sort by file order, trigger A→Z, or trigger Z→A. Choice persists.
- **Search filter chips** — filter by All / Text / Form / Regex / Vars; combines with search text.
- **Match counts** — toolbar shows total matches and current filtered count.
- **Reorder alternate triggers** — up/down arrows reorder triggers within a multi-trigger match.
- **Regex tester** — when regex mode is on, a test-input field shows live match results.
- **Multi-select operations** — ⌘-click and shift-click to select many matches; bulk-action panel offers Delete All and Move to.
- **Snooze espanso** — temporarily disable for 15 min, 1 hour, 4 hours, or until tomorrow. State persists across launches and the menu header reflects the snooze window.
- **Cross-file conflict detection** — duplicate triggers spanning multiple files now show a badge in the file tree and a Conflicts section in Diagnostics.
- **Espanso log viewer** — live tail of `espanso log` with auto-refresh and error highlighting, accessible from About.
- **Versioned auto-backups** — destructive imports and snapshot restores automatically snapshot the current state first. "Restore from Snapshot" submenu lists the last 10.
- **App Intents** — Toggle Espanso, Restart Espanso, Snooze Espanso, and New Match From Clipboard intents are now available in Shortcuts.app, Spotlight, and Siri.

### Improved
- **Stable match identity** — selection now survives external file edits. When a file is reloaded, UUIDs are re-associated to existing matches by trigger so the editor stays open on the same match.
- **Match list rows** — regex matches now show a `regex` badge alongside the existing `form` badge.

## [1.2.0] - 2026-04-20

### Fixed
- **About screen** — version number now correctly reflects the current release; app icon displayed at full resolution instead of the low-res menu bar icon.

### Improved
- **About screen** — added a Website link (`jeffcaldwellca.github.io/macspanso`) alongside the existing GitHub and espanso.org links.
- **Form match editor** — the template field now has a "Template" section label and an inline placeholder hint (`e.g. Hello [[name]], your email is [[email]]`) so it is clear where to type. A descriptive caption explains the `[[placeholder]]` syntax. When no placeholders have been added yet, a guidance message is shown where the field cards will appear.

## [1.1.0] - 2026-04-14

### Added
- **Launch at Login** — toggle macspanso to start automatically at login from the menu bar. The setting integrates with System Settings › General › Login Items.
- **Backup & Restore** — export all espanso matches to a `.macspanso` backup file and restore them on any machine. Import supports two modes: *Merge* (adds backup matches alongside existing ones) or *Replace* (replaces existing matches with the backup).
- **Clipboard shortcut** — quickly insert clipboard contents via an espanso match shortcut.

## [1.0.0] - 2026-03-01

Initial release.
