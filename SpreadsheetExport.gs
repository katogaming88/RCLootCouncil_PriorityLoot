// RCLootCouncil_PriorityLoot — Google Sheets export script
// Paste into Extensions > Apps Script in your priority spreadsheet.
// Run via the "RCLPL" menu → "Export priority data…"
// Copy the Base64 string and paste it into the in-game /rclp import window.
//
// Sheet layout expected:
//
//   "Item Lookup"  — row 1: title, row 2: headers (Item Name | Item ID | Slot), row 3+: data
//   "BiS List"     — row 1: blank, row 2: headers (Slot | Name-Realm | Name-Realm | ...)
//                    col A: slot labels like "Head - 1", "Head - 2", "Trinket 1 - 1", etc.
//                    col B+: item names matching entries in Item Lookup
//   "Priority Order" — row 1: headers (Item Name | Rank1 Name-Realm | Rank2 | ...)
//                      col A: item name, col B+: player names in rank order

const BIS_SHEET_NAME    = "BiS List";
const PRIO_SHEET_NAME   = "Priority Order";
const LOOKUP_SHEET_NAME = "Item Lookup";

// Slot label (left side of " - N") → internal slot key used by the addon
const SLOT_LABEL_MAP = {
  "Head":       "helm",
  "Neck":       "neck",
  "Shoulders":  "shoulders",
  "Chest":      "chest",
  "Gloves":     "gloves",
  "Legs":       "legs",
  "Ring 1":     "ring1",
  "Ring 2":     "ring2",
  "Trinket 1":  "trinket1",
  "Trinket 2":  "trinket2",
  "MH/2H":      "mh2h",
  "OH":         "oh",
  "Cloak":      "cloak",
  "Bracers":    "bracers",
  "Belt":       "belt",
  "Boots":      "boots",
};

// ── Menu ────────────────────────────────────────────────────────────────────

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu("RCLPL")
    .addItem("Export priority data…", "exportPriorityData")
    .addToUi();
}

// ── Main export ──────────────────────────────────────────────────────────────

function exportPriorityData() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();

  const itemLookup = buildItemLookup(ss);
  const players    = buildPlayersObject(ss, itemLookup);
  const priority   = buildPriorityObject(ss, itemLookup);

  const playerCount  = Object.keys(players).length;
  const priorityCount = Object.keys(priority).length;

  if (playerCount === 0) {
    SpreadsheetApp.getUi().alert(
      `No player data found in "${BIS_SHEET_NAME}". ` +
      "Check the sheet name and that row 3+ has item entries."
    );
    return;
  }

  const payload = JSON.stringify({ players, priority });
  const encoded = Utilities.base64Encode(payload);

  showExportDialog(encoded, playerCount, priorityCount);
}

// ── Item lookup ──────────────────────────────────────────────────────────────
// Returns { "item name lowercase": itemID (number) }
// Row 1 = title banner, Row 2 = column headers, Row 3+ = data.

function buildItemLookup(ss) {
  const sheet = ss.getSheetByName(LOOKUP_SHEET_NAME);
  if (!sheet) throw new Error(`Sheet "${LOOKUP_SHEET_NAME}" not found.`);

  const data   = sheet.getDataRange().getValues();
  const lookup = {};

  for (let r = 2; r < data.length; r++) {
    const name = String(data[r][0]).trim();
    const id   = Number(data[r][1]);
    if (name && id > 0) {
      lookup[name.toLowerCase()] = id;
    }
  }

  return lookup;
}

// ── Build players object ─────────────────────────────────────────────────────
// BiS List layout:
//   Row index 0 (row 1): blank — skipped
//   Row index 1 (row 2): headers — col 0 = "Slot", col 1+ = "Name-Realm"
//   Row index 2+ (row 3+): col 0 = "SlotLabel - N", col 1+ = item name strings
//
// Each slot label like "Head - 1" maps to slotKey "helm" at BIS rank 1.
// Two rows per slot (- 1 and - 2) build a bis: [id1, id2] array.
//
// Returns: { "Name-Realm": { helm: { bis: [id,...] }, ... } }

