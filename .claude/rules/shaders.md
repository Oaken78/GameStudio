---
paths:
  - "**/*.gdshader"
  - "**/*.gdshaderinc"
---
# Shader rules

- Comment every `uniform` with its purpose and sane range; expose tunables as `@export` on the owning material or node.
- No per-pixel loops longer than 16 iterations; no texture reads inside loops without a stated reason.
- Respect `design/budgets.json` (draw calls, frame time). Measure with a scenario `metrics` step.
- Every shader change gets a scenario `screenshot` step and a `tools/shots.ps1` run before merge.
- Readability of game state beats spectacle: effects must not hide the player, enemies or hazards.
