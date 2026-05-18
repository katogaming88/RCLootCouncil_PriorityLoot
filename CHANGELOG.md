# Changelog

All notable changes to RCLootCouncil_PriorityLoot will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).  
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.1.14] - 2026-05-10

### Added

- **Award tracking** — when the ML awards an item via RCLootCouncil, that player's priority column and loot frame overlay for that specific item switches from their ranked position to `Awarded` (grey). Rankings for other items are unaffected. This lets you see at a glance who still needs loot without touching the spreadsheet between raids.
- Award history persists across sessions and is cleared automatically on a fresh import, so it tracks the full season without manual housekeeping.
- `/rcpl awards` — open a scrollable window listing every award recorded this season, grouped by item. Each recipient has a checkbox; selecting one or more and clicking **Remove Award** unmarks them immediately without closing the window.
- `/rcpl award <PlayerName-Realm> <shift-click item>` — manually record an award (for non-ML clients or corrections).
- `/rcpl unaward <PlayerName-Realm> <shift-click item>` — remove a recorded award.

---

## [0.1.13] - 2026-05-08

### Fixed

- `Core.lua` - removed the duplicate `Log.info` chat line that fired alongside the orange out-of-date warning at line 107. Demoted to `Log.debug` so the diagnostic still records into the `/rcpl log` ring buffer but only mirrors to chat when `/rcpl debug on` is set. Behind-version players now see exactly one warning line on login or `/reload` instead of two adjacent lines repeating the same information. Every other diagnostic in `OnVersionReceived`, `BroadcastVersion`, and `OnVersionCheckMessage` already used `Log.debug`; this was the only `Log.info` call in the codebase and the level mismatch is what produced the duplicate.

---

## [0.1.12] - 2026-05-08

### Changed

- **Breaking**: SavedVariable renamed from `RCLPriorityDB` to `RCPL_DB` (declared in `.toc`). Existing saved data will not carry over — re-import priority data after updating.
- Internal identifier renames across all files (no behaviour change): `RCLPAddon` → `RCPLAddon` (`Core.lua`, `Modules/lootFrame.lua`, `Modules/votingFrame.lua`); `RCLPVotingFrame` → `RCPLVotingFrame` (`Modules/votingFrame.lua`); `RCLPPrioPreviewFrame` / `RCLPPrioScrollFrame` → `RCPLPrioPreviewFrame` / `RCPLPrioScrollFrame` (`Modules/prioPreviewFrame.lua`).

---

## [0.1.11] - 2026-05-08

### Fixed

- `Modules/log.lua`, `Core.lua`, `docs/ROADMAP.md` - chat-log prefix corrected from `[RCLP]` to `[RCPL]` so it matches the addon's actual abbreviation (RC + PL). Missed in the v0.1.7 internal rename and the v0.1.8 `/rclp` typo sweep. Affects the central `PREFIX` constant in the logger module and six hardcoded `print()` strings in `Core.lua`'s slash-command handlers (`log show`, `log dump`, `log clear`, `log` help text, `debug` toggle, unknown-command error).

---

## [0.1.10] - 2026-05-08

### Fixed

- `Core.lua` - replies to a guild version broadcast now go directly to the broadcaster as a WHISPER on the `RCPL_Ver` AceComm prefix, instead of being broadcast back on GUILD where every other guildmate would see them and treat each one as a fresh broadcast that needed another reply. The previous design used a per-session `hasRepliedToOthers` boolean to break that loop, but the boolean also blocked every reply after the first one per session, so any guildmate who had already replied to one earlier broadcast would silently ignore every subsequent broadcast (including the same player reloading). The orange `out of date` warning therefore never fired for the player who needed it most: the one who just logged in or just reloaded. WHISPER replies only reach the original broadcaster, so no dedup is needed and every load (login or `/reload`) gets a fresh round of replies from every online guildmate.
- `Core.lua` - `OnVersionReceived` skips the reply path when the incoming `distribution` is `WHISPER` (that is our own whisper coming back) and guards against nil or empty `sender` strings from malformed comm packets.

---

## [0.1.9] - 2026-05-08

### Fixed

- `Core.lua` - `RCPL_VERSION` constant was not bumped alongside `.toc` in v0.1.8, causing `/rcpl version` to report the wrong version in-game.

---

## [0.1.8] - 2026-05-08

### Fixed

