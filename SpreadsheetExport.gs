// ============================================================
// Team Phoenix — Combined Apps Script
// Includes:
//   1. RCLootCouncil Priority Export + Dropdown helpers
//   2. WCL Performance Score Fetcher
// ============================================================
 
 
// ════════════════════════════════════════════════════════════════════════════
// SHARED CONFIG
// ════════════════════════════════════════════════════════════════════════════

const BIS_SHEET_NAME    = "BiS List";
const PRIO_SHEET_NAME   = "Priority Order";
const LOOKUP_SHEET_NAME = "Item Lookup";
const ROSTER_SHEET_NAME = "Roster & Scoring";

const PRIO_HEADER_ROW     = 2;
const PRIO_DATA_START     = 3;
const PRIO_ITEM_NAME_COL  = 2;
const PRIO_RANK_START_COL = 3;

const PLAYER_COL        = 1;
const DRAFT_SCORE_COL   = 12;  // Column L — Recent Score (last 2 reports)
const TREND_SCORE_COL   = 13;  // Column M — Trend Score (last 8 reports)
const PLAYER_DATA_START = 4;
const PLAYER_DATA_END   = 33;

// ════════════════════════════════════════════════════════════════════════════
// WCL CONFIG
// ════════════════════════════════════════════════════════════════════════════

const WCL_CLIENT_ID     = 'a1aa2d7d-bea9-4047-a993-999f163d2368';
const WCL_CLIENT_SECRET = 'hCLPCtQMaQrJ1hGl5WzB7trET8tMciore78E1L7R';

const GUILD_ID            = 801219;
const RECENT_REPORTS      = 2;   // "Recent" score window
const TREND_REPORTS       = 8;   // "Trend" score window
const REPORT_NAME_FILTER  = 'Phoenix';

const HEALERS = ['Mittens', 'Fxhp', 'Inquizical', 'Flameus'];
const TANKS   = ['Fluphie', 'Fluphyxd', 'Hinda', 'Rothdar'];

const MYTHIC_DIFF = 5;
const HEROIC_DIFF = 4;

// ════════════════════════════════════════════════════════════════════════════
// MENU
// ════════════════════════════════════════════════════════════════════════════

function onOpen() {
  const ui = SpreadsheetApp.getUi();

  ui.createMenu('RCLPL')
    .addItem('Export priority data…', 'exportPriorityData')
    .addSeparator()
    .addItem('Fill dropdowns for selected item row', 'fillDropdownsForSelectedRow')
    .addItem('Fill dropdowns for ALL item rows', 'fillAllPriorityDropdowns')
    .addToUi();

  ui.createMenu('⚔ Team Phoenix')
    .addItem('Refresh WCL Performance Scores', 'fetchWCLScores')
    .addItem('Commit Draft Scores → Performance', 'commitDraftScores')
    .addToUi();
}

// ════════════════════════════════════════════════════════════════════════════
// SECTION 1 — RCLootCouncil Export + Priority Dropdowns
// ════════════════════════════════════════════════════════════════════════════

const SLOT_LABEL_MAP = {
  "Head":      "helm",
  "Neck":      "neck",
  "Shoulders": "shoulders",
  "Chest":     "chest",
  "Gloves":    "gloves",
  "Legs":      "legs",
  "Ring 1":    "ring1",
  "Ring 2":    "ring2",
  "Trinket 1": "trinket1",
  "Trinket 2": "trinket2",
  "MH/2H":     "mh2h",
  "OH":        "oh",
  "Cloak":     "cloak",
  "Bracers":   "bracers",
  "Belt":      "belt",
  "Boots":     "boots",
};

