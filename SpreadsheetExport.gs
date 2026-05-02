// ============================================================
// Team Phoenix — Combined Apps Script
// Includes:
//   1. RCLootCouncil Priority Export + Dropdown helpers
//   2. WCL Performance Score Fetcher
//   3. BiS List Slot-Filtered Dropdowns
//   4. About Tab Creator
//   5. Sheet Reorder & Rename
// ============================================================


// ════════════════════════════════════════════════════════════════════════════
// SHARED CONFIG
// ════════════════════════════════════════════════════════════════════════════

const BIS_SHEET_NAME     = "BiS List";
const PRIO_SHEET_NAME    = "Priority Order";
const LOOKUP_SHEET_NAME  = "Item Lookup";
const SCORING_SHEET_NAME = "Scoring";

const PRIO_HEADER_ROW     = 2;
const PRIO_DATA_START     = 3;
const PRIO_ITEM_NAME_COL  = 2;
const PRIO_RANK_START_COL = 3;

const PLAYER_COL        = 1;
const DRAFT_SCORE_COL   = 10;  // Column J — Recent Score (last 2 reports)
const TREND_SCORE_COL   = 11;  // Column K — Trend Score (last 8 reports)
const PERF_COL          = 3;   // Column C — Performance
const PLAYER_DATA_START = 4;
const PLAYER_DATA_END   = 33;

// ════════════════════════════════════════════════════════════════════════════
// WCL CONFIG
// ════════════════════════════════════════════════════════════════════════════

const WCL_CLIENT_ID     = 'YOUR_WCL_CLIENT_ID';
const WCL_CLIENT_SECRET = 'YOUR_WCL_CLIENT_SECRET';

