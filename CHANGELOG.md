# Changelog

All notable changes to RCLootCouncil_PriorityLoot will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).  
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
