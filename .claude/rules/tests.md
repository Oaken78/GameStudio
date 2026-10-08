---
paths:
  - "**/test/**"
---
# Test rules (GUT)

- `test/unit/test_<file>.gd extends GutTest`; one behaviour per test; the name states the rule
  (`test_dash_grants_invulnerability_for_8_frames`).
- Unit tests: pure logic, no scenes, under 100 ms each. Integration tests under `test/integration/` may load
  scenes with `add_child_autofree`, under 1 s each, headless-safe (no rendering assumptions).
- Use `double()`/`partial_double()` for collaborators, `simulate(node, frames, delta)` for frame logic,
  `InputSender.new(Input)` for input, and `release_all()` plus `clear()` in `after_each`.
- No wall-clock waits (`await get_tree().create_timer(...)`) in tests; drive frames instead.
- Tests never write to `user://`. Output goes to `.reports/` only.
- A test that cannot fail is deleted. A flaky test is fixed or deleted the same day.
- Scenario files (`test/scenarios/*.json`) follow the schema in the `godot-cli` skill; every mechanic that the
  player can trigger gets at least one scenario step that proves it.
