# Merge notes — tailored data model (`feat/tailored-data-model`)

Spec: `specs/2026-06-07-tailored-data-model-design.md` · Plan: `plans/2026-06-07-tailored-data-model.md`

This branch lands the unified `cat / sub / title / desc` field shape on `activity_segments`,
`planned_blocks`, and `user_events`, plus three agent-curated surfaces: a DB-backed
`category_registry`, user memory (identity + learned behaviour in `settings`), and custom events.

## michelle-merge (`integration/michelle-merge`) — onboarding → memory

That branch's onboarding collects the same identity this branch now owns. When the two merge,
route the north star into memory instead of the side-table:

1. In `OnboardingCoordinator.saveNorthStar()`, write `settings.set("north_star", text)` and
   `settings.set("north_star_why", why)` instead of `NorthStarService.save(...)`.
   (Name already goes to `settings["user_display_name"]`, which `read_behaviour` reads — no change.)
2. Delete `NorthStarRecord`, `NorthStarService`, `NorthStarSync`, and that branch's
   `v5_north_star` migration (its `north_star` table). North star becomes local-first memory;
   the Supabase sync is dropped.
3. Migration-name overlap: this branch's migration is `v5_tailored_data_model`; michelle-merge's
   is `v5_north_star`. They are distinct GRDB identifiers and can coexist, but at merge keep
   `v5_tailored_data_model` and drop `v5_north_star` rather than leaving a dead table.
4. Verify `read_behaviour` returns the onboarded name + north star end to end.

## Downstream

A separate goals/journal/check-ins effort is specced as **v6-on-v5, gated on this branch landing**
(`memory/goals-journal-checkins-design.md`). Land this first.

## Branch state at hand-off

- Swift: 104 tests pass (2 skipped). Sidecar: 31 tests pass; `npm run build` clean.
- Track worktrees (`feat/tdm-sidecar`, `feat/tdm-swift-cat`, `feat/tdm-swift-evt`) were merged in
  and can be pruned.