const GUILD_ID           = 801219;
const RECENT_REPORTS     = 2;   // "Recent" score window
const TREND_REPORTS      = 8;   // "Trend" score window
const REPORT_NAME_FILTER = 'Phoenix';

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
    .addItem('Set BiS List slot dropdowns', 'setBiSDropdowns')
    .addItem('Create BiS submission form', 'createBiSForm')
    .addItem('Import BiS form responses', 'importBiSFormResponses')
    .addItem('Rebuild About tab', 'createAboutTab')
    .addItem('Reorder & rename sheets', 'reorderAndRenameSheets')
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

    const allReports = getRecentReports(token, TREND_REPORTS);
    if (!allReports || allReports.length === 0) throw new Error('No matching Phoenix reports found.');

    Logger.log(`Found ${allReports.length} reports.`);

    const recentReports = allReports.slice(0, RECENT_REPORTS);
    const trendReports  = allReports;

    const recentData = collectPlayerData(token, recentReports);
    const trendData  = collectPlayerData(token, trendReports);

    writeDualScores(recentData, trendData);

    SpreadsheetApp.getUi().alert(
      '✅ WCL Scores Updated!\n\n' +
      `Column J = Recent Score (last ${RECENT_REPORTS} reports)\n` +
      `Column K = Trend Score (last ${TREND_REPORTS} reports)\n\n` +
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
          if (expectedRole === 'tank')                             continue;
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
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SCORING_SHEET_NAME);
  if (!sheet) throw new Error(`Sheet "${SCORING_SHEET_NAME}" not found`);

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
    } else if (trendScore !== null) {
      recentCell.setValue(trendScore).setNumberFormat('0.00').setBackground('#E8D5F5');
      recentCell.setNote(`No recent data — using trend score instead (${trendCount} fight(s) across last ${TREND_REPORTS} reports)`);
    } else {
      recentCell.setValue('No data').setBackground('#F4CCCC');
    }

    if (trendScore !== null) {
      let trendBg = '#D9EAD3';
      if (recentScore !== null) {
        if (trendScore > recentScore + 0.5)      trendBg = '#FCE5CD';
        else if (recentScore > trendScore + 0.5) trendBg = '#B7E1CD';
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
    'This will copy Recent Scores (column J) into the Performance column (C).\n\n' +
    'Cells marked "No data" or "Manual" will be skipped.\n\nAre you sure?',
    ui.ButtonSet.YES_NO
  );

  if (response !== ui.Button.YES) return;

  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SCORING_SHEET_NAME);
  let committed = 0;

  for (let row = PLAYER_DATA_START; row <= PLAYER_DATA_END; row++) {
    const cellValue = sheet.getRange(row, PLAYER_COL).getValue();
    if (!cellValue) continue;

    const firstName = cellValue.toString().split('-')[0];
    if (getRole(firstName) === 'tank') continue;

    const draftValue = sheet.getRange(row, DRAFT_SCORE_COL).getValue();
    if (!draftValue || draftValue === 'No data' || draftValue === 'Manual' || draftValue === '') continue;

    sheet.getRange(row, PERF_COL).setValue(draftValue);
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
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SCORING_SHEET_NAME);

  const legendStartRow = 4;
  const legendStartCol = 13;

  const title = sheet.getRange(legendStartRow, legendStartCol, 1, 2);
  title.merge();
  title.setValue('Score Legend');
  title.setFontWeight('bold');
  title.setHorizontalAlignment('center');
  title.setBackground('#333333');
  title.setFontColor('#FFFFFF');

  const entries = [
    ['Has a score',          '#FFF2CC', '#D9EAD3'],
    ['Trending up 📈',       '#FFF2CC', '#B7E1CD'],
    ['Trending down 📉',     '#FFF2CC', '#FCE5CD'],
    ['No data (not logged)', '#F4CCCC', '#F4CCCC'],
    ['Tank (manual score)',  '#CFE2F3', '#CFE2F3'],
    ['Score committed',      '#D9EAD3', ''],
    ['Using trend score',    '#E8D5F5', ''],
  ];

  const descriptions = [
    'Has a score this window',
    'Improving — recent > trend',
    'Declining — trend > recent',
    'No fights logged this window',
    'Scored manually by council',
    'Recent score committed to Performance',
    'No recent data — trend score used instead',
  ];

  sheet.getRange(legendStartRow + 1, legendStartCol).setValue('Recent (J)').setFontWeight('bold').setHorizontalAlignment('center');
  sheet.getRange(legendStartRow + 1, legendStartCol + 1).setValue('Trend (K)').setFontWeight('bold').setHorizontalAlignment('center');

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

  sheet.setColumnWidth(legendStartCol, 160);
  sheet.setColumnWidth(legendStartCol + 1, 220);

  SpreadsheetApp.getUi().alert('✅ Legend created! Check row ' + legendStartRow + ' in Scoring.');
}

// ════════════════════════════════════════════════════════════════════════════
// SECTION 3 — BiS List Slot-Filtered Dropdowns
// ════════════════════════════════════════════════════════════════════════════

const BIS_SLOT_TO_LOOKUP = {
  "Head":      "Head",
  "Neck":      "Neck",
  "Shoulders": "Shoulders",
  "Chest":     "Chest",
  "Gloves":    "Gloves",
  "Legs":      "Legs",
  "Ring 1":    "Ring",
  "Ring 2":    "Ring",
  "Trinket 1": "Trinket",
  "Trinket 2": "Trinket",
  "MH/2H":     "1H/2H",
  "OH":        "OH",
  "Cloak":     "Cloak",
  "Bracers":   "Bracers",
  "Belt":      "Belt",
  "Boots":     "Boots",
};