function exportPriorityData() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();

  const itemLookup = buildItemLookup(ss);
  const players    = buildPlayersObject(ss, itemLookup);
  const priority   = buildPriorityObject(ss, itemLookup);

  const playerCount   = Object.keys(players).length;
  const priorityCount = Object.keys(priority).length;

  if (playerCount === 0) {
    SpreadsheetApp.getUi().alert(
      `No player data found in "${BIS_SHEET_NAME}". ` +
      "Check the sheet name and that row 3+ has item entries."
    );
    return;
  }

  const payload = JSON.stringify({ players, priority });
  const encoded = Utilities.base64Encode(payload, Utilities.Charset.UTF_8);

  // Write to the output box on Export sheet
  const exportSheet = ss.getSheetByName("Export");
  exportSheet.getRange("A11").setValue(encoded);

  showExportDialog(encoded, playerCount, priorityCount);
}

function buildItemLookup(ss) {
  const sheet = ss.getSheetByName(LOOKUP_SHEET_NAME);
  if (!sheet) throw new Error(`Sheet "${LOOKUP_SHEET_NAME}" not found.`);

  const data   = sheet.getDataRange().getValues();
  const lookup = {};

  for (let r = 2; r < data.length; r++) {
    const name = String(data[r][0]).trim();
    const id   = Number(data[r][1]);
    if (name && id > 0) lookup[name.toLowerCase()] = id;
  }

  return lookup;
}

function buildPlayersObject(ss, itemLookup) {
  const sheet = ss.getSheetByName(BIS_SHEET_NAME);
  if (!sheet) throw new Error(`Sheet "${BIS_SHEET_NAME}" not found.`);

  const data        = sheet.getDataRange().getValues();
  const headerRow   = data[1];
  const playerNames = [];

  for (let c = 1; c < headerRow.length; c++) {
    playerNames.push(String(headerRow[c]).trim());
  }

  const collected = {};

  for (let r = 2; r < data.length; r++) {
    const row   = data[r];
    const label = String(row[0]).trim();
    if (!label) continue;

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

      if (!collected[playerName])          collected[playerName] = {};
      if (!collected[playerName][slotKey]) collected[playerName][slotKey] = {};
      collected[playerName][slotKey][rank] = itemID;
    }
  }

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

function buildPriorityObject(ss, itemLookup) {
  const sheet = ss.getSheetByName(PRIO_SHEET_NAME);
  if (!sheet) return {};

  const data     = sheet.getDataRange().getValues();
  const priority = {};

  for (let r = PRIO_DATA_START - 1; r < data.length; r++) {
    const row      = data[r];
    const itemName = String(row[PRIO_ITEM_NAME_COL - 1]).trim();
    if (!itemName) continue;

    const itemID = itemLookup[itemName.toLowerCase()];
    if (!itemID) continue;

    const names = [];
    for (let c = PRIO_RANK_START_COL - 1; c < row.length; c++) {
      const name = String(row[c]).trim();
      if (name) names.push(name);
    }

    if (names.length > 0) priority[String(itemID)] = names;
  }

  return priority;
}

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

// ── Priority Order Dropdowns ──────────────────────────────────────────────────

function buildBisMap(ss) {
  const sheet = ss.getSheetByName(BIS_SHEET_NAME);
  if (!sheet) throw new Error(`Sheet "${BIS_SHEET_NAME}" not found.`);

  const data      = sheet.getDataRange().getValues();
  const headerRow = data[1];

  const players = [];
  for (let c = 1; c < headerRow.length; c++) {
    const name = String(headerRow[c]).trim();
    if (name) players.push({ col: c, name });
  }

  const bisMap = {};

  for (let r = 2; r < data.length; r++) {
    const row = data[r];
    for (const { col, name: player } of players) {
      const cell = String(row[col]).trim();
      if (!cell || cell === "undefined") continue;
      const key = cell.toLowerCase();
      if (!bisMap[key]) bisMap[key] = new Set();
      bisMap[key].add(player);
    }
  }

  return bisMap;
}

function getEligiblePlayers(itemName, bisMap) {
  if (!itemName) return [];
  const key   = String(itemName).trim().toLowerCase();
  const found = bisMap[key];
  return found ? Array.from(found).sort() : [];
}