- `docs/ROADMAP.md`, `Modules/importFrame.lua`, `Modules/prioPreviewFrame.lua` - corrected `/rclp` typo to `/rcpl` in section 2.5 of the roadmap, the importFrame header comment, and two in-game help strings.

---

## [0.1.7] - 2026-05-08

### Added

- `Modules/log.lua` - centralised logger with `debug`, `info`, `warn`, `error` levels. Every call records into a 500-entry in-memory ring buffer regardless of debug state; `debug` calls only mirror to chat when debug mode is on. The buffer is volatile and resets on `/reload`.
- `Core.lua` - `/rcpl debug` toggles the persisted `RCLPriorityDB.debug` flag (also accepts `on`/`off`/`1`/`0`). Without arguments it flips the current state and prints the new value.
- `Core.lua` - `/rcpl log` opens an AceGUI window with the full log; falls back to a chat dump when AceGUI is unavailable. `/rcpl log dump` prints the buffer to chat directly. `/rcpl log clear` empties the buffer.
- `Core.lua` - diagnostic `Log.debug` calls inside the lifecycle (`OnInitialize`, `OnEnable`) and the comm hooks (`BroadcastVersion`, `OnVersionReceived`, `OnVersionCheckMessage`). Enable `/rcpl debug on` to see whether the version-check broadcast is firing, what `IsInGuild()` returned, what comm prefixes registered, and what messages arrived from each sender.
- `spec/log_spec.lua` - covers level gating against the `RCLPriorityDB.debug` flag, ring-buffer cap behaviour, format-string handling, and the persisted toggle round trip.

### Changed

- `Core.lua` - slash command help table reformatted to drop the em-dash separators in favour of plain spacing, so the printed list reads consistently with the other addon prefixes the user already sees in chat.
- `RCLootCouncil_PriorityLoot.toc` - `Modules/log.lua` added to the load order ahead of `Core.lua` so every downstream file can call `RCPL_Log` safely.
- Renamed internal `RCLPL` prefix to `RCPL` throughout (`RCLPL_Data_*` → `RCPL_Data_*`, `RCLPL_Show*` → `RCPL_Show*`, `RCLPL_Log` → `RCPL_Log`, etc.). No behaviour change.

### Fixed

