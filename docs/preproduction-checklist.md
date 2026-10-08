# Pre-production checklist (go / no-go before "start")

Run through this with the lead before saying "we are ready to start". Every line is checkable.

- [ ] `tools/selftest.ps1` passed within the last week (environment proven).
- [ ] `/new-game <name>` done; tier 2 and the boot screenshot baseline are green on the empty project.
- [ ] GDD sections 1-8, 13 and 14 filled; feel targets are numbers; M0 criteria are checkable by tier 2 or 3.
- [ ] Input map defined in `project.godot` with the action names from GDD section 6.
- [ ] `design/budgets.json` filled (frame time, draw calls, memory, orphan nodes, screenshot threshold).
- [ ] At least 3 reference images in `design/refs/` for the visual direction.
- [ ] M0 is at most two weeks of agent work: 5-12 task packets with disjoint owned paths and tiers.
- [ ] Open decisions logged in the GDD Decisions log (engine version, 2D/3D, renderer, resolution).
- [ ] Klas accepts that the first thing built is the loop, not the menu.