function applyDropdownsToRow(prioSheet, rowIndex, eligiblePlayers) {
  const lastCol = prioSheet.getLastColumn();

  if (eligiblePlayers.length === 0) {
    for (let c = PRIO_RANK_START_COL; c <= lastCol; c++) {
      prioSheet.getRange(rowIndex, c).clearDataValidations().clearContent();
    }
    SpreadsheetApp.getUi().alert(
      "No players have this item in their BiS List yet.\n" +
      "Fill in the BiS List sheet first, then re-run."
    );
    return;
  }

  const rule = SpreadsheetApp.newDataValidation()
    .requireValueInList(["", ...eligiblePlayers], true)
    .setAllowInvalid(false)
    .build();

  for (let c = PRIO_RANK_START_COL; c <= lastCol; c++) {
    const cell     = prioSheet.getRange(rowIndex, c);
    const existing = String(cell.getValue()).trim();
    if (existing && !eligiblePlayers.includes(existing)) cell.clearContent();
    cell.setDataValidation(rule);
  }
}

function fillDropdownsForSelectedRow() {
  const ss          = SpreadsheetApp.getActiveSpreadsheet();
  const prioSheet   = ss.getSheetByName(PRIO_SHEET_NAME);
  const activeSheet = ss.getActiveSheet();

  if (!prioSheet) {
    SpreadsheetApp.getUi().alert(`Sheet "${PRIO_SHEET_NAME}" not found.`);
    return;
  }
  if (activeSheet.getName() !== PRIO_SHEET_NAME) {
    SpreadsheetApp.getUi().alert(`Please click a cell in the "${PRIO_SHEET_NAME}" sheet first.`);
    return;
  }

  const row = ss.getActiveRange().getRow();
  if (row < PRIO_DATA_START) {
    SpreadsheetApp.getUi().alert(`Please click on an item row (row ${PRIO_DATA_START} or below).`);
    return;
  }

  const itemName = String(prioSheet.getRange(row, PRIO_ITEM_NAME_COL).getValue()).trim();
  if (!itemName) {
    SpreadsheetApp.getUi().alert(`No item name found in column B of row ${row}.`);
    return;
  }

  const bisMap          = buildBisMap(ss);
  const eligiblePlayers = getEligiblePlayers(itemName, bisMap);

  applyDropdownsToRow(prioSheet, row, eligiblePlayers);

  if (eligiblePlayers.length > 0) {
    SpreadsheetApp.getUi().alert(
      `✓ Dropdowns set for "${itemName}".\n` +
      `${eligiblePlayers.length} eligible player(s): ${eligiblePlayers.join(", ")}`
    );
  }
}

function fillAllPriorityDropdowns() {
  const ss        = SpreadsheetApp.getActiveSpreadsheet();
  const prioSheet = ss.getSheetByName(PRIO_SHEET_NAME);

  if (!prioSheet) {
    SpreadsheetApp.getUi().alert(`Sheet "${PRIO_SHEET_NAME}" not found.`);
    return;
  }

  const bisMap  = buildBisMap(ss);
  const data    = prioSheet.getDataRange().getValues();
  let   updated = 0;
  let   skipped = 0;

  for (let r = PRIO_DATA_START - 1; r < data.length; r++) {
    const itemName = String(data[r][PRIO_ITEM_NAME_COL - 1]).trim();
    if (!itemName) { skipped++; continue; }

    const eligible = getEligiblePlayers(itemName, bisMap);
    applyDropdownsToRow(prioSheet, r + 1, eligible);
    updated++;
  }

  SpreadsheetApp.getUi().alert(
    `✓ Done!\nUpdated dropdowns for ${updated} item row(s).\nSkipped ${skipped} empty row(s).`
  );
}

