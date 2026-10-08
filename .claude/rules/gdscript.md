---
paths:
  - "**/*.gd"
---
# GDScript rules

- Static typing everywhere (`var speed: float = 200.0`, `func hit(damage: int) -> void`). Tabs. Official member order:
  tool/class_name/extends, signals, enums, consts, @export vars, vars, @onready vars, _init/_ready/_process, public funcs, private funcs.
- Names: `snake_case` members, `PascalCase` classes, `UPPER_SNAKE` consts, `_private`. Signals in past tense (`died`, `level_started`).
- Tunables are `@export` or Resources under `data/`, never magic literals in logic.
- Signals up, calls down: a child never reaches `get_node("../..")` into another scene.
- No `await` on timers in core gameplay logic; count frames or deltas so tests can `simulate()` deterministically.
- Gameplay randomness uses a seeded `RandomNumberGenerator` instance, never bare `randi()`/`randf()`.
- `push_error()` only for impossible states; the harness fails a run on any error line.
- Godot 4.7: overriding a typed-return method needs an explicit `return null` on every path; mouse/keyboard events
  carry `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD`, not device 0.
- Every new system gets a unit test in `test/unit/test_<file>.gd` in the same change. Fix bugs with a failing test first.
