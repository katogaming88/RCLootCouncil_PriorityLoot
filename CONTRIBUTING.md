# Contributing to RCLootCouncil_PriorityLoot

Thanks for your interest. This doc covers how to set up a dev environment, the conventions PRs follow, and the release process.

For longer-range plans see [`docs/ROADMAP.md`](docs/ROADMAP.md).

---

## Local development setup

You need Lua 5.1, LuaRocks, `luacheck`, and `busted`. CI uses `leafo/gh-actions-lua@v10` (`luaVersion: "5.1"`) and `leafo/gh-actions-luarocks@v4`; local setup should match. **For the full per-platform recipe (Linux, macOS, Windows + MSYS2 / Git Bash), see [`docs/SETUP.md`](docs/SETUP.md).**

Once installed, from the repo root:

```bash
luacheck .                    # lint
bash scripts/run_tests.sh     # 29 specs covering Data/db.lua
```

Both should exit 0 before you push. CI runs the same commands on every push and PR.

### Live-testing in WoW

You also need a retail WoW install with [RCLootCouncil](https://www.curseforge.com/wow/addons/rclootcouncil) for in-game testing. Symlink your local clone into the AddOns directory rather than copying it, so edits show up after `/reload`. On Windows use `mklink /D` from `cmd` (not `ln -s` from MSYS2; symlinks created from MSYS2 without `MSYS=winsymlinks:nativestrict` silently produce file copies).

```cmd
mklink /D "C:\Path\To\WoW\_retail_\Interface\AddOns\RCLootCouncil_PriorityLoot" "C:\Path\To\Repo"
```

If WoW seems to load stale code despite repo edits, the symlink may have been replaced by a real directory. Check with `ls -la` on the AddOns folder. The `Libs/` folder is gitignored and must be present for the addon to load (see the `.toc` for the dependency list).

---

## Branch and commit conventions

### Branches

One PR per branch, off `main`. Frozen after merge: do not push more commits to a branch whose PR has closed; start a fresh branch off `main`.

| Prefix | Use |
|---|---|
| `chore/<topic>` | Repo hygiene (cleanup, lint, tests, CI, docs) |
| `fix/<topic>` | Bug fix |
| `feat/<topic>` | New user-visible feature |
| `refactor/<topic>` | Internal refactor with no behaviour change |
| `docs/<topic>` | Doc-only change |

### Commit messages

```
Short imperative description (vX.Y.Z)

Optional longer body explaining why (not what; the diff shows what).

Co-Authored-By: ...
```

Subject line max 72 characters, ends with `(vX.Y.Z)` when the commit bumps the version.

### Versioning

Every commit that ships behaviour bumps `## Version:` in `RCLootCouncil_PriorityLoot.toc`:

| Bump | When |
|---|---|
| **patch** (`0.1.0 → 0.1.1`) | Bug fixes, lint cleanup, internal refactors, doc updates that ship in the addon zip |
| **minor** (`0.1.0 → 0.2.0`) | New slash subcommand, new SavedVariable key, new module, new UI surface |
| **major** (`0.1.0 → 1.0.0`) | Removed slash subcommand, breaking SavedVariable schema change, RCLootCouncil major-version dependency change |

Stale version strings are bugs. Before committing, search for the old version string and update every occurrence (`.toc`, `CHANGELOG.md` header, any inline `Core.lua` version constant if added later).

### CHANGELOG entries

Every commit adds an entry under `## [Unreleased]` describing the user-visible effect. Categories follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/): **Added**, **Changed**, **Fixed**, **Removed**, **Deprecated**, **Security**.

When releasing:

1. Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`.
2. Add a fresh empty `## [Unreleased]` section above it.
3. Tag the merge commit `vX.Y.Z` and push the tag - the release workflow builds the zip and creates the GitHub Release.

Never tag a commit whose `.toc` Version, CHANGELOG header, or inline constants disagree.

---

## PR checklist

Before requesting review, every PR should pass:

- [ ] Branch name follows the prefix conventions above.
- [ ] `luacheck .` exits 0.
- [ ] `bash scripts/run_tests.sh` exits 0.
- [ ] New or changed behaviour is covered by a spec under `spec/`.
- [ ] CHANGELOG entry under `## [Unreleased]` describes the user-visible change.
- [ ] Version bump in `.toc` if the commit ships behaviour.
- [ ] README, `docs/`, or relevant inline docs updated if the change affects them.
- [ ] Commit message follows the subject + body format above.
- [ ] No em dashes or AI-flavoured filler ("ensure", "robust", "leverage", "seamless") in committed prose.

CI enforces lint and tests automatically. The other items rely on reviewer attention.

---

## Branch protection

`main` is intended to be protected. The recommended ruleset (applied by the repo owner via Settings → Branches, or `gh api -X PUT /repos/.../branches/main/protection`):

| Rule | Setting |
|---|---|
| Require a pull request before merging | On |
| Required approving reviews | 0 (raise to 1 once the team grows) |
| Dismiss stale approvals when new commits are pushed | On |
| Require status checks to pass | `Lint (luacheck)`, `Test (busted)` (added once those check names exist on `main`, i.e. after the first CI run) |
| Require branches to be up to date before merging | On |
| Require linear history | On (squash-merge or rebase-merge only; no merge commits) |
| Allow force pushes | Off |
| Allow deletions | Off |
| Include administrators | Off |

If `Require linear history` is on, `gh pr merge --merge` will fail. Use `--squash` or `--rebase`.

---

## Stacked-PR rebase

When a downstream PR's base merges, rebase the next branch in the chain:

```bash
git checkout <branch>
git fetch origin
git rebase origin/main
```

Canonical conflict resolution:

- **`CHANGELOG.md`**: keep all entries, ascending by version. Drop duplicate `## [Unreleased]` blocks.
- **`RCLootCouncil_PriorityLoot.toc` Version line**: take the higher of the two versions, then bump again if your branch is supposed to ship a new version.
- After resolving, run `luacheck .` and `bash scripts/run_tests.sh` before `git rebase --continue`.

If a downstream PR's purpose collapses into the upstream merge (e.g. a series of small dev-infra PRs combined into one), close the redundant PR with a comment linking to the consolidated one.

---

## Style notes

- **Lua**: 4-space indentation, `local` for everything that does not need to be a global, snake_case for locals, PascalCase for module-level functions assigned to the addon table.
- **Slot keys**, **equipLoc constants**, and **WoW event names** are case-sensitive and inconsistent (some `GUILD_BANK_*`, some `GUILDBANK*`). Verify against `FrameXML/` source or wowpedia rather than guessing.
- **Mocks**: when adding a new external API surface, prefer cross-checking against the vendor source over guessing field names. Mocks built from wrong assumptions produce green tests and red production behaviour.
- **Comments**: explain *why* something is non-obvious, not *what* the code does. Identifiers should carry the *what*.

---

## Reporting issues

Open a GitHub Issue using the appropriate template:

- **Bug report**: include WoW version, RCLootCouncil version, addon version, repro steps, and any chat-log error output.
- **Feature request**: describe the use case in terms of officer or raider workflow before proposing implementation.
