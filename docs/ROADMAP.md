# RCLootCouncil_PriorityLoot - Roadmap

This roadmap turns the addon from a working v0.1.0 into a maintainable project that other people can contribute to safely. It is right-sized for a single guild's tool that will eventually publish to CurseForge for other officers, not for a hypothetical large OSS project.

Each item lists **acceptance criteria** so a contributor (or future maintainer) can tell when it is done. PRs should reference the roadmap item they belong to.

---

## Branching strategy

Single-purpose branches off `main`, one PR per branch. After the PR closes the branch is **frozen** (no new commits - start a fresh branch off `main` for follow-up work).

Branch name conventions:

| Prefix | Use |
|---|---|
| `chore/<topic>` | Repo hygiene: cleanup, lint, tests, CI, docs |
| `fix/<topic>` | Bug fix |
| `feat/<topic>` | New user-visible feature |
| `refactor/<topic>` | Internal refactor with no behaviour change |
| `docs/<topic>` | Doc-only change |

Examples: `chore/cleanup-dead-code`, `feat/tooltip-integration`, `fix/voting-frame-injection-race`.

## Commit and release conventions

- **Subject line**: imperative, max 72 chars, ends with `(vX.Y.Z)` parenthetical when the commit bumps the version.
- **Version bump**: every commit that ships behaviour bumps the version. Patch by default; minor for new commands or import schema additions; major for breaking changes (removed slash subcommand, breaking schema change, RCLootCouncil major-version dependency change).
- **CHANGELOG.md**: every commit updates it. Unreleased entries go under `## [Unreleased]`; on release the section is renamed to `## [X.Y.Z] - YYYY-MM-DD` and an empty `[Unreleased]` is added back.
- **Version sync**: `.toc`'s `## Version:` line, the CHANGELOG header, and any inline version constant must all agree.
- **Release**: tag the merge commit `vX.Y.Z`, push tag. `release.yml` builds the zip and creates the GitHub Release. Never tag a commit whose version files are stale.

See `CONTRIBUTING.md` for the full PR checklist.

---

## Phase 0 - Foundation (shipped in v0.1.1)

Lint, tests, CI, contribution docs, dev-environment recipe, hardened release workflow. No runtime behaviour change to the addon. See the v0.1.1 CHANGELOG entry for the full file list.

---

## Phase 1 - Hardening

Three real fixes in current behaviour. Ship in this order.

### 1.1 Strict import-string schema validation
Branch: `feat/strict-import-validation` · Version: patch

Currently `RCPL_Data_SaveImportedData` only checks types at the outer level. Officers paste user-shaped data; bad nested shapes drop silently with no feedback.

- Validate each `players[name][slotKey].bis` entry: array of integers, length up to 10, slot key in known set.
- Validate each `priority[itemID]` entry: itemID is a numeric string, list is array of strings matching `Name-Realm` format.
- Reject and report counts of invalid entries instead of silently dropping. Show counts in the chat success line and in the `/rclp prio` subtitle.
- Tests: malformed inputs at every level produce specific error messages; valid input still parses identically to today.

**Acceptance:** `spec/import_save_spec.lua` gains coverage for at least 6 invalid-shape scenarios. The chat output on a partial-bad import says "imported N players, M priority items, K invalid entries dropped."

### 1.2 Centralised logging — shipped in v0.1.7

`Modules/log.lua` ships with `debug`, `info`, `warn`, `error` levels behind a chat prefix of `|cFF00FF00[RCLP]|r`. Every call records into a 500-entry in-memory ring buffer regardless of debug state; `debug` calls only mirror to chat when `RCLPriorityDB.debug` is true. New slash surface: `/rcpl debug` toggles the persisted flag, `/rcpl log` opens an AceGUI viewer over the recorded history (with `dump` and `clear` subcommands).

The diagnostic instrumentation in `Core.lua` covers the lifecycle (`OnInitialize`, `OnEnable`) and the comm flow (`BroadcastVersion`, `OnVersionReceived`, `OnVersionCheckMessage`). Together this is enough to see whether the version-check broadcast fires, what `IsInGuild()` reported, what comm prefixes registered, and what arrived from each sender.

Two follow-ups deferred:

- Replacing the remaining `print(...)` calls in `Data/db.lua`, `Modules/importFrame.lua`, and the `/rcpl version` ordinal table is left for a later pass; v0.1.7 routes only the lifecycle and comm paths through the logger because that is where the open diagnostic gap lives.
- Re-introducing error logging in `Modules/lootFrame.lua:65` (the pcall whose `err` was dropped during Phase 0 lint cleanup) lands with whichever PR next touches that file.

