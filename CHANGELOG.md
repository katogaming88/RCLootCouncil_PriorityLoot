# Changelog

All notable changes to RCLootCouncil_PriorityLoot will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).  
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **A stale-data indicator.** `/rcpl prio` now colors its "Imported: ..." timestamp green/yellow/orange by age (1 day / 3 days), instead of showing a bare date with no sense of how old it is. A raid/party member also now gets a one-time chat warning (per stale streak, not repeated every roster change) if their loaded priority data is more than 3 days old, nudging them to `/rcpl sync` or ask an officer to `/rcpl broadcast` a refresh.
- **Wishlist tier tags in the officer voting frame's "Full Priority Order" panel.** Each ranked name can now show `(BiS)`/`(2nd Choice)`/`(Sidegrade)` (or whatever your team's actually-configured Wishlist Tier Labels say -- pulled from the WGA Raid Hub export, not hardcoded) next to it, so an officer can tell a real BiS pick apart from a lower-tier pick that still made the ranked list, or a rank with no wishlist entry behind it at all (no tag). Loot-council-only by design -- never shown on the raider-facing loot roll frame or the Priority column. Requires a WGA Raid Hub export from after [#760](https://github.com/katogaming88/WGA-Raid-Hub/pull/761); older exports simply show no tags.

### Fixed

- **The loot roll frame could show a stale, wrong priority rank on a recycled entry widget.** RCLootCouncil reuses its own entry widgets across different loot drops that share the same button-config type -- with only a `default` (Upgrade/Catalyst/OS+M+) and a `tier` (Gives 1pc/2pc/etc.) type configured, that means *any* two non-tier items can share one, not just two of the same slot. A trashed widget from an earlier item gets handed to whatever non-tier item drops next, but our `Update` hook closed over the item from the first time that particular widget was hooked and never refreshed it, so the appended priority text kept describing whatever item the widget was originally created for -- even though RCLootCouncil's own icon/name/ilvl text was correct for the new item. This is the confirmed cause of a report where a raider's loot frame showed "Prio: 3rd" on an item they were actually ranked 14th on (their stored priority data was current and correct throughout -- the display was reading the wrong item). The hook now reads the entry's own current `.item` field (set by RCLootCouncil itself on every `Update` call, before any text is touched) instead of the stale closure.
- **Item-centric priority lookup could return a same-named player's rank on a different realm instead of your own.** The loot frame and voting frame matched the ranked priority list by bare character name as soon as an exact `Name-Realm` match failed to appear yet, so a raider could see e.g. "Prio: 3rd" when their real rank was 14th, because a different-realm namesake happened to rank 3rd and was scanned first. Exact `Name-Realm` matches are now always checked across the whole list before falling back to a bare-name match.
- **Two prio-sync rejection warnings could spam chat once per roster change, all raid long.** Unlike every other warning in `Modules/prioSync.lua`, the "not the leader" and "keeping your own imported data" rejection messages had no de-duplication, so a client stuck in either state (e.g. a raider who'd previously run their own `/rcpl import`, now permanently differing from the leader's rebroadcasts) got the same line reprinted on every roster-change resync all night. Both now warn once per distinct rejected payload instead of on every receipt.

---

## [0.6.13] - 2026-08-25

### Changed

- **The debug log now persists in SavedVariables (`RCPL_DB.log`) instead of an in-memory buffer that reset on every `/reload`** -- same approach the base RCLootCouncil addon's own logger uses. Entries are still capped at the last 500 and are still recorded regardless of whether `/rcpl debug` is on, but now survive `/reload` and logout, so `/rcpl log` can be checked after a raid to diagnose something that happened earlier, instead of needing debug mode enabled and the window pulled up in the moment.

---

## [0.6.12] - 2026-08-25

### Fixed

- **An item with a tertiary stat or socket it doesn't normally carry could show the wrong priority rank (e.g. "1st" for a player who was actually 4th).** `instanceDifficultyID` -- the field in a real item link that tells the addon whether a drop is Heroic or Mythic -- was being read one field too late (field 12 instead of field 11), which happened to land on `numBonusIDs` instead. A plain item with few bonus IDs rarely tripped this, but an item with extra bonus IDs (an unusual tertiary stat and/or a socket) could produce a `numBonusIDs` value that coincidentally matched a real difficulty ID (14/15/16), silently pointing the lookup at the wrong track's priority list. Confirmed against this account's own saved item links and fixed with regression coverage for both a Heroic drop carrying extra bonus IDs and a bonus-ID count that collides with a real difficulty ID.

---

## [0.6.11] - 2026-08-21

### Fixed

- **Normal-difficulty items showed "N/A (unknown raid difficulty)" in the voting/loot frame Priority column, even though the difficulty is perfectly well known.** `RAID_DIFFICULTY_TRACK` only mapped Heroic (15) and Mythic (16) difficulty IDs to a track, so a Normal drop (14) -- whether read from the item link's own `instanceDifficultyID` or a live Normal raid instance -- always resolved to no track at all, which triggered the "unknown difficulty" message meant for a genuinely ambiguous case (e.g. the overlapping Heroic/Mythic item-level band). Normal is now mapped to its own `"N"` track, so it resolves cleanly and (since WGA Raid Hub doesn't export Normal priority data) correctly falls through to a plain "N/A" instead.

