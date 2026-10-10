# Task packet template

Copy to `games/<name>/design/tasks/<id>.md`. An implementer receives this file verbatim, not the chat history.

```markdown
# <id> <title>

Pillar served: <pillar name>
GDD refs: section <n> "<quoted sentence or two>"; section <m> "<quote>"
Tier: <1|2|3>
Branch: (filled by /dispatch)

## Goal
One paragraph: what exists when this is done and what the player can do.

## Owned paths (only these may change)
- games/<name>/scripts/<file>.gd
- games/<name>/test/unit/test_<file>.gd

## Not allowed
- project.godot, autoload/, other systems' files (report needs to the lead instead)

## Acceptance checks
- Unit: test_<file>.gd::test_<rule> (one line per rule)
- Scenario: test/scenarios/<name>.json step "<step>" asserts <what>
- Screenshot: <scenario>__<shot>.png shows <what> (tier 3 only)

## Out of scope
Things that look related but belong to another packet.

## Done definition
Committed on the branch, then `tools/verify.ps1 -Tier <n>` run once on the clean tree: PASS with
`commit=<HEAD>` and `tree=clean` in the summary header, quoted in the final message with the scenarios added or
changed; reviewer findings addressed, open questions listed.
```