function setBiSDropdowns() {
  const ss        = SpreadsheetApp.getActiveSpreadsheet();
  const bisSheet  = ss.getSheetByName(BIS_SHEET_NAME);
  const itemSheet = ss.getSheetByName(LOOKUP_SHEET_NAME);

  if (!bisSheet || !itemSheet) {
    SpreadsheetApp.getUi().alert(`Could not find "${BIS_SHEET_NAME}" or "${LOOKUP_SHEET_NAME}". Check sheet names.`);
    return;
  }

  const itemData    = itemSheet.getDataRange().getValues();
  const itemsBySlot = {};

  for (let r = 2; r < itemData.length; r++) {
    const name = String(itemData[r][0]).trim();
    const slot = String(itemData[r][2]).trim();
    if (!name || !slot || name === 'Item Name') continue;
    if (!itemsBySlot[slot]) itemsBySlot[slot] = [];
    itemsBySlot[slot].push(name);
  }

  for (const slot in itemsBySlot) {
    itemsBySlot[slot].sort();
  }

  const bisData    = bisSheet.getDataRange().getValues();
  const lastCol    = bisSheet.getLastColumn();
  let   rowsSet    = 0;
  let   rowsMissed = 0;

  for (let r = 2; r < bisData.length; r++) {
    const label = String(bisData[r][0]).trim();
    if (!label) continue;

    const match = label.match(/^(.+?)\s*-\s*\d+$/);
    if (!match) continue;

    const slotBase  = match[1].trim();
    const lookupKey = BIS_SLOT_TO_LOOKUP[slotBase];
    if (!lookupKey) continue;

    const items = itemsBySlot[lookupKey];
    if (!items || items.length === 0) {
      rowsMissed++;
      continue;
    }

    const rule = SpreadsheetApp.newDataValidation()
      .requireValueInList(["", ...items], true)
      .setAllowInvalid(false)
      .build();

    bisSheet.getRange(r + 1, 2, 1, lastCol - 1).setDataValidation(rule);
    rowsSet++;
  }

  SpreadsheetApp.getUi().alert(
    `✅ Done!\n` +
    `${rowsSet} slot row(s) updated with filtered dropdowns.\n` +
    (rowsMissed > 0 ? `${rowsMissed} row(s) skipped (no matching items found).` : '')
  );
}

// ════════════════════════════════════════════════════════════════════════════
// SECTION 4 — BiS List Submission Form Creator
// ════════════════════════════════════════════════════════════════════════════

const BIS_FORM_SLOTS = [
  { label: "Head",      rows: ["Head - 1",      "Head - 2"]      },
  { label: "Neck",      rows: ["Neck - 1",      "Neck - 2"]      },
  { label: "Shoulders", rows: ["Shoulders - 1", "Shoulders - 2"] },
  { label: "Chest",     rows: ["Chest - 1",     "Chest - 2"]     },
  { label: "Gloves",    rows: ["Gloves - 1",    "Gloves - 2"]    },
  { label: "Legs",      rows: ["Legs - 1",      "Legs - 2"]      },
  { label: "Ring 1",    rows: ["Ring 1 - 1",    "Ring 1 - 2"]    },
  { label: "Ring 2",    rows: ["Ring 2 - 1",    "Ring 2 - 2"]    },
  { label: "Trinket 1", rows: ["Trinket 1 - 1", "Trinket 1 - 2"] },
  { label: "Trinket 2", rows: ["Trinket 2 - 1", "Trinket 2 - 2"] },
  { label: "MH / 2H",  rows: ["MH/2H - 1",     "MH/2H - 2"]    },
  { label: "Off Hand",  rows: ["OH - 1",         "OH - 2"]       },
  { label: "Cloak",     rows: ["Cloak - 1",      "Cloak - 2"]    },
  { label: "Bracers",   rows: ["Bracers - 1",    "Bracers - 2"]  },
  { label: "Belt",      rows: ["Belt - 1",       "Belt - 2"]     },
  { label: "Boots",     rows: ["Boots - 1",      "Boots - 2"]    },
];

