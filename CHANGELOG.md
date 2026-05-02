# Changelog

All notable changes to RCLootCouncil_PriorityLoot will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).  
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
