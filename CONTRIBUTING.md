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

### Pull request titles and commit messages

PRs are squash-merged, so a PR's title becomes its commit subject on `main`, and release-please reads those subjects to build the changelog and pick the next version. Start every PR title with a Conventional Commit type:

| Type | Use | Effect on the next release |
|---|---|---|
| `feat:` | A new user-visible feature | Minor bump (`0.7.2` to `0.8.0`) |
| `fix:` | A bug fix | Patch bump (`0.7.2` to `0.7.3`) |
| `feat!:` or `fix!:` | A breaking change: a removed slash subcommand, an incompatible SavedVariables change, a newer RCLootCouncil major version required | Major bump (`0.7.2` to `1.0.0`) |
| `docs:`, `chore:`, `refactor:`, `test:`, `ci:` | Everything else | None on its own |

A title with no type is skipped: the change still ships in the next release, but the changelog never mentions it. Keep the subject under 72 characters with no version number in it. The body says why, not what, since the diff shows what.

### Versioning

No file holds a version number to bump by hand. The `.toc` line is `## Version: @project-version@`, which the packager replaces with the release's version when it builds the zip, and `Core.lua` reads the version back from the `.toc` at runtime. release-please records the last released version in `.release-please-manifest.json` and updates it itself.

### Releases and the changelog

Once a `feat:` or `fix:` PR has merged, release-please keeps a Release PR open against `main` that drafts the next version and its `CHANGELOG.md` section from the merged PR titles. Merging the Release PR tags the merge commit `vX.Y.Z`. The tag runs `release.yml`, which builds the zip, creates the GitHub Release and uploads the zip to CurseForge.

Never edit `CHANGELOG.md` or push a tag by hand: both belong to the Release PR. The entries already in `CHANGELOG.md` from before release-please keep their old Keep a Changelog form.

---

## PR checklist

Before requesting review, every PR should pass:

- [ ] Branch name follows the prefix conventions above.
- [ ] `luacheck .` exits 0.
- [ ] `bash scripts/run_tests.sh` exits 0.
- [ ] New or changed behaviour is covered by a spec under `spec/`.
- [ ] The PR title starts with a Conventional Commit type and reads as a changelog line a raider or officer would understand.
- [ ] README, `docs/`, or relevant inline docs updated if the change affects them.
- [ ] The PR body says why the change is needed.
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

- **`CHANGELOG.md` and the `.toc` version line** are never edited by hand, so neither should conflict. If one does, take `main`'s side: the Release PR owns both.
- After resolving, run `luacheck .` and `bash scripts/run_tests.sh` before `git rebase --continue`.

If a downstream PR's purpose collapses into the upstream merge (e.g. a series of small dev-infra PRs combined into one), close the redundant PR with a comment linking to the consolidated one.

---

## Style notes

- **Lua**: 4-space indentation, `local` for everything that does not need to be a global, snake_case for locals, PascalCase for module-level functions assigned to the addon table.
- **Slot keys**, **equipLoc constants**, and **WoW event names** are case-sensitive and inconsistent (some `GUILD_BANK_*`, some `GUILDBANK*`). Verify against `FrameXML/` source or wowpedia rather than guessing.
- **Mocks**: when adding a new external API surface, prefer cross-checking against the vendor source over guessing field names. Mocks built from wrong assumptions produce green tests and red production behaviour.
- **Comments**: explain *why* something is non-obvious, not *what* the code does. Identifiers should carry the *what*.
- **Addon files are ASCII only**: `.lua`, `.xml` and `.toc`.
- **The voting window and the loot frame popup lean on RCLootCouncil's internals**, not a supported API. Check them against each new RCLootCouncil release before a release of ours ships.

---

## Reporting issues

Open a GitHub Issue using the appropriate template:

- **Bug report**: include WoW version, RCLootCouncil version, addon version, repro steps, and any chat-log error output.
- **Feature request**: describe the use case in terms of officer or raider workflow before proposing implementation.