function onSelectionChange(e) {
  if (e.range.getSheet().getName() === "Export" && e.range.getA1Notation() === "A8:C8") {
    exportPriorityData();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SECTION 2 — WCL Performance Score Fetcher (Dual Score: Recent + Trend)
// ════════════════════════════════════════════════════════════════════════════

function fetchWCLScores() {
  try {
    Logger.log('Starting WCL fetch...');

    const token = getAccessToken();
    if (!token) throw new Error('Failed to get WCL access token. Check Client ID and Secret.');

    // Fetch enough reports for the trend window
    const allReports = getRecentReports(token, TREND_REPORTS);
    if (!allReports || allReports.length === 0) throw new Error('No matching Phoenix reports found.');

    Logger.log(`Found ${allReports.length} reports.`);

    // Split into recent and trend windows
    const recentReports = allReports.slice(0, RECENT_REPORTS);
    const trendReports  = allReports; // all 8

    const recentData = collectPlayerData(token, recentReports);
    const trendData  = collectPlayerData(token, trendReports);

    writeDualScores(recentData, trendData);

    SpreadsheetApp.getUi().alert(
      '✅ WCL Scores Updated!\n\n' +
      `Column L = Recent Score (last ${RECENT_REPORTS} reports)\n` +
      `Column M = Trend Score (last ${TREND_REPORTS} reports)\n\n` +
      'Review both columns before committing.'
    );

  } catch (e) {
    Logger.log('Error: ' + e.message);
    SpreadsheetApp.getUi().alert('❌ Error: ' + e.message);
  }
}

function collectPlayerData(token, reports) {
  const playerData = {};

  for (const report of reports) {
    Logger.log(`Processing: ${report.title} (${report.code})`);
    const fightData = getReportRankings(token, report.code);
    if (!fightData) continue;

    for (const fight of fightData) {
      if (!fight.roles) continue;

      for (const roleKey of ['dps', 'healers', 'tanks']) {
        const entries = fight.roles[roleKey]?.characters || [];
        for (const character of entries) {
          const name    = character.name;
          const ilvlPct = character.bracketPercent;
          if (!name || ilvlPct == null || ilvlPct === 0) continue;

          const expectedRole = getRole(name);
          if (expectedRole === 'tank')                          continue;
          if (expectedRole === 'healer' && roleKey !== 'healers') continue;
          if (expectedRole === 'dps'    && roleKey !== 'dps')     continue;

          if (!playerData[name]) playerData[name] = { ilvlPercentages: [] };
          playerData[name].ilvlPercentages.push(ilvlPct);
        }
      }
    }
  }

  return playerData;
}

function calcScore(ilvlPercentages) {
  if (!ilvlPercentages || ilvlPercentages.length === 0) return null;
  const avg = ilvlPercentages.reduce((a, b) => a + b, 0) / ilvlPercentages.length;
  return Math.round((avg / 10) * 100) / 100;
}

function writeDualScores(recentData, trendData) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(ROSTER_SHEET_NAME);
  if (!sheet) throw new Error(`Sheet "${ROSTER_SHEET_NAME}" not found`);

  // Set column headers
  const recentHeader = sheet.getRange(3, DRAFT_SCORE_COL);
  recentHeader.setValue(`Recent Score\n(last ${RECENT_REPORTS} reports)`);
  recentHeader.setFontWeight('bold').setBackground('#FFF2CC').setHorizontalAlignment('center').setWrap(true);

  const trendHeader = sheet.getRange(3, TREND_SCORE_COL);
  trendHeader.setValue(`Trend Score\n(last ${TREND_REPORTS} reports)`);
  trendHeader.setFontWeight('bold').setBackground('#D9EAD3').setHorizontalAlignment('center').setWrap(true);

  for (let row = PLAYER_DATA_START; row <= PLAYER_DATA_END; row++) {
    const cellValue = sheet.getRange(row, PLAYER_COL).getValue();
    if (!cellValue) continue;

    const firstName = cellValue.toString().split('-')[0];
    const role      = getRole(firstName);

    const recentCell = sheet.getRange(row, DRAFT_SCORE_COL);
    const trendCell  = sheet.getRange(row, TREND_SCORE_COL);

    if (role === 'tank') {
      recentCell.setValue('Manual').setBackground('#CFE2F3');
      trendCell.setValue('Manual').setBackground('#CFE2F3');
      continue;
    }

    const recentScore = calcScore(recentData[firstName]?.ilvlPercentages);
    const trendScore  = calcScore(trendData[firstName]?.ilvlPercentages);
    const recentCount = recentData[firstName]?.ilvlPercentages?.length || 0;
    const trendCount  = trendData[firstName]?.ilvlPercentages?.length || 0;

    if (recentScore !== null) {
      recentCell.setValue(recentScore).setNumberFormat('0.00').setBackground('#FFF2CC');
      recentCell.setNote(`${recentCount} fight(s) across last ${RECENT_REPORTS} reports`);
    } else {
      recentCell.setValue('No data').setBackground('#F4CCCC');
    }

    if (trendScore !== null) {
      // Highlight trend direction vs recent
      let trendBg = '#D9EAD3'; // neutral green
      if (recentScore !== null) {
        if (trendScore > recentScore + 0.5)      trendBg = '#FCE5CD'; // trending down (recent is better)
        else if (recentScore > trendScore + 0.5) trendBg = '#B7E1CD'; // trending up (recent is better than trend)
      }
      trendCell.setValue(trendScore).setNumberFormat('0.00').setBackground(trendBg);
      trendCell.setNote(`${trendCount} fight(s) across last ${TREND_REPORTS} reports`);
    } else {
      trendCell.setValue('No data').setBackground('#F4CCCC');
    }
  }

  Logger.log('Dual scores written successfully.');
}

function commitDraftScores() {
  const ui = SpreadsheetApp.getUi();
  const response = ui.alert(
    'Commit Draft Scores',
    'This will copy Recent Scores (column L) into the Performance column (C).\n\n' +
    'Cells marked "No data" or "Manual" will be skipped.\n\nAre you sure?',
    ui.ButtonSet.YES_NO
  );

  if (response !== ui.Button.YES) return;

  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(ROSTER_SHEET_NAME);
  let committed = 0;

  for (let row = PLAYER_DATA_START; row <= PLAYER_DATA_END; row++) {
    const draftValue = sheet.getRange(row, DRAFT_SCORE_COL).getValue();
    if (!draftValue || draftValue === 'No data' || draftValue === 'Manual' || draftValue === '') continue;

    sheet.getRange(row, 3).setValue(draftValue).setBackground(null);
    sheet.getRange(row, DRAFT_SCORE_COL).setBackground('#D9EAD3');
    committed++;
  }

  ui.alert(`✅ Done — ${committed} Performance scores updated from Recent Score.`);
}

// ── WCL Helpers ───────────────────────────────────────────────────────────────

function getAccessToken() {
  const credentials = Utilities.base64Encode(`${WCL_CLIENT_ID}:${WCL_CLIENT_SECRET}`);
  const response = UrlFetchApp.fetch('https://www.warcraftlogs.com/oauth/token', {
    method: 'post',
    headers: { 'Authorization': `Basic ${credentials}` },
    payload: { grant_type: 'client_credentials' },
    muteHttpExceptions: true
  });
  const data = JSON.parse(response.getContentText());
  if (!data.access_token) { Logger.log('Token response: ' + response.getContentText()); return null; }
  return data.access_token;
}

function getRecentReports(token, limit) {
  const query = `
    query {
      reportData {
        reports(guildID: ${GUILD_ID}, limit: 20) {
          data { code title startTime endTime }
        }
      }
    }
  `;
  const result = wclQuery(token, query);
  if (!result) return [];
  const allReports = result.data?.reportData?.reports?.data || [];
  return allReports.filter(r => r.title && r.title.includes(REPORT_NAME_FILTER)).slice(0, limit);
}

function getReportRankings(token, reportCode) {
  let fights = fetchRankingsForDifficulty(token, reportCode, MYTHIC_DIFF);
  if (!fights || fights.length === 0) {
    Logger.log(`No mythic data for ${reportCode}, falling back to heroic`);
    fights = fetchRankingsForDifficulty(token, reportCode, HEROIC_DIFF);
  }
  return fights;
}

function fetchRankingsForDifficulty(token, reportCode, difficulty) {
  const query = `
    query {
      reportData {
        report(code: "${reportCode}") {
          rankings(difficulty: ${difficulty})
        }
      }
    }
  `;
  const result = wclQuery(token, query);
  if (!result) return [];
  const rankingsRaw = result.data?.reportData?.report?.rankings;
  if (!rankingsRaw) return [];
  try {
    const rankings = typeof rankingsRaw === 'string' ? JSON.parse(rankingsRaw) : rankingsRaw;
    return rankings?.data || [];
  } catch (e) {
    Logger.log('Failed to parse rankings JSON: ' + e.message);
    return [];
  }
}

function wclQuery(token, query) {
  try {
    const response = UrlFetchApp.fetch('https://www.warcraftlogs.com/api/v2/client', {
      method: 'post',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      payload: JSON.stringify({ query }),
      muteHttpExceptions: true
    });
    const data = JSON.parse(response.getContentText());
    if (data.errors) { Logger.log('GraphQL errors: ' + JSON.stringify(data.errors)); return null; }
    return data;
  } catch (e) {
    Logger.log('Request failed: ' + e.message);
    return null;
  }
}

function getRole(firstName) {
  if (HEALERS.some(h => h.toLowerCase() === firstName.toLowerCase())) return 'healer';
  if (TANKS.some(t  => t.toLowerCase() === firstName.toLowerCase())) return 'tank';
  return 'dps';
}

function createScoreLegend() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(ROSTER_SHEET_NAME);
  
  // Adjust this to wherever you want the legend to appear
  const legendStartRow = 4;
  const legendStartCol = 15; // Column O

  const title = sheet.getRange(legendStartRow, legendStartCol, 1, 2);
  title.merge();
  title.setValue('Score Legend');
  title.setFontWeight('bold');
  title.setHorizontalAlignment('center');
  title.setBackground('#333333');
  title.setFontColor('#FFFFFF');

  const entries = [
    // [label, recentBg, trendBg]
    ['Has a score',           '#FFF2CC', '#D9EAD3'],
    ['Trending up 📈',        '#FFF2CC', '#B7E1CD'],
    ['Trending down 📉',      '#FFF2CC', '#FCE5CD'],
    ['No data (not logged)',  '#F4CCCC', '#F4CCCC'],
    ['Tank (manual score)',   '#CFE2F3', '#CFE2F3'],
  ];

  const descriptions = [
    'Has a score this window',
    'Improving — recent > trend',
    'Declining — trend > recent',
    'No fights logged this window',
    'Scored manually by council',
  ];

  // Column headers
  sheet.getRange(legendStartRow + 1, legendStartCol).setValue('Recent (L)').setFontWeight('bold').setHorizontalAlignment('center');
  sheet.getRange(legendStartRow + 1, legendStartCol + 1).setValue('Trend (M)').setFontWeight('bold').setHorizontalAlignment('center');

  entries.forEach(([label, recentBg, trendBg], i) => {
    const row = legendStartRow + 2 + i;

    const recentCell = sheet.getRange(row, legendStartCol);
    recentCell.setValue('■ ' + label);
    recentCell.setBackground(recentBg);
    recentCell.setFontSize(10);

    const trendCell = sheet.getRange(row, legendStartCol + 1);
    trendCell.setValue(descriptions[i]);
    trendCell.setBackground(trendBg);
    trendCell.setFontSize(10);
    trendCell.setWrap(true);
  });

  // Set column widths for legend area
  sheet.setColumnWidth(legendStartCol, 160);
  sheet.setColumnWidth(legendStartCol + 1, 220);

  SpreadsheetApp.getUi().alert('✅ Legend created! Check row ' + legendStartRow + ' in Roster & Scoring.');
}