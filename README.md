# RCLootCouncil – PriorityLoot

[![CI](https://github.com/katogaming88/RCLootCouncil_PriorityLoot/actions/workflows/ci.yml/badge.svg)](https://github.com/katogaming88/RCLootCouncil_PriorityLoot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A World of Warcraft addon (patch **12.0.5 – Midnight**) that integrates with [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil) to surface BiS priority data directly inside the voting frame and raider loot popup.

---

## Features

- **Officer voting frame** — adds a sortable *Priority* column showing each candidate's BiS rank (1st / 2nd / 3rd) for the dropped item.
- **Raider loot frame** — overlays the local player's own priority rank below each item button so raiders can immediately see where an item sits in their BiS list.
- **Priority preview** — `/rclp prio` opens a scrollable popup showing all imported priority lists and the full player roster, so officers can verify data before a raid.
- **Offline-first** — data is imported once per week by an officer via a single in-game paste; no external server, desktop client, or API key required.
- **Optional for raiders** — raiders who do not install the addon see the default RCLootCouncil UI with no changes.

---

## Requirements

| Dependency | Notes |
|---|---|
| [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil) | Required. Loaded before this addon via `.toc` dependency. |
| WoW patch 12.0.5+ | Interface version `120005`. |
| Priority Google Sheet | **Required for officers.** The accompanying Google Sheet (running `SpreadsheetExport.gs`) is what generates the Base64 import string. A public template is not yet available — contact the addon author for access. Raiders who never run `/rclp import` do not need it. |

---

## Installation

1. Download or clone this folder into your addons directory:
   ```
   World of Warcraft/_retail_/Interface/AddOns/RCLootCouncil_PriorityLoot/
   ```
2. Ensure RCLootCouncil is also installed.
3. Launch the game — the addon loads automatically.

---

## Weekly Officer Workflow

1. Open the Priority Google Sheet and run the export function — this produces a **Base64-encoded JSON string** matching the format below. (The sheet is not yet publicly available; contact the addon author for access.)
2. In-game, type `/rclp import`.
3. Paste the export string into the text box and click **Confirm**.
4. The addon prints a confirmation with the number of players and priority items imported. Data persists via SavedVariables until the next import or a manual reset.

---

## Slash Commands

| Command | Description |
|---|---|
| `/rclp import` | Open the import window. |
| `/rclp prio` | Open a scrollable preview of all imported priority data (toggle). |
| `/rclp reset` | Wipe all stored priority data from SavedVariables. |
| `/rclp` | Print command usage. |

---

## Data Format

The import string is a **Base64-encoded JSON** blob. When decoded, the expected structure is:

```json
{
  "priority": {
    "12345": ["Playername-Realm", "Playername2-Realm", "Playername3-Realm"]
  },
  "players": {
    "Playername-Realm": {
      "helm":      { "bis": [111, 222, 333] },
      "neck":      { "bis": [111, 222, 333] },
      "shoulders": { "bis": [111, 222, 333] },
      "chest":     { "bis": [111, 222, 333] },
      "gloves":    { "bis": [111, 222, 333] },
      "legs":      { "bis": [111, 222, 333] },
      "ring1":     { "bis": [111, 222, 333] },
      "ring2":     { "bis": [111, 222, 333] },
      "trinket1":  { "bis": [111, 222, 333] },
      "trinket2":  { "bis": [111, 222, 333] },
      "mh2h":      { "bis": [111, 222, 333] },
      "oh":        { "bis": [111, 222, 333] }
    }
  }
}
```

**`priority`** (optional) — item-centric lookup. Keyed by item ID string; value is an ordered array of `Name-Realm` strings. When a `priority` entry exists for the dropped item it takes precedence over the player's `players` BiS list. Players absent from the list display as **N/A**.

**`players`** (required) — player-centric fallback. Keyed by `Name-Realm`; each slot holds a `bis` array of item IDs ordered by priority (index 1 = highest).

**Player keys** must match the `Name-Realm` format RCLootCouncil uses internally.  
**Item IDs** are integers — the same IDs returned by `GetItemInfo()`.

### Slot keys

| Key(s) | Covers |
|---|---|
| `helm` | Head |
| `neck` | Neck |
| `shoulders` | Shoulders |
| `chest` | Chest / Robe |
| `gloves` | Hands |
| `legs` | Legs |
| `ring1`, `ring2` | Finger (both slots checked) |
| `trinket1`, `trinket2` | Trinket (both slots checked) |
| `mh2h` | Main-hand, Two-handed, Weapon |
| `oh` | Off-hand |

Secondary armor slots (Cloak, Bracers, Belt, Boots) are not part of the import. The Priority column defers to wowaudit wishlists for those item types.

---

## File Structure

```
RCLootCouncil_PriorityLoot/
├── RCLootCouncil_PriorityLoot.toc   — metadata, load order, saved variables
├── Core.lua                          — addon init, slash commands
├── SpreadsheetExport.gs              — Google Apps Script: exports BiS/priority data,
│                                       fills Priority Order dropdowns, fetches WCL scores
├── Data/
│   └── db.lua                        — SavedVariable read/write, priority lookup
├── Modules/
│   ├── votingFrame.lua               — voting frame column injection
│   ├── lootFrame.lua                 — raider loot frame overlay
│   ├── importFrame.lua               — in-game import UI, Base64 decoder
│   └── prioPreviewFrame.lua          — /rclp prio scrollable data preview
└── Libs/
    └── LibJSON.lua                   — bundled pure-Lua JSON decoder
```

---

## Colour Reference

| Value | Colour |
|---|---|
| 1st BiS | Green `#00FF00` |
| 2nd BiS | Yellow `#FFFF00` |
| 3rd BiS (or lower) | Orange `#FF8000` |
| Not on list / no data | Grey `#999999` |

---

## SavedVariables

Data is stored in `RCLPriorityDB` (declared in `.toc`). WoW persists this table automatically between sessions per account. Use `/rclp reset` to wipe it, or delete the entry from your `WTF/` saved variables file manually.

---

## Versioning

`MAJOR.MINOR.PATCH`

| Segment | Bumped when… |
|---|---|
| `MAJOR` | WoW expansion launch · new or removed dependency · priority data source type change · major UI overhaul · first stable release |
| `MINOR` | Column added to a new RCLootCouncil frame · new priority tier/category system · new standalone UI surface (options panel, minimap button, etc.) |
| `PATCH` | Bug fixes · `.toc` interface version bumps · UX polish |

Priority data is imported by officers — changes to player priority entries do not affect the version number.

---

## Development

For the full per-platform setup (Lua 5.1, LuaRocks, `luacheck`, `busted` on Linux, macOS, and Windows + MSYS2 / Git Bash) see [`docs/SETUP.md`](docs/SETUP.md). Once installed:

```bash
luacheck .                  # lint
bash scripts/run_tests.sh   # 29 specs covering Data/db.lua
```

Both should exit 0 before you push. CI runs the same commands on every push and PR via `.github/workflows/ci.yml`.

### Roadmap

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the phased improvement plan, branching strategy, and commit/version conventions.

### Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full setup, branch and commit conventions, PR checklist, and style notes. Bug reports and feature requests use the templates under `.github/ISSUE_TEMPLATE/`.

---

## License

MIT
