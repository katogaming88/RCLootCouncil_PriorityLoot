<!-- See CONTRIBUTING.md for the full PR checklist. -->

## Summary

<!-- One or two sentences on what this PR does and why. The diff covers what; this section covers motivation. -->

## Roadmap reference

<!-- Optional: link to the docs/ROADMAP.md item this PR addresses (e.g. "Phase 0.3: Test scaffold"). -->

## Testing

<!-- How did you verify this works?
- `luacheck .` and `bash scripts/run_tests.sh` outputs (mention if either was already covered by CI)
- For UI changes: in-game smoke test description (which raid frame, what you clicked, what changed)
- For data changes: which spec covers the new behaviour
-->

## Checklist

- [ ] `luacheck .` exits 0
- [ ] `bash scripts/run_tests.sh` exits 0
- [ ] New / changed behaviour is covered by a spec under `spec/` (or N/A explained above)
- [ ] CHANGELOG entry added under `## [Unreleased]`
- [ ] Version bump in `.toc` if behaviour ships (and the new version is reflected in CHANGELOG header on release PRs)
- [ ] README / `docs/` updated if affected
- [ ] No em dashes or AI-flavoured filler in committed prose