---

## [0.6.10] - 2026-08-21

### Fixed

- **Cloak/Wrist/Waist/Feet items always showed a generic "no priority for this slot" message in the voting and loot frames, even when WGA Raid Hub had already exported a real ranking for the item** -- confirmed live: the Full Priority Order side panel showed a 5-player ranking for a Waist item while every row in the voting frame said there was no priority for it. These four slots used to have no per-player BiS category at all and always deferred to a separate message, back when WGA Raid Hub didn't track them. It tracks (and exports priority for) every slot now, so the special case is gone entirely -- Cloak/Wrist/Waist/Feet are ordinary slots like any other, checked against the item-centric priority list first and the per-player BiS list second, same as Head/Chest/Legs/etc.

---

## [0.6.9] - 2026-08-21

### Fixed

- **The loot/voting frame's Priority said "Awarded" for an item already given out on a lower difficulty, even when the current drop was a genuine upgrade the player still needed.** The awarded check only ever looked at whether *any* award for that item existed, with no regard for which track it was on. It now compares the stored award's track against the current drop's track and only short-circuits to "Awarded" when the past award is the same track or better -- a Heroic award no longer suppresses priority for a fresh Mythic-track drop of the same item. An award with no resolvable track on either side (legacy data, or a drop whose track genuinely can't be determined) keeps the old unconditional behavior.

---

## [0.6.8] - 2026-08-21

### Fixed

- **The voting frame's Priority column showed "N/A" for most raiders on the viewer's own (or a connected) realm, even though they were plainly ranked in the exact same list the Full Priority Order side panel prints in full.** The exported priority list always stores full "Name-Realm" strings, but RCLootCouncil hands the voting frame a bare name (no realm suffix) for any candidate the game treats as the viewer's own realm. The lookup only ever compared that bare name (or a realm-stripped version of it) against the full stored name, so it could only ever match a genuinely cross-realm candidate. It now also checks whether the *stored* name's own realm-stripped form matches, the same fallback already used for the bonus-roll-tracking lookup.

---

## [0.6.7] - 2026-08-18

### Fixed

- **Every roster-change resync rebroadcast the leader's priority data to the whole group, and each recipient printed a "Priority data synced" chat line even when the data hadn't changed** -- flooding chat on every join/leave/reload during a raid. Incoming sync data identical to what's already stored is now applied silently, with the chat line only printed when the data actually changes.
- **A player who imported their own priority string could have it silently overwritten by a differing leader broadcast.** `RCPL_DB` now tracks whether stored data came from a local `/rcpl import` or from a group sync; a leader's differing broadcast is rejected (with a chat warning) when the local data was self-imported, rather than silently applied. `/rcpl reset` clears the protection if you do want to pick up the leader's data instead.

---

## [0.6.6] - 2026-08-17

### Fixed

- **A non-leader with priority data already loaded got spammed with "Not sent -- only the raid/party leader's priority data syncs to the group" once per roster change, all raid.** `Broadcast()`'s non-leader chat warning was meant for an explicit user action (`/rcpl import`, `/rcpl broadcast`) but was also firing from the silent background roster-update resync every time anyone joined the group, and from auto-replying to another client's `/rcpl sync` request. Both of those paths are now silent (still logged for `/rcpl debug`) -- only a direct `/rcpl import`/`/rcpl broadcast` attempt still tells you why it wasn't sent.

