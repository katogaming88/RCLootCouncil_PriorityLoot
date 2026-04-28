# RCLootCouncil – PriorityLoot

A World of Warcraft addon (patch **12.0.5 – Midnight**) that integrates with [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil) to surface BiS priority and Droptimizer data directly inside the voting frame and raider loot popup.

---

## Features

- **Officer voting frame** — adds a sortable *Priority* column showing each candidate's BiS rank (1st / 2nd / 3rd) or Droptimizer % gain for the dropped item.
- **Raider loot frame** — appends the local player's own priority beneath the item link so raiders can immediately see whether an item is an upgrade for them.
- **Offline-first** — data is imported once per week by an officer via a single in-game paste; no external server, desktop client, or API key required.
- **Optional for raiders** — raiders who do not install the addon see the default RCLootCouncil UI with no changes.

---

## Requirements

| Dependency | Notes |
|---|---|
| [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil) | Required. Loaded before this addon via `.toc` dependency. |
| WoW patch 12.0.5+ | Interface version `120005`. |

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

1. Export your roster's BiS / Droptimizer data from your preferred planning tool (e.g. WoWAudit, Warcraftlogs) as a **Base64-encoded JSON string** matching the format below.
2. In-game, type `/rclp import`.
3. Paste the export string into the text box and click **Confirm**.
4. The addon prints a confirmation with the number of players imported. Data persists via SavedVariables until the next import or a manual reset.

---

## Slash Commands

| Command | Description |
|---|---|
| `/rclp import` | Open the import window. |
| `/rclp reset` | Wipe all stored priority data from SavedVariables. |
| `/rclp` | Print command usage. |

---

## Data Format

The import string is a **Base64-encoded JSON** blob. When decoded, the expected structure is:

```json
{
  "players": {
    "Playername-Realm": {
      "helm":      { "bis": [111, 222, 333] },
      "neck":      { "bis": [111, 222, 333] },
      "shoulders": { "bis": [111, 222, 333] },
      "chest":     { "bis": [111, 222, 333] },
      "gloves":    { "bis": [111, 222, 333] },
      "legs":      { "bis": [111, 222, 333] },
      "ring":      { "bis": [111, 222, 333] },
      "trinket":   { "bis": [111, 222, 333] },
      "weapon":    { "bis": [111, 222, 333] },
      "cloak":     { "droptimizer": 12.4 },
      "bracers":   { "droptimizer": 8.1 },
      "belt":      { "droptimizer": 5.7 }
    }
  }
}
```

**Player keys** must match the `Name-Realm` format RCLootCouncil uses internally.  
**Item IDs** are integers — the same IDs returned by `GetItemInfo()`.  
**`bis` arrays** are ordered: index 1 = highest priority, index 3 = lowest.

### Slot categories

| Category | Slots | Display |
|---|---|---|
| Core | Helm, Neck, Shoulders, Chest, Gloves, Legs, Rings, Trinkets, Weapons | BiS rank: **1st** (green) · **2nd** (yellow) · **3rd** (orange) |
| Secondary | Cloak, Bracers, Belt | Droptimizer gain: **≥10%** green · **5–9%** yellow · **<5%** orange |

Items not present in a player's list display as grey **N/A**.

---

## File Structure

```
RCLootCouncil_PriorityLoot/
├── RCLootCouncil_PriorityLoot.toc   — metadata, load order, saved variables
├── Core.lua                          — addon init, slash commands, login hook
├── Data.lua                          — SavedVariable read/write, priority lookup
├── Import.lua                        — in-game import UI, Base64 decoder
├── UI.lua                            — voting frame column injection
├── LootFrame.lua                     — raider loot frame overlay
└── Libs/
    └── LibJSON.lua                   — bundled pure-Lua JSON decoder
```

---

## Colour Reference

| Value | Colour |
|---|---|
| 1st BiS / ≥10% Droptimizer | Green `#00FF00` |
| 2nd BiS / 5–9% Droptimizer | Yellow `#FFFF00` |
| 3rd BiS / <5% Droptimizer | Orange `#FF8000` |
| Not on list / no data | Grey `#999999` |

---

## SavedVariables

Data is stored in `RCLPriorityDB` (declared in `.toc`). WoW persists this table automatically between sessions per account. Use `/rclp reset` to wipe it, or delete the entry from your `WTF/` saved variables file manually.

---

## License

MIT
