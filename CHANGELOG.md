# Changelog

## [1.4.0] - 2026-06-10

### Fixed
- **Settings beyond matches no longer deleted on save** — editing a match in a file containing `global_vars:`, `imports:`, or any other top-level key used to silently erase those keys when the file was rewritten. Unmodelled per-match options (`markdown:`, `priority:`, `paste_shortcut:`, app filters, …) were dropped the same way. All YAML the editor doesn't model now survives every save.
- **espanso commands could hang the app** — command output larger than 64 KB (e.g. `espanso log`) deadlocked the process runner, and a missing espanso binary left it blocked forever. Match-directory detection now also times out after 3 seconds and falls back to the default location instead of waiting on a stuck binary.
- **References to global variables blocked saving** — a `{{name}}` referencing a `global_vars:` declaration in another file was flagged as unresolved and disabled the Save button.
- **Regex toggle could write invalid YAML** — switching a multi-trigger match to Regex and back produced both `trigger:` and `triggers:` keys on the same match.
- **Failed saves no longer desync the app** — if a disk write failed, deletes and adds could show state that didn't match the file, and external-edit detection could be silently disabled for the rest of the session. All write paths now keep memory and disk consistent and recover cleanly.
- **Snooze now ends on time after sleep** — sleeping the Mac through a snooze's end time left espanso disabled; expiry is now checked by the regular status poll.
- **Date preview literal text** — formats like `Updated: %Y` or `%d days` no longer mangle literal letters in the preview, and `%%` renders as a literal percent.
- **Backups no longer touch espanso packages** — exports skip `packages/`, and restores never overwrite installed packages, even from older backups that contained them.
- **Window stays visible when switching apps** — the Match Manager no longer hides when macspanso loses focus.
- **Symlinked match directories** — file identity now resolves symlinks, preventing duplicate file entries when the config path goes through a symlink.

### Added
- **`.yaml` support** — match files with the `.yaml` extension are now loaded alongside `.yml`.
- **Live detection in subfolders** — files added or removed inside subdirectories of the match folder are now picked up immediately, not just at the top level.
- **Conflict badges in the match list** — triggers defined in more than one file show an inline warning badge in the main list, not just the file tree.
- **Delete confirmations** — deleting multiple matches at once now asks first.
- **Session safety snapshot** — opening the Match Manager automatically snapshots your match files (rotating, last 10 kept), so any editing session can be rolled back from "Restore from Snapshot".
- **Update check feedback** — "Check for Updates…" now reports up to date, update available, or network failure instead of silently doing nothing.

### Improved
- **Menu freshness** — the menu bar menu rebuilds each time it opens, so the snapshot list and Launch at Login state are always current; stale update checks re-run on open.
- **Release safety** — CI and the release pipeline now run the full test suite (71 tests, up from 43) with per-test timeouts before any build ships.

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