---

## [0.6.5] - 2026-08-17

### Changed

- **Migrated the Priority and Bonus voting-frame columns to RCLootCouncil 3.23.0's official Column API** (`RCVotingFrame:AddColumn()`/`:GetColumnIndex()`), replacing direct `scrollCols` table manipulation. That old approach is "preserved for backwards compatibility" per RCLootCouncil's own 3.23.0 changelog but is expected to eventually be removed -- migrating now while it's a small, mechanical, behavior-preserving change (same columns, same position, same look) avoids a scramble later. No user-facing change.

---

## [0.6.4] - 2026-08-17

### Fixed

- **The "Full Priority Order" side panel (`Modules/votingPriorityPanel.lua`) could fail to reappear after a raid lead/Master Looter handoff.** It tracked visibility by hooking `RCVotingFrame:Show()`/`:Hide()`, the Ace3 module's own wrapper methods -- but `RCVotingFrame:Show()` has an internal guard that can leave the real frame hidden even though `:Show()` was called (our hook still fired regardless), and any code path that shows/hides the underlying frame object directly wouldn't reach a method-level hook at all. In current retail RCLootCouncil treats raid lead and Master Looter as the same thing, so a lead pass forces its own session-state resync -- confirmed live as the trigger. Now tracks the actual Blizzard frame's own `OnShow`/`OnHide` script instead, which fires for every real visibility change no matter what caused it.

---

## [0.6.3] - 2026-08-17

### Added

- **A client with no priority data loaded now gets a proactive chat warning a few seconds after joining/forming a raid or party, instead of silently sitting on an empty voting-frame side panel and N/A loot overlays with no indication why.** Easy to hit on a client that's a version or two behind (missed the import-status/reload-prompt fixes, or predates the sync module existing entirely, meaning it was never even subscribed to receive anyone else's broadcast). The raid/party leader gets told to `/rcpl import`; anyone else gets an automatic `/rcpl sync` request sent on their behalf, plus a nudge to ask the leader for a manual `/rcpl broadcast` or check their addon is up to date if it doesn't resolve. Fires once per empty streak (resets if data later arrives, so it can warn again if it goes empty a second time), not on every roster change.

---

## [0.6.2] - 2026-08-17

### Fixed

- **The item-level Heroic/Mythic detection fallback (`Data/db.lua`'s `TrackFromItemLevel`) was still using Season 1's item level ranges (Heroic 259-276, Mythic 272-289), now stale after Season 2's launch.** A Season 2 item (e.g. Ula'tek's Abyssal Broodfiend's Bardiche, ilvl 305) fell outside both old ranges entirely, so this fallback silently returned nothing -- and since a `/rc test` link never carries the primary `instanceDifficultyID` signal by design, that left `/rc test` runs and other synthetic links unable to resolve a track at all this season. Updated to Season 2's actual ranges: Heroic 305-321, Mythic 318-344 (the 318-321 overlap stays genuinely ambiguous, same as before).

---

## [0.6.1] - 2026-08-17

### Fixed

