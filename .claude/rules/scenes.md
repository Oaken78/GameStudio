---
paths:
  - "**/*.tscn"
  - "**/*.tres"
  - "**/project.godot"
---
# Scene and project-file rules

- Keep `[gd_scene format=3 ...]` headers and every `uid://` intact; never invent UIDs by hand.
- Prefer changing behaviour in scripts and `@export` defaults over hand-editing scene files. Hand edits are
  for trivial property changes only; structural changes go through the editor or a scene-building script.
- Use `%UniqueName` for in-scene lookups instead of long node paths.
- After editing a scene or `project.godot`, run `./tools/import.ps1 -Game <g>` before tests.
- Keep the autoload list in sync with the scripts; never remove `DevHarness`.
- `project.godot` and autoloads are edited only by the lead on `main`.