function createBiSForm() {
  const ss   = SpreadsheetApp.getActiveSpreadsheet();
  const form = FormApp.create("Phoenix – BiS List Submission");

  form.setDescription(
    "Submit your Best in Slot list for raid loot priority.\n\n" +
    "• Enter your #1 BiS item and your #2 (second best) for every slot.\n" +
    "• Spell item names exactly as they appear in the Item Lookup sheet — " +
    "responses will be imported directly into the spreadsheet.\n" +
    "• If a slot is not relevant to your spec (e.g. OH for a 2H user), " +
    "enter \"N/A\" for both fields."
  );

  form.setCollectEmail(false);
  form.setLimitOneResponsePerUser(false);

  form.addTextItem()
    .setTitle("Name-Realm")
    .setHelpText("e.g. Flipdascript-Thrall — must match exactly as it appears on the Roster.")
    .setRequired(true);

  form.addTextItem()
    .setTitle("BiS List Link")
    .setHelpText("Link to your BiS list (Wowhead, Bloodmallet, Raidbots, etc.)")
    .setRequired(true);

  form.addSectionHeaderItem()
    .setTitle("Item Slots")
    .setHelpText(
      "For each slot, enter your #1 BiS item and your #2 (second best) item. " +
      "Enter \"N/A\" if a slot doesn't apply to your spec."
    );

  for (const slot of BIS_FORM_SLOTS) {
    form.addTextItem()
      .setTitle(`${slot.label} — #1 BiS`)
      .setRequired(true);

    form.addTextItem()
      .setTitle(`${slot.label} — #2 (Second Best)`)
      .setRequired(true);
  }

  form.setDestination(FormApp.DestinationType.SPREADSHEET, ss.getId());

  const exportSheet = ss.getSheetByName("Export") || ss.insertSheet("Export");
  exportSheet.getRange("A1").setValue("BiS Form URL");
  exportSheet.getRange("B1").setValue(form.getPublishedUrl());
  exportSheet.getRange("A2").setValue("BiS Form Editor URL");
  exportSheet.getRange("B2").setValue(form.getEditUrl());
  exportSheet.autoResizeColumn(2);

  SpreadsheetApp.getUi().alert(
    "✅ Form created!\n\n" +
    "Form URL (share this):\n" + form.getPublishedUrl() + "\n\n" +
    "Both URLs are also saved in the Export sheet."
  );
}

// ── Import Form Responses → BiS List ─────────────────────────────────────────

function importBiSFormResponses() {
  const ss       = SpreadsheetApp.getActiveSpreadsheet();
  const bisSheet = ss.getSheetByName(BIS_SHEET_NAME);

  const responseSheet = ss.getSheets().find(s => s.getName().startsWith("Form Responses"));
  if (!responseSheet) {
    SpreadsheetApp.getUi().alert('No "Form Responses" sheet found. Has anyone submitted the form yet?');
    return;
  }
  if (!bisSheet) {
    SpreadsheetApp.getUi().alert(`"${BIS_SHEET_NAME}" sheet not found.`);
    return;
  }

  const bisData   = bisSheet.getDataRange().getValues();
  const headerRow = bisData[1];

  const playerColMap = {};
  for (let c = 1; c < headerRow.length; c++) {
    const name = String(headerRow[c]).trim();
    if (name) playerColMap[name] = c + 1;
  }

  const slotRowMap = {};
  for (let r = 2; r < bisData.length; r++) {
    const label = String(bisData[r][0]).trim();
    if (label) slotRowMap[label] = r + 1;
  }

  const respData    = responseSheet.getDataRange().getValues();
  const respHeaders = respData[0];

  const colIdx = {};
  respHeaders.forEach((h, i) => { colIdx[String(h).trim()] = i; });

  const latestByPlayer = {};
  for (let r = 1; r < respData.length; r++) {
    const row       = respData[r];
    const nameRealm = String(row[colIdx["Name-Realm"]] || "").trim();
    if (!nameRealm) continue;
    latestByPlayer[nameRealm] = row;
  }

  let written  = 0;
  let warnings = [];

  for (const [nameRealm, row] of Object.entries(latestByPlayer)) {
    const playerCol = playerColMap[nameRealm];
    if (!playerCol) {
      warnings.push(`"${nameRealm}" not found in BiS List header row — skipped.`);
      continue;
    }

    for (const slot of BIS_FORM_SLOTS) {
      const [rowLabel1, rowLabel2] = slot.rows;
      const formTitle1 = `${slot.label} — #1 BiS`;
      const formTitle2 = `${slot.label} — #2 (Second Best)`;

      const val1 = String(row[colIdx[formTitle1]] || "").trim();
      const val2 = String(row[colIdx[formTitle2]] || "").trim();

      const sheetRow1 = slotRowMap[rowLabel1];
      const sheetRow2 = slotRowMap[rowLabel2];

      if (sheetRow1) {
        const v = (val1.toLowerCase() === "n/a") ? "" : val1;
        bisSheet.getRange(sheetRow1, playerCol).setValue(v);
      }
      if (sheetRow2) {
        const v = (val2.toLowerCase() === "n/a") ? "" : val2;
        bisSheet.getRange(sheetRow2, playerCol).setValue(v);
      }

      written++;
    }
  }

  let msg = `✅ Imported ${Object.keys(latestByPlayer).length} submission(s) — ${written} slot entries written.`;
  if (warnings.length > 0) msg += "\n\n⚠️ Warnings:\n" + warnings.join("\n");
  SpreadsheetApp.getUi().alert(msg);
}