- **CurseForge uploads were silently failing** -- `.github/workflows/release.yml` set `CF_API_TOKEN`, but the pinned `BigWigsMods/packager@v2` action (resolves to v2.5.1, predating upstream's env var rename) only reads `CF_API_KEY`. `release.sh`'s `upload_curseforge()` returns immediately with no error or log output when its token variable is empty, so v0.6.0's zip and GitHub Release published fine while the CurseForge upload never even attempted. Now sets both env vars to the same token.

---

## [0.6.0] - 2026-08-17

### Added

- **Priority/BiS data now syncs to the raid or party automatically, instead of staying local to whoever ran `/rcpl import`.** Previously `RCPL_DB` was purely per-account SavedVariables -- only the officer who pasted the export string had it, so every other officer's voting frame and every raider's loot frame showed nothing until they each separately ran their own import. A successful import now broadcasts the data group-wide right away; a client that reloads or joins mid-raid also gets automatically resynced a few seconds after the roster changes, picking up whatever the group already has. `/rcpl broadcast` (re-)sends your own data on demand; `/rcpl sync` asks the group to send you theirs -- both useful if the automatic paths miss a particular client. Built on RCLootCouncil's own `Services.Comms` (same mechanism `RCLootCouncil_wowaudit` uses for its wishlist sync), so large payloads are compressed and chunked automatically. **Only the current raid/party leader's data ever actually reaches anyone else.** A non-leader who tries `/rcpl import` while grouped gets refused outright (naming the leader, and the timestamp of the leader's existing import if there is one) instead of saving priority data locally that nobody else in the raid will ever see. Applies while ungrouped too (the normal pre-raid import workflow) since there's no leader to defer to yet.

### Fixed

- **The import screen's success/failure message (and the "Reload UI now?" prompt) now checks both the player and priority entry counts, not just player count.** Previously an import with real ranked-priority data but zero BiS-wishlist entries (a legitimate, common state -- BiS wishlist is a separate, optional layer) showed "Import succeeded but contained no player entries" as if it had failed, and -- more importantly -- skipped the reload prompt entirely. Since SavedVariables only get flushed to disk on a UI reload/logout, the priority data those officers imported lived in memory only; the next `/reload` or relog silently discarded it with no warning, and the rolling/voting frames went back to showing nothing.

---

## [0.5.0] - 2026-08-09

### Added

- **A "Bonus" column on the voting frame flags any candidate who already used their weekly Bonus Roll on the current boss.** RCLootCouncil already tracks this itself (broadcast group-wide, reset every ENCOUNTER_END) for its own non-tradeable icon strip -- this surfaces the same signal as a plain "BONUS" label next to the Priority column, so officers can see at a glance that a candidate already had an independent shot at this boss's loot table before deciding who gets the normal drop.

---

## [0.4.0] - 2026-08-06

### Changed

- **All addon windows now share one dark/gold tooltip-style look.** Options, Priority Preview, Season Awards, Version Checker, Import, the Full Priority Order voting panel, and the Log window previously each carried their own copy of the old tiled red-and-stone Blizzard DialogFrame skin (or, for the Log window, a completely different AceGUI-drawn frame that couldn't match at all). They now all pull from a single shared style (`Modules/frameStyle.lua`): a solid near-black background, thin gold border, and a gold header strip behind the title. Every custom action button across these windows (Import's Confirm, Season Awards' Remove Award, Version Checker's Guild/Group, and all of the Options panel's action buttons) got the same flat dark/gold treatment in place of the default red Blizzard button art.
- **Priority ranks below 3rd now render grey instead of orange.** Previously every rank from 3rd onward shared the same orange, so a long priority list gave no visual cue for who's actually in realistic contention. Rank 1 stays green, 2 stays yellow, 3 stays orange, and 4th onward now fades to grey -- consistent everywhere the shared rank color is used (loot frame overlay, voting frame Priority column, Priority Preview, and the Full Priority Order panel).
- **The raider-facing loot frame overlay now says "On your wishlist" instead of "On your BiS list".** Wording update to match current wishlist terminology; no behavior change.

---

## [0.3.0] - 2026-07-13

### Added

- **Minimap button.** A LibDataBroker/LibDBIcon launcher icon so officers can open the Options panel without remembering `/rcpl`. Left-click opens Options; position and shown/hidden state persist via SavedVariables (`RCPL_DB.minimap`). A "Show minimap button" checkbox in the Options panel toggles it on or off, defaulting to shown. Also registers with Blizzard's native Addon Compartment (the dropdown next to the minimap) as a second, independent way to reach the same Options panel -- and being a standard `LibDBIcon` button means third-party minimap button collectors (MBB, ButtonForge, etc.) already recognize it with no extra work.

---

## [0.2.8] - 2026-07-12

### Changed

- **`TrackFromItemLevel` now checks a range per track instead of one exact ilvl, take two.** The overlap band from 0.2.7's range fix (272-276) is left genuinely ambiguous rather than guessed, and the resolution is now logged in full (`isPreview`, `baseItemLevel` included) at every step of the track-detection chain to make future `/rc test` discrepancies easier to diagnose.
- **The raider-facing "On your BiS list" loot frame overlay now still shows the difficulty tag.** Past `RAIDER_RANK_REVEAL_THRESHOLD`, the exact rank is hidden and replaced with "On your BiS list" -- previously this also silently dropped the Heroic/Mythic label that a shown rank gets, so a raider past the threshold had no way to tell which difficulty's drop they were looking at. Now shows e.g. "On your BiS list (Heroic)".

---

## [0.2.7] - 2026-07-12

### Added

- **Full priority order side panel on the officer voting frame.** A new panel attached to the right edge of the voting frame shows the complete saved priority order (every ranked player, both Heroic and Mythic) for whichever item is currently selected in the session -- the existing "Priority" column only shows each *candidate's* own rank, not the full list. Shows/hides in sync with the voting frame itself, and updates automatically on `RCSessionChangedPre` as the officer switches between items. Falls back to "No saved priority order for this item" when the item has no saved `priority_order` entry. Leads with whichever track the selected drop actually is (labeled "this drop"), falling back to the fixed Heroic-then-Mythic order when the track can't be resolved.

### Changed

- **`TrackFromItemLevel` now checks a range per track instead of one exact ilvl.** Item level climbs per boss within a raid tier -- an early boss's Heroic drop is a lower ilvl than a later boss's Heroic drop on the same difficulty -- so a single hardcoded "the Heroic ilvl" could only ever match one specific boss's items, not the whole difficulty. Season 1 (per Kat): Heroic 259-276, Mythic 272-289 -- these overlap at 272-276, which is left genuinely ambiguous (returns unresolved rather than guessed) since item level alone can't tell the two apart in that band. Still only matters for `/rc test`'s synthetic links; `instanceDifficultyID` (the primary signal) resolves every real drop correctly regardless of which boss it came from.

---

## [0.2.6] - 2026-07-12

### Added

- **Bare `/rcpl` opens an Options panel instead of printing a command list to chat.** A real button per action that opens a window with no required arguments (Import, Priority Preview, Season Awards, Version Checker, Check Guild Now, Toggle Debug Logging, Open Log) -- click one and it runs immediately, no need to type the full command. `reset`/`award`/`unaward` stay as reference-only text rows since they're either destructive or need typed arguments a click can't supply.

---

## [0.2.5] - 2026-07-12

### Changed

- **Raider loot roll overlay no longer shows the exact priority rank past 5th.** A raider who sees "Prio: 8th" tends to just not bother clicking Upgrade/OS/M+ -- and since a non-click reads to the loot council as "doesn't want it right now," that can quietly hide someone from a deliberate override the council would otherwise make (e.g. a bigger upgrade for someone further down the priority list). Ranks 1st-5th still show the exact position; beyond that the overlay just says "On your BiS list" instead. `RCPL_Data_GetPlayerPriority` now returns the raw numeric rank as a fourth value so `Modules/lootFrame.lua` can apply this threshold -- the officer voting frame (`Modules/votingFrame.lua`) ignores it and keeps showing the exact rank to officers regardless.

---

## [0.2.4] - 2026-07-12

### Added

- **`/rcpl version` now opens a real window instead of printing to chat**, mirroring base RCLootCouncil's own version checker (`Modules/versionCheck.lua`): opens immediately showing just your own version, with separate **Guild** and **Group** buttons that trigger the actual poll -- never an automatic/implicit one. Seeds a "Waiting..." row for every expected recipient up front (every current raid/party member, or every online guild member) and updates rows live as replies arrive, rather than batching everything into one chat dump after a fixed timeout. Rows still color-code the same way the old chat output did (green = same version, orange = you're behind, yellow = they're behind). `/rcpl version guild` is a shortcut that opens the window and immediately fires the guild poll, for chat-only workflows.

### Fixed

- **`/rcpl version` compared against a version constant frozen at "0.2.0" since 0.2.1.** `RCPL_VERSION` was a hardcoded string that never got bumped alongside three real releases (0.2.1-0.2.3), silently defeating the whole point of the check -- now read live from the `.toc`'s own `## Version` via `GetAddOnMetadata`, one source of truth.
- **The version-check REQUEST-reply handler recomputed the replier's own current group state instead of mirroring the channel the request arrived on.** A guild-wide check needs replies from guildies who aren't in the requester's raid/party (or aren't grouped at all) -- recomputing `IsInRaid()`/`IsInGroup()` on the replying end would silently drop exactly those replies. Now replies on whatever channel (`RAID`/`PARTY`/`GUILD`) the request actually came in on.

---

## [0.2.3] - 2026-07-12

### Changed

- **`/rcpl prio` window: color-coded ranks, bigger text, and grid layout (#27).** Each ranked player entry now shows in the same green/yellow/orange scheme (rank 1/2/3+) the voting/loot frame overlay already uses, via a new `RCPL_Data_RankColor` public wrapper around `Data/db.lua`'s existing color logic -- instead of every rank blending into one flat grey line. Ranked lists and the player roster now lay out as a fixed-width grid (3 per row) rather than one long word-wrapped string, so a long list wraps predictably instead of however the FontString happens to break. Items within the Priority Lists section are now separated by a lighter dotted divider instead of just a blank line. Body text bumped from `GameFontNormalSmall` to `GameFontNormal` (frame widened to match), and each track's Heroic/Mythic heading is bumped further still (`GameFontNormalLarge`, white instead of grey) so it doesn't recede behind the ranked players it's labeling.
- **Loot roll frame priority text is bigger, shows the difficulty, and reuses RCLootCouncil_wowaudit's empty space when it's not installed.** The "Prio: 2nd" text `lootFrame.lua` shows for each loot roll entry is now `GameFontNormal` instead of `GameFontNormalSmall`, and includes which track the rank is for (e.g. "Prio: 2nd (Heroic)") since Heroic and Mythic priority for the same item can genuinely differ -- `RCPL_Data_GetPlayerPriority` now returns the resolved track as a third value, and a new `RCPL_Data_TrackLabel` wrapper turns it into the same "Heroic"/"Mythic" label `/rcpl prio` already used (that window's own local copy of the label table is gone, now sharing this one). When `RCLootCouncil_wowaudit` is loaded, the text still renders as its own line below the entry, same as before (that addon owns the inline itemLvl line with its own wishlist annotation). When it's *not* loaded, the priority text is appended directly onto that itemLvl line instead -- the same technique wowaudit itself uses -- rather than adding a second line no one else needed the space for.

### Fixed

- **Loot roll frame priority text duplicating (e.g. "Prio: 2nd (Mythic) Prio: 2nd (Mythic)"), worse with every button click.** The RCLootCouncil_wowaudit-style inline append (added earlier in this same release) called `UpdateEntry` from two places for the same refresh: directly in the `GetEntry` hook body, and via a hook on the entry's own `Update` method. `EntryManager:GetEntry`'s "restored" branch (reusing a pooled entry) calls `entry:Update(item)` *inside* the original `GetEntry` -- for an already-hooked entry that triggered the `Update` hook during the very same `GetEntry` call the direct call then ran again, appending the priority text a second time onto a text field that already had it, once per click of Upgrade/Catalyst/Pass/etc. as the frame kept re-rendering. Now only calls `UpdateEntry` directly the one time the `Update` hook is first attached (covering a brand-new entry, whose own internal `Update` call already ran *before* it could be hooked).
- **`/rcpl prio` window can show a stale "Item #12345" instead of the item's name.** `GetItemInfo(itemID)` returns `nil` immediately for an item the client hasn't cached yet (never seen in a tooltip, the auction house, etc. this session) and fetches it asynchronously in the background -- the window only ever looked it up once, at populate time, so an uncached item was stuck on the ID fallback until the window happened to be manually reopened. Now requests the data (`C_Item.RequestLoadItemDataByID`) and listens for `GET_ITEM_INFO_RECEIVED` to redraw automatically once it resolves.
- **`## Interface` declares both 120007 and 120100 instead of only 120100.** A single-value bump to 120100 (WoW 12.1.0) was premature -- that patch isn't live yet, and a client running the actual current interface (120007) refuses to load an addon whose declared `## Interface` is higher than its own, showing it as out-of-date/disabled rather than just a compatibility warning. The TOC format supports a comma-separated list, so declaring both keeps the addon working right now on 12.0.7 and ready with no further change once 12.1.0 ships.

---

## [0.2.2] - 2026-07-12

### Added

- **Reload prompt after a successful `/rcpl import`.** SavedVariables only get flushed to disk on UI reload or logout -- until then, an import lives in memory only, and a crash (or an unconfirmed second import) can lose it. A confirmation popup ("Reload Now" / "Later") now appears right after a successful import so the data gets safely on disk before it's actually needed, without forcing an unannounced reload if you're mid-raid or mid-typing.

---

## [0.2.1] - 2026-07-12

### Changed

- **Track detection now reads `instanceDifficultyID` off the item link first.** Every real loot drop's item string carries a dedicated `instanceDifficultyID` field (distinct from bonus IDs) set by the server the moment the drop is generated -- it's the same enum `GetInstanceInfo()` returns (15 = Heroic, 16 = Mythic), but travels with the item itself, so it's always correct for genuine awards (Start Session voting/loot frames) with zero per-tier maintenance, unlike the ilvl constants it now sits ahead of. Falls back to `TrackFromItemLevel` when the field isn't set -- true for synthetic links like `/rc test`'s Encounter Journal previews, which were never itemized against a real instance run and so don't carry a meaningful `instanceDifficultyID`, but do still scale ilvl correctly via bonus IDs. `GetInstanceInfo()` remains the final fallback for the rare uncached-ilvl case. Pure Lua string parsing, no new dependency -- reimplements the same one-line pattern RCLootCouncil's own (non-public) `Utils.Item:GetItemStringFromLink` uses internally rather than reaching into RCLootCouncil's internals.
- `TIER_HEROIC_ILVL`/`TIER_MYTHIC_ILVL` still need a manual bump each new raid tier, but only matter for `/rc test` accuracy now -- real awards no longer depend on them being current.
- **WoW 12.1.0 compatibility** -- updated Interface version to 120100.

---

## [0.2.0] - 2026-07-11

### Changed

- **Breaking SavedVariable schema change: track-aware priority (Heroic vs. Mythic).** `RCPL_DB.priority[itemID]` is now a per-track object (`{ H = {...}, M = {...} }`) instead of a single flat ranked list, matching the new export shape from WGA Raid Hub's `build_rclc_export()` (Supabase-side companion change). Heroic and Mythic share the same item ID in this game (the track only changes item level), so a single flat list couldn't tell a Mythic-only-ranked player apart from a Heroic one -- merging them risked surfacing the wrong player's priority during an award at the wrong difficulty. `RCPL_Data_GetPlayerPriority` resolves the track per lookup: primarily from the dropped item's own live item level (`C_Item.GetDetailedItemLevelInfo`, against two per-tier ilvl constants -- no bonus-ID table to maintain, unlike the wowaudit-table-based approach considered and rejected during design), falling back to the raid's live difficulty via `GetInstanceInfo()` if the item level isn't cached yet. Item-level detection works everywhere, including `/rc test`, which never actually places you in a raid instance -- `GetInstanceInfo()` alone was tried first and failed exactly this case during real verification. Shows an "unknown raid difficulty" message when neither signal resolves a track (e.g. LFR, or an item level outside both known tier values) instead of guessing.
- `/rcpl prio` preview now lists Heroic and Mythic priority separately per item instead of one combined list.
- Priority data imported before this version (flat per-item lists) will show N/A instead of a rank until the next `/rcpl import`. `players`-keyed BiS data is unaffected.

### Docs

- `README.md` -- replaced Google Sheet/Apps Script references (Requirements table, Weekly Officer Workflow, Data Format, File Structure) with the WGA Raid Hub officer dashboard/`build_rclc_export()` Supabase path, which now generates the import string live with no manual spreadsheet step.

---

## [0.1.17] - 2026-06-26

### Fixed

- Priority column showing "N/A" for all players: import data stores names without
  realm suffix (e.g. "Katorri") but RCLootCouncil passes cross-realm names like
  "Katorri-Stormrage". All lookups in `RCPL_Data_GetPlayerPriority` now strip the
  realm suffix before comparing against imported priority lists and player BIS data.

---

## [0.1.16] - 2026-06-16

### Changed

- **WoW 12.0.7 compatibility** -- updated Interface version to 120007.

---

## [0.1.15] - 2026-05-18

### Fixed

- **Prio frame row overlap** — priority lines that wrapped across multiple visual rows no longer overlap the next item's name; layout now advances by the actual rendered string height instead of a fixed constant.
- **Prio frame scroll overrun** — scrolling past the bottom of the prio window no longer pushes content off-screen; the scroll is now clamped to the content height.

### Changed

- **Prio frame layout** — each priority entry now shows the item name on its own line with the ranked player list indented below it, making long lists easier to read.
- **ESC closes RCPL windows** — all three RCPL windows (prio preview, awards, import) now close when ESC is pressed, consistent with other WoW UI panels.

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