function buildPlayersObject(ss, itemLookup) {
  const sheet = ss.getSheetByName(BIS_SHEET_NAME);
  if (!sheet) throw new Error(`Sheet "${BIS_SHEET_NAME}" not found.`);

  const data = sheet.getDataRange().getValues();

  // Row index 1 = player name headers
  const headerRow  = data[1];
  const playerNames = [];
  for (let c = 1; c < headerRow.length; c++) {
    playerNames.push(String(headerRow[c]).trim());
  }

  // Collect { playerName → { slotKey → { rank → itemID } } }
  const collected = {};

  for (let r = 2; r < data.length; r++) {
    const row   = data[r];
    const label = String(row[0]).trim();
    if (!label) continue;

    // Parse "SlotLabel - N"
    const match = label.match(/^(.+?)\s*-\s*(\d+)$/);
    if (!match) continue;

    const slotLabel = match[1].trim();
    const rank      = parseInt(match[2], 10);
    const slotKey   = SLOT_LABEL_MAP[slotLabel];
    if (!slotKey) continue;

    for (let c = 0; c < playerNames.length; c++) {
      const playerName = playerNames[c];
      if (!playerName) continue;

      const itemName = String(row[c + 1]).trim();
      if (!itemName) continue;

      const itemID = itemLookup[itemName.toLowerCase()];
      if (!itemID) continue;

      if (!collected[playerName])           collected[playerName] = {};
      if (!collected[playerName][slotKey])  collected[playerName][slotKey] = {};
      collected[playerName][slotKey][rank] = itemID;
    }
  }

  // Convert rank maps to ordered bis arrays
  const players = {};
  for (const [playerName, slotMap] of Object.entries(collected)) {
    const slots = {};
    for (const [slotKey, rankMap] of Object.entries(slotMap)) {
      const maxRank = Math.max(...Object.keys(rankMap).map(Number));
      const bis = [];
      for (let rank = 1; rank <= maxRank; rank++) {
        if (rankMap[rank] != null) bis.push(rankMap[rank]);
      }
      if (bis.length > 0) slots[slotKey] = { bis };
    }
    if (Object.keys(slots).length > 0) players[playerName] = slots;
  }

  return players;
}

// ── Build priority object ────────────────────────────────────────────────────
// Priority Order layout:
//   Row 1: headers (Item Name | Rank1 | Rank2 | ...)
//   Row 2+: col A = item name, col B+ = "Name-Realm" in rank order
//
// Returns: { "itemIDstr": ["Name-Realm", ...] }

function buildPriorityObject(ss, itemLookup) {
  const sheet = ss.getSheetByName(PRIO_SHEET_NAME);
  if (!sheet) return {};

  const data     = sheet.getDataRange().getValues();
  const priority = {};

  for (let r = 1; r < data.length; r++) {
    const row      = data[r];
    const itemName = String(row[0]).trim();
    if (!itemName) continue;

    const itemID = itemLookup[itemName.toLowerCase()];
    if (!itemID) continue;

    const names = [];
    for (let c = 1; c < row.length; c++) {
      const name = String(row[c]).trim();
      if (name) names.push(name);
    }

    if (names.length > 0) {
      priority[String(itemID)] = names;
    }
  }

  return priority;
}

// ── Export dialog ────────────────────────────────────────────────────────────

function showExportDialog(encoded, playerCount, priorityCount) {
  const html = `<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: Arial, sans-serif; padding: 12px; margin: 0; }
  p    { margin: 0 0 8px; font-size: 13px; }
  textarea {
    width: 100%; height: 180px; font-family: monospace; font-size: 11px;
    word-break: break-all; resize: none; box-sizing: border-box;
  }
  button {
    margin-top: 8px; padding: 6px 16px; font-size: 13px;
    cursor: pointer; background: #4a86e8; color: #fff; border: none; border-radius: 4px;
  }
  button:hover { background: #2d6acf; }
  .meta { color: #555; font-size: 12px; margin-bottom: 10px; }
</style>
</head>
<body>
  <p class="meta">
    Exported <strong>${playerCount}</strong> player(s) and
    <strong>${priorityCount}</strong> priority override(s).
  </p>
  <p>Select all and copy, then paste into the in-game <code>/rclp import</code> window.</p>
  <textarea id="out" readonly>${encoded}</textarea>
  <br>
  <button onclick="selectAll()">Select All</button>
  <script>
    function selectAll() {
      var t = document.getElementById('out');
      t.focus();
      t.select();
    }
    window.onload = selectAll;
  </script>
</body>
</html>`;

  SpreadsheetApp.getUi().showModalDialog(
    HtmlService.createHtmlOutput(html).setWidth(640).setHeight(320),
    "RCLootCouncil Priority Export"
  );
}