// ════════════════════════════════════════════════════════════════════════════
// SECTION 5 — About Tab Creator
// ════════════════════════════════════════════════════════════════════════════

function createAboutTab() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();

  const existing = ss.getSheetByName('About');
  if (existing) ss.deleteSheet(existing);
  const sheet = ss.insertSheet('About');
  ss.moveActiveSheet(1);

  const C = {
    white:        '#FFFFFF',
    pageBg:       '#F8F7F4',
    headerBg:     '#1A1A1A',
    headerText:   '#FFFFFF',
    sectionBg:    '#F0EEE8',
    cardBg:       '#FFFFFF',
    cardBorder:   '#E0DDD5',
    officerBg:    '#FEF9EE',
    officerBorder:'#F5C842',
    raiderBg:     '#EEF4FE',
    raiderBorder: '#4A86E8',
    accentLine:   '#CCCCCC',
    labelText:    '#888880',
    bodyText:     '#3A3A38',
    mutedText:    '#6B6B68',
    calloutBg:    '#F0EEE8',
    calloutBorder:'#AAAAAA',
    badgeOfficer: '#FEF3CD',
    badgeRaider:  '#D6E4FC',
  };

  sheet.setColumnWidth(1, 32);
  sheet.setColumnWidth(2, 130);
  sheet.setColumnWidth(3, 130);
  sheet.setColumnWidth(4, 130);
  sheet.setColumnWidth(5, 130);
  sheet.setColumnWidth(6, 130);
  sheet.setColumnWidth(7, 130);
  sheet.setColumnWidth(8, 32);

  function bg(row, col, numRows, numCols, color) {
    sheet.getRange(row, col, numRows, numCols).setBackground(color);
  }

  function write(row, col, numCols, text, opts = {}) {
    const range = sheet.getRange(row, col, 1, numCols);
    if (numCols > 1) range.merge();
    range.setValue(text);
    range.setFontFamily('Arial');
    range.setFontSize(opts.size || 11);
    range.setFontWeight(opts.bold ? 'bold' : 'normal');
    range.setFontColor(opts.color || C.bodyText);
    range.setVerticalAlignment('middle');
    range.setWrap(true);
    if (opts.align) range.setHorizontalAlignment(opts.align);
    if (opts.italic) range.setFontStyle('italic');
    if (opts.rowHeight) sheet.setRowHeight(row, opts.rowHeight);
    return range;
  }

  function spacer(row, height = 10) {
    sheet.setRowHeight(row, height);
    bg(row, 1, 1, 8, C.pageBg);
  }

  function divider(row) {
    sheet.setRowHeight(row, 1);
    sheet.getRange(row, 2, 1, 6).setBorder(false, false, true, false, false, false, C.accentLine, SpreadsheetApp.BorderStyle.SOLID);
    bg(row, 1, 1, 8, C.pageBg);
  }

  function sectionLabel(row, text, badgeText) {
    sheet.setRowHeight(row, 22);
    bg(row, 1, 1, 8, C.pageBg);
    const r = sheet.getRange(row, 2, 1, 6);
    r.merge();
    r.setValue(text + (badgeText ? '   › ' + badgeText : ''));
    r.setFontFamily('Arial');
    r.setFontSize(9);
    r.setFontWeight('bold');
    r.setFontColor(C.labelText);
    r.setVerticalAlignment('middle');
  }

  function sheetCard(startRow, col, name, desc) {
    sheet.setRowHeight(startRow, 18);
    sheet.setRowHeight(startRow + 1, 32);

    const nameRange = sheet.getRange(startRow, col, 1, 2);
    nameRange.merge();
    nameRange.setValue(name);
    nameRange.setFontFamily('Arial');
    nameRange.setFontSize(10);
    nameRange.setFontWeight('bold');
    nameRange.setFontColor(C.bodyText);
    nameRange.setBackground(C.cardBg);
    nameRange.setVerticalAlignment('bottom');

    const descRange = sheet.getRange(startRow + 1, col, 1, 2);
    descRange.merge();
    descRange.setValue(desc);
    descRange.setFontFamily('Arial');
    descRange.setFontSize(9);
    descRange.setFontColor(C.mutedText);
    descRange.setBackground(C.cardBg);
    descRange.setVerticalAlignment('top');
    descRange.setWrap(true);

    sheet.getRange(startRow, col, 2, 2)
      .setBorder(true, true, true, true, false, false, C.cardBorder, SpreadsheetApp.BorderStyle.SOLID);
  }

  function officerCard(row, title, body) {
    sheet.setRowHeight(row, 18);
    bg(row, 1, 1, 8, C.pageBg);
    const titleR = sheet.getRange(row, 2, 1, 6);
    titleR.merge();
    titleR.setValue(title);
    titleR.setFontFamily('Arial');
    titleR.setFontSize(10);
    titleR.setFontWeight('bold');
    titleR.setFontColor(C.bodyText);
    titleR.setBackground(C.officerBg);
    titleR.setVerticalAlignment('middle');
    titleR.setBorder(true, true, false, true, false, false, C.officerBorder, SpreadsheetApp.BorderStyle.SOLID);

    const lines = Math.ceil(body.length / 90);
    const bodyHeight = Math.max(40, lines * 18 + 14);
    sheet.setRowHeight(row + 1, bodyHeight);
    bg(row + 1, 1, 1, 8, C.pageBg);
    const bodyR = sheet.getRange(row + 1, 2, 1, 6);
    bodyR.merge();
    bodyR.setValue(body);
    bodyR.setFontFamily('Arial');
    bodyR.setFontSize(10);
    bodyR.setFontColor(C.mutedText);
    bodyR.setBackground(C.officerBg);
    bodyR.setWrap(true);
    bodyR.setVerticalAlignment('top');
    bodyR.setBorder(false, true, true, true, false, false, C.officerBorder, SpreadsheetApp.BorderStyle.SOLID);

    return row + 2;
  }

  function callout(row, text) {
    const lines = Math.ceil(text.length / 95);
    const h = Math.max(36, lines * 17 + 12);
    sheet.setRowHeight(row, h);
    bg(row, 1, 1, 8, C.pageBg);
    const r = sheet.getRange(row, 2, 1, 6);
    r.merge();
    r.setValue('ℹ  ' + text);
    r.setFontFamily('Arial');
    r.setFontSize(10);
    r.setFontColor(C.mutedText);
    r.setBackground(C.calloutBg);
    r.setWrap(true);
    r.setVerticalAlignment('middle');
    r.setBorder(false, true, false, false, false, false, C.calloutBorder, SpreadsheetApp.BorderStyle.SOLID_MEDIUM);
  }

  sheet.getRange(1, 1, 120, 8).setBackground(C.pageBg);

  let r = 1;

  sheet.setRowHeight(r, 10); bg(r, 1, 1, 8, C.headerBg); r++;

  sheet.setRowHeight(r, 16); bg(r, 1, 1, 8, C.headerBg);
  write(r, 2, 6, 'TEAM PHOENIX', { size: 9, bold: true, color: '#888880', align: 'left', rowHeight: 16 });
  sheet.getRange(r, 2, 1, 6).setBackground(C.headerBg);
  r++;

  sheet.setRowHeight(r, 32); bg(r, 1, 1, 8, C.headerBg);
  write(r, 2, 6, 'Loot Priority Sheet', { size: 20, bold: true, color: C.headerText, rowHeight: 32 });
  sheet.getRange(r, 2, 1, 6).setBackground(C.headerBg);
  r++;

  sheet.setRowHeight(r, 22); bg(r, 1, 1, 8, C.headerBg);
  write(r, 2, 6, 'Transparent, data-driven loot distribution for raid progression.', { size: 11, color: '#AAAAAA', rowHeight: 22 });
  sheet.getRange(r, 2, 1, 6).setBackground(C.headerBg);
  r++;

  sheet.setRowHeight(r, 12); bg(r, 1, 1, 8, C.headerBg); r++;

  spacer(r); r++;
  sectionLabel(r, 'FOR RAIDERS', 'Raider'); r++;
  spacer(r, 6); r++;

  write(r, 2, 6, 'What this sheet is', { size: 13, bold: true, rowHeight: 26 });
  bg(r, 1, 1, 8, C.pageBg); r++;

  write(r, 2, 6,
    'This spreadsheet tracks loot priority for our raid team. It combines your submitted BiS lists with WarcraftLogs performance data to determine who gets first priority on each item when it drops. The goal is to distribute gear in a way that maximizes raid performance.',
    { size: 10, color: C.mutedText, rowHeight: 52 });
  bg(r, 1, 1, 8, C.pageBg); r++;

  spacer(r, 14); r++;
  write(r, 2, 6, 'What you need to do', { size: 13, bold: true, rowHeight: 26 });
  bg(r, 1, 1, 8, C.pageBg); r++;
  spacer(r, 6); r++;

  const steps = [
    ['1', 'Fill out the BiS list form with your #1 and #2 item choices for every slot. Spell item names exactly as they appear in the sheet.'],
    ['2', 'Include your BiS list link (Wowhead, Bloodmallet, Raidbots, etc.) so officers can cross-reference your choices.'],
    ['3', 'BiS lists are set at the start of the tier and do not change. If you genuinely need to update your list, message Katorri or Rod — do not resubmit the form on your own.'],
    ['4', 'Show up and perform. Priority scores are pulled from WarcraftLogs after each raid. Consistent performance improves your standing.'],
  ];

  for (const [num, text] of steps) {
    sheet.setRowHeight(r, 36);
    bg(r, 1, 1, 8, C.pageBg);

    const numCell = sheet.getRange(r, 2);
    numCell.setValue(num);
    numCell.setFontFamily('Arial');
    numCell.setFontSize(9);
    numCell.setFontWeight('bold');
    numCell.setFontColor(C.bodyText);
    numCell.setBackground(C.sectionBg);
    numCell.setHorizontalAlignment('center');
    numCell.setVerticalAlignment('middle');

    const textRange = sheet.getRange(r, 3, 1, 5);
    textRange.merge();
    textRange.setValue(text);
    textRange.setFontFamily('Arial');
    textRange.setFontSize(10);
    textRange.setFontColor(C.mutedText);
    textRange.setBackground(C.pageBg);
    textRange.setWrap(true);
    textRange.setVerticalAlignment('middle');

    sheet.getRange(r, 2, 1, 6)
      .setBorder(false, false, true, false, false, false, C.accentLine, SpreadsheetApp.BorderStyle.SOLID);

    r++;
  }

  spacer(r, 10); r++;
  callout(r, 'If a slot doesn\'t apply to your spec (e.g. Off Hand for a two-handed user), enter "N/A" for both fields. Don\'t leave it blank — blank entries are treated as incomplete submissions.');
  r++;
  spacer(r, 6); r++;
  callout(r, 'Need to change your BiS list? Message Katorri or Rod. Do not resubmit the form without officer approval.');
  r++;

  spacer(r, 14); r++;
  write(r, 2, 6, 'How priority is decided', { size: 13, bold: true, rowHeight: 26 });
  bg(r, 1, 1, 8, C.pageBg); r++;

  write(r, 2, 6,
    'When an item drops, officers check the Priority Order tab. Players who listed that item in their BiS appear in the dropdown, ordered by their current priority score. Officers use this alongside attendance, performance trend, and upgrade value to make the final call. The sheet informs the decision — it does not make it automatically.',
    { size: 10, color: C.mutedText, rowHeight: 58 });
  bg(r, 1, 1, 8, C.pageBg); r++;

  spacer(r, 18); r++;
  sectionLabel(r, 'HOW THE SHEET IS ORGANIZED'); r++;
  spacer(r, 8); r++;

  const cards = [
    ['Roster',           'Players, roles, and priority scores'],
    ['BiS List',         'Each player\'s top 2 item picks per slot'],
    ['Upgrade Values',   'Upgrade % for items like trinkets, weapons, rings, and necks'],
    ['Scoring',          'WCL performance scores (recent + trend)'],
    ['Priority Order',   'Ranked priority list used during raid'],
    ['Item Lookup',      'Master list of all raid items and slots'],
    ['Export',           'Generates the RCLootCouncil import string'],
  ];

  const cardCols = [2, 4, 6];
  for (let i = 0; i < cards.length; i++) {
    const col = cardCols[i % 3];
    if (i % 3 === 0 && i > 0) r += 3;
    sheetCard(r, col, cards[i][0], cards[i][1]);
  }
  r += 3;

  spacer(r, 20); r++;
  divider(r); r++;
  spacer(r, 10); r++;
  sectionLabel(r, 'FOR OFFICERS', 'Officer'); r++;
  spacer(r, 6); r++;

  write(r, 2, 6, 'Officer workflows', { size: 13, bold: true, rowHeight: 26 });
  bg(r, 1, 1, 8, C.pageBg); r++;

  write(r, 2, 6,
    'All officer actions are in the RCLPL and ⚔ Team Phoenix menus in the top toolbar.',
    { size: 10, color: C.mutedText, rowHeight: 28 });
  bg(r, 1, 1, 8, C.pageBg); r++;

  spacer(r, 10); r++;

  const officerCards = [
    ['Start of tier — setup',
     'Add all raid items to Item Lookup (name, item ID, slot). Run Set BiS List slot dropdowns to apply per-slot filtering. Share the BiS submission form link with raiders and give them a deadline. Once responses are in, run Import BiS form responses to populate the BiS List sheet.'],
    ['Before each raid — refresh scores',
     'Run Refresh WCL Performance Scores from the ⚔ Team Phoenix menu. Review the draft scores in columns J (Recent) and K (Trend). When satisfied, run Commit Draft Scores → Performance to write them to the Performance column and update loot priority standings.'],
    ['During raid — assigning loot',
     'When an item drops, find or add it in Priority Order and run Fill dropdowns for selected item row to show only eligible players. Use the ranked list alongside your judgment to assign. After each raid, run Export priority data and paste the output into /rclp import in-game. This syncs the full priority list to the RCLootCouncil_PriorityLoot addon, so loot council members can see who has priority on each item directly in the RCLootCouncil voting frame — no spreadsheet required during raid.'],
    ['Adding new items mid-tier',
     'Add the item to Item Lookup first. Re-run Set BiS List slot dropdowns to refresh BiS List validations. Then add the item to Priority Order and run Fill dropdowns for selected item row for that row.'],
  ];

  for (const [title, body] of officerCards) {
    r = officerCard(r, title, body);
    spacer(r, 8); r++;
  }

  spacer(r, 6); r++;
  callout(r, 'Tanks are marked "Manual" in the scoring columns and are never auto-populated by WCL. Update their Performance scores manually based on officer consensus.');
  r++;

  spacer(r, 24); r++;

  sheet.setRowHeight(r, 1);
  sheet.getRange(r, 2, 1, 6).setBackground(C.accentLine);
  r++;
  spacer(r, 10); r++;

  write(r, 2, 6, 'Last updated by officers via Apps Script › Rebuild About tab', {
    size: 9, color: C.labelText, italic: true, rowHeight: 20
  });
  bg(r, 1, 1, 8, C.pageBg); r++;

  spacer(r, 16); r++;

  sheet.setHiddenGridlines(true);
  sheet.setFrozenRows(0);
  sheet.setFrozenColumns(0);

  SpreadsheetApp.getUi().alert('✅ About tab created! It has been moved to the first tab position.');
}