### 1.3 Idempotent import + import diff
Branch: `feat/idempotent-import` · Version: patch

Current `SaveImportedData` wipes `RCLPriorityDB.players` and `.priority` before writing. If the second loop errors mid-way, you have corrupted state.

- Build the new tables locally, then atomically swap.
- Compute and print a diff: "X players added, Y changed, Z removed; A items added, B items removed."
- Show the same diff in the `/rclp prio` subtitle when last-import data is recent.
- Include a stale-data note in the subtitle when `importedAt` is more than 7 days old (folds in roadmap item 1.4 below as a 5-line addition; no separate PR).
- Tests: simulate mid-import error, assert old data preserved; assert diff calculation against synthetic before/after fixtures.

**Acceptance:** `spec/import_save_spec.lua` gains "mid-import error preserves prior state" plus diff-calculation specs. Subtitle in `/rclp prio` shows the diff and the stale-data note when applicable.

---

## Phase 2 - UX

### 2.1 Item tooltip integration
Branch: `feat/tooltip-integration` · Version: minor

Highest-value feature on the roadmap. Hover any item with a known itemID (bag, bank, AH, equipment manager, chat link) and see priority text in the tooltip.

- Hook `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)` (modern 12.0.5 API; older `OnTooltipSetItem` is deprecated).
- For the local player by default; when `priority[itemID]` exists, also show "Top priority: PlayerA, PlayerB, PlayerC" line so officers can see at a glance.
- Skip secondary slots (defer to wowaudit's own tooltip integration).
- Tests: tooltip handler called with known item produces expected lines via mock GameTooltip.

**Acceptance:** hovering items in bag, bank, AH, and equipment manager all show the priority line. Items without a known itemID (e.g. quest items, currencies) no-op without errors.

### 2.5 Slash command UX
Branch: `feat/slash-ux` · Version: minor (new subcommands)

- `/rcpl status` - prints counts (players, priority items), `importedAt`, days-old, debug state.
- `/rcpl export` - re-encodes current `RCLPriorityDB` to base64 for backup or cross-account share. Uses the same JSON shape as the import format, so an export round-trips through `/rcpl import`.
- Keep existing `/rcpl`, `/rcpl import`, `/rcpl prio`, `/rcpl reset`.

**Acceptance:** both new subcommands have specs covering output shape and round-trip.

### 2.6 Version check — raid leader out-of-date report
Branch: `feat/version-check-leader-report` · Version: minor

Currently the guild broadcast tells each officer individually when someone has a newer version. There is no surface that gives the raid leader a view of who in the group is running an outdated version on login or `/reload`.

- On `BroadcastVersion`, if the local player is the raid or party leader, collect version replies from all group members (reuse the `RCPL_Ver` WHISPER reply flow) and after a short timeout (same pattern as `/rcpl version`) print a single report to the leader only: green for current, yellow for outdated, grey for no addon.
- Only fires when the player is group leader to avoid spamming every member on login.
- Report is printed to chat with the `[RCPL]` prefix, not broadcast to the group.
- No new slash command needed; this is automatic on login/`/reload` when leading a group.
- Tests: mock `IsRaidLeader`/`IsPartyLeader`, simulate version replies, assert correct colour-coded output.

**Acceptance:** logging in or `/reload`-ing as the active raid/party leader prints a per-member version summary to the leader's chat. Non-leaders see nothing extra.

---

## Phase 3 - Loot integration

### 3.2 Tier-set awareness
Branch: `feat/tier-set-awareness` · Version: minor (additive schema field)

Tier-set 4-piece bonuses are a meaningful DPS/HPS swing in modern WoW. Tracking each player's current tier-piece count lets officers prioritise tokens to players who would gain the most (e.g. a player at 2/4 over a player at 4/4 holding the same itemID at the same rank). Without this, the priority column tells officers "Alice is 1st on this item" but not "Alice is already 4/4 and the bonus is moot."

- Extend the import schema: `players[name].tierPieces = N` (single integer 0..4 for the current season; or `{ N, M }` if the addon ever needs to track two simultaneous set bonuses). Backward compatible: missing field treated as nil.
- Surface in the voting frame `Priority` column: append "(N/4)" suffix when known. Colour adjusts when the player would hit a bonus threshold (2/4 or 4/4) with the current item.
- Surface in `/rclp prio` per-player roster line.
- `SpreadsheetExport.gs` companion change: add a "Tier Pieces" column to the Roster sheet, fold into the export.
- Tests: additive schema does not break v0.1.0-shape imports; resolver returns the suffix; voting frame DoCellUpdate handles missing `tierPieces` as no-suffix.

**Acceptance:** importing a roster with `tierPieces` data produces visible "(2/4)" / "(4/4)" annotations in both the voting column and the prio preview. Old-shape imports without `tierPieces` still work and show no suffix.

### 3.4 RCLootCouncil award integration
Branch: `feat/rcl-award-integration` · Version: minor

Closes the loop: when an officer awards an item via RCLootCouncil, the priority entry is consumed so the same item does not re-surface as "1st" for that player on a subsequent drop.

- Hook RCLootCouncil's awarding flow (probably `RCLootCouncilML:GiveLoot` or the `RCMLAwardSuccess` AceComm message; investigate at implementation time).
- Persist in `RCLPriorityDB.awarded[itemID][playerName] = timestamp`.
- `/rclp prio` filters out awarded items by default; `/rclp prio all` shows them.
- Voting frame `Priority` column shows "(received)" suffix in grey for already-awarded items so officers know not to assign again.
- For tier tokens specifically (Phase 3.2): an award also bumps the awardee's `tierPieces` count, so the "(N/4)" suffix updates without a re-import.
- Tests: simulated award message updates the saved table; resolver respects the filter; tier-token awards bump tierPieces.

**Acceptance:** awarding an item once removes that player+item pair from outstanding priority; `/rclp prio all` still surfaces it for audit. Tier-token awards bump the awardee's tier count by 1.

---

## Phase 4 - Public release

### 4.1 CurseForge publishing
Branch: `chore/curseforge-publish` · Version: patch

Triggered when the project is ready to share with other officers outside this guild.

- Add `pkgmeta.yaml` for [BigWigsMods/packager](https://github.com/BigWigsMods/packager).
- Extend `release.yml` with a packager job that uploads to CurseForge (and optionally WowInterface) using `CF_API_KEY` (and `WOWI_API_TOKEN`) repo secrets.
- Document the secret-setup flow in `CONTRIBUTING.md`.
- Make repo public, or grant CurseForge integration access to the private repo via the BigWigsMods packager docs.
- Decide on CurseForge slug, project description, license, supported game versions.
- First public release notes: a short "What this is, who it's for" intro before the v-number changelog entry.

**Acceptance:** a tag push results in both a GitHub Release and a CurseForge release artefact.

### Spreadsheet companion versioning (housekeeping)

Not a milestone. Next time `SpreadsheetExport.gs` is touched, add a `// Version: X.Y.Z` header at the top and bump it on each change. Document the supported sheet schema in `docs/` if it grows beyond what the README covers.

---

## Maybe (parked for explicit signal)

These items were considered and parked until a real usage signal warrants them. Documented here so they are not forgotten and so future contributors can see prior reasoning.

### 1.4 Stale-data login warning
A "your import is N days old" nag at PLAYER_LOGIN. Risk: goes from useful to muted within two weeks. Phase 1.3 already shows the staleness in `/rclp prio` subtitle, where the user already opened the UI. Promote to keep only if officers report missing the in-UI surface.

### 2.4 Diff viewer on re-import
Visual tab in `/rclp prio` showing colour-coded added/changed/removed rows from the most recent import. Phase 1.3's chat-output diff covers the data; visual viewer is polish on polish. Promote when an officer asks.

### 3.1 Multi-team profiles
N named profiles in `RCLPriorityDB.profiles[name]` with active-profile pointer. Real value if you run this addon for more than one raid team; zero value otherwise. Promote when juggling teams becomes real, or when another guild adopts the addon and asks. If promoted, schema change cascades through Phases 1 and 2 - so decide before Phase 1.1 ships if possible.

### 3.3 Item-level threshold
Optional `RCLPriorityDB.minILvl`. Distinguishes "below threshold" from "not in BiS" with a different label. Reviewer-only ergonomics; promote on request.

---

## Tracking

Each shipping item maps to a GitHub Issue tagged with its phase (`phase-1`, `phase-2`, ...). Milestones group phases. PRs reference issue numbers.

The CHANGELOG is the source of truth for what shipped; this roadmap describes intent.