- `README.md` - removed stale `SpreadsheetExport.gs` reference from the File Structure section. The script was deleted from the repo in v0.1.3 (PR #3) but the README never caught up. Officers still run the script inside the Google Sheet itself; it is not bundled with the addon.
- `README.md` - Slash Commands table now lists `/rcpl version`, `/rcpl debug`, and `/rcpl log` alongside the existing entries.

---

## [0.1.6] - 2026-05-08

### Added

- `Core.lua` — `/rcpl version` slash command (aliases: `ver`, `v`) queries raid/party members for their installed addon version. Sends a request via AceComm on the `RCPL_Chk` prefix, collects responses for 10 seconds, then prints a colour-coded table: green = current, yellow = outdated, orange = newer than you, grey = not installed.

### Fixed

- `Core.lua` — `OnEnable` was never firing because RCLootCouncil sets `defaultModuleState = false` for all sub-modules. Added `RCLPAddon:SetEnabledState(true)` immediately after `NewModule`. This was silently preventing the guild version-check broadcast from ever running since v0.1.4.

---

## [0.1.5] - 2026-05-05

### Fixed

- `Modules/lootFrame.lua` — rewrote hook to match the actual RCLootCouncil loot frame structure. Now hooks `RCLootFrame.EntryManager:GetEntry` (fires per-item as each entry is set up) instead of `Update` (fired only once on open). Extracts itemID via pattern match on the item link rather than `C_Item.GetItemInfoInstant` to avoid cache-miss failures.
- `Modules/lootFrame.lua` — overlay now correctly appears. `UpdateEntry` was reading `entry.item`, which is `nil` when the `GetEntry` hook fires (assigned inside `entry:Update(item)`, called within `GetEntry`). The hook now passes the `item` parameter directly.
- `Modules/lootFrame.lua` — player name is now realm-qualified (`UnitName("player") .. "-" .. GetRealmName()`) to match the `Playername-Realm` keys stored in `RCLPriorityDB`.

### Changed

- `Modules/lootFrame.lua` — priority overlay on the loot frame now shows `Prio: 1st`, `Prio: 7th`, etc. so the label is self-explanatory without surrounding context. The voting frame column continues to show bare ordinals (`1st`, `2nd`) since the column header already reads `Priority`.
- `Modules/lootFrame.lua` — secondary-slot items (cloak, bracers, belt, boots) now show nothing on the loot frame instead of the raw wowaudit deferral message.
- `Modules/lootFrame.lua` — priority overlay repositioned to centered below the full loot frame row.

---

## [0.1.4] - 2026-05-04

### Added

- `Core.lua` — guild version-check broadcast: 5 seconds after login the addon announces its version to the GUILD channel via AceComm-3.0. When a guildmate's broadcast carries a higher version, a one-time orange chat message names the sender, their version, your version, and the GitHub repo URL. The addon also replies once when it first receives any guildmate's broadcast, so players already online see your version even when they logged in before you.

---

## [0.1.3] - 2026-05-04

### Fixed

- `Modules/importFrame.lua` — `/rcpl import` now opens the window on the first invocation. `CreateFrame` returns a frame that is visible by default; the frame was being immediately hidden because `IsShown()` returned true before the caller could toggle it. Added `f:Hide()` at the end of `CreateImportFrame` so the lazy-created frame starts hidden.
- `Modules/importFrame.lua` — import window frame strata raised from the default `MEDIUM` to `DIALOG`, matching WoW's built-in dialog level so the window renders above the voting and loot frames.

---

## [0.1.2] - 2026-05-01

**Shield/holdable slot support, slash command rename, and docs clarification.** No import-format changes.

### Added

- `Data/db.lua` — `INVTYPE_SHIELD` and `INVTYPE_HOLDABLE` added to `CORE_EQUIPLOC`, both mapping to the `oh` slot. Shields and held-in-off-hand items are now resolved correctly instead of falling through to wowaudit deferral.

### Changed

- `README.md` — Added Priority Google Sheet row to the Requirements table; notes it is required for officers and that a public template is not yet available. Updated Weekly Officer Workflow step 1 to reference the sheet explicitly.
- `Core.lua`, `README.md`, `SpreadsheetExport.gs` — Slash command renamed from `/rclp` to `/rcpl` to correctly abbreviate `RCLootCouncil_PriorityLoot` (RC + PL). `SLASH_RCLP1` → `SLASH_RCPL1`, `SlashCmdList["RCLP"]` → `SlashCmdList["RCPL"]`.

---

## [0.1.1] - 2026-04-30

**Phase 0 foundation: lint, tests, CI, contribution docs.** No runtime behaviour change to the addon. Sets up the development infrastructure for future feature work.

### Added

- `docs/ROADMAP.md` - right-sized phased plan: Phase 0 (foundation, this release), Phase 1 (hardening: strict import validation, centralised logging, idempotent import), Phase 2 (tooltip integration, slash UX), Phase 3 (tier-set awareness, RCLootCouncil award integration), Phase 4 (CurseForge publishing). Maybe section parks four lower-signal items for explicit signal. Branching, commit, and release conventions live alongside.
- `docs/SETUP.md` - per-platform dev-environment recipe (Linux, macOS, Windows + MSYS2/Git Bash) for Lua 5.1, LuaRocks, luacheck, and busted, with verification commands and a troubleshooting block for the common Windows traps.
- `CONTRIBUTING.md` - branch and commit conventions, version-bump rules, PR checklist, branch-protection summary, stacked-PR rebase recipe, style notes.
- `.github/PULL_REQUEST_TEMPLATE.md` - auto-populates new PRs with the contribution checklist.
- `.github/ISSUE_TEMPLATE/{bug_report.md, feature_request.md, config.yml}` - structured intake; routes RCLootCouncil-host bugs to the upstream tracker.
- `.luacheckrc` - Lua 5.1 std, WoW + Ace3 globals whitelisted, project globals listed, vendored `Libs/` excluded.
- `.busted` - busted runner config (verbose, `spec/` root, `*_spec.lua` pattern, `LUA_PATH` includes repo root).
- `spec/wow_mocks.lua`, `spec/data_db_spec.lua`, `spec/import_save_spec.lua` - 29 specs covering `RCLPL_Data_GetPlayerPriority`, `RCLPL_Data_SaveImportedData`, and `RCLPL_Data_ResetData`. Item-centric and player-centric resolution paths, every rank colour, secondary-slot wowaudit deferral, multi-key slots (ring/trinket), full weapon equipLoc family, input validation, count returns, prior-state wipe, importedAt stamp.
- `scripts/run_tests.sh` - busted wrapper that sets `LUA_PATH` correctly on Windows/MSYS2 (LuaRocks `.bat` shims are unreliable in Git Bash).
- `.github/workflows/ci.yml` - CI pipeline with `Lint (luacheck)` and `Test (busted)` jobs. Both use `leafo/gh-actions-lua@v10` (pinned to Lua 5.1) and `leafo/gh-actions-luarocks@v4`. Run on every push and PR to `main`.
- `README.md` - CI + license badges, Development section (linter + tests setup), Roadmap link, Contributing link.

### Changed

- `.github/workflows/release.yml` - rsync excludes broadened to cover `docs/`, `spec/`, `scripts/`, `.vscode/`, `.idea/`, `.luacheckrc`, `.busted`. Added a post-rsync `find` sanity check that fails the build if any file outside the expected ship-set (`.toc`, `Core.lua`, `LICENSE`, `Data/`, `Modules/`, `Libs/`) ends up in the zip. Long-term defence against orphan-file regressions.
- `.gitignore` - expanded to cover common IDE and OS artefacts (`.vscode/`, `.idea/`, `*.swp`, `*~`, `.DS_Store`, `dist/`).

### Fixed

- `Modules/lootFrame.lua:65` - dropped an unused `err` capture from a pcall destructure (lint cleanup, no behaviour change).

### Removed

- Root-level `Data.lua`, `Import.lua`, `UI.lua` - v0.0.1 versions superseded by `Data/db.lua` and `Modules/*.lua` in v0.1.0 but never deleted. The `.toc` did not load them, so removal is behaviour-neutral. Cuts about 480 lines of dead code from the release zip.

---

## [0.1.0] – 2026-04-30

### Added

- `Modules/prioPreviewFrame.lua` — new `/rclp prio` slash command opens a draggable, scrollable popup showing all imported priority lists (item name + ranked player order) and the full player roster; toggles on repeat invocation; mousewheel scrolling supported.
- `Core.lua` — registered `prio` subcommand in the slash handler and updated the `/rclp` help text.

### Changed

- `SpreadsheetExport.gs` — combined into a single "Team Phoenix" script:
  - **Priority Order dropdowns** — new menu items to fill player dropdown validation lists on individual rows or all rows at once, based on who has the item in their BiS List.
  - **WCL performance scores** — fetches ilvl-adjusted bracket percentages from Warcraft Logs for the last N reports; writes a *Recent Score* (last 2 reports) and *Trend Score* (last 8 reports) to the Roster & Scoring sheet with colour-coded trend direction.
  - **Commit draft scores** — copies Recent Scores into the permanent Performance column after officer review.
  - `Utilities.Charset.UTF_8` passed explicitly to `base64Encode` to ensure accented characters in player names survive the encode/decode round-trip.

---

## [0.0.1] – 2026-04-27

### Added

- Initial release targeting WoW patch 12.0.5 (Midnight).
- `Core.lua` — addon skeleton using AceAddon-3.0 / AceEvent-3.0 / AceHook-3.0; PLAYER_LOGIN guard ensures RCLootCouncil is present before any hooks are registered; `/rclp import` and `/rclp reset` slash commands.
- `Data.lua` — `RCLPL_Data_GetPlayerPriority()` resolves BiS rank (core slots) or Droptimizer % gain (secondary slots) from `RCLPriorityDB`; `RCLPL_Data_SaveImportedData()` normalises decoded JSON into SavedVariables; `RCLPL_Data_ResetData()` wipes stored data.
- `Import.lua` — in-game import window (scrollable EditBox + Confirm button); pure-Lua Base64 decoder using WoW's `bit.*` API; JSON parsed via bundled LibJSON; player count printed on success.
- `UI.lua` — injects a sortable *Priority* column into `votingFrame.scrollCols`; hooks `SwitchSession` to track the active item; `SetCellPriority` DoCellUpdate callback colours text green / yellow / orange by rank or percentage.
- `LootFrame.lua` — hooks the loot frame's update method (tries `Update`, `UpdateItems`, `Show`, `OnShow` in order); appends a coloured `FontString` overlay beneath each item button for the local player; N/A entries display nothing to avoid clutter.
- `Libs/LibJSON.lua` — bundled pure-Lua JSON decoder (based on rxi/json.lua, MIT); no `require` / `io` / `os` dependencies; exposed as `LibRCLPJSON` global.
- `RCLPriorityDB` SavedVariable declared in `.toc`; persists across sessions automatically.
