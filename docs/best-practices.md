# Claude Code best practices (condensed)

Source: https://code.claude.com/docs/en/best-practices, read 2026-10-08. Kept short on purpose; the
"Here:" lines say how this repo applies each point. Not loaded automatically; read it when you wonder why
the setup looks the way it does.

## The one constraint
The context window fills fast and quality drops as it fills. Every file read, command output and message
stays in it. Most practices below protect context. Check usage with `/context`.

## Give Claude a check it can run
- A test suite, a build exit code, a linter, a diff against a fixture, a screenshot compared to a design.
  Without a check, "looks done" is the only signal and you become the verification loop.
- Gate levels, cheapest first: ask for the check in the prompt; `/goal` (an evaluator re-checks every turn);
  a Stop hook (deterministic script, blocks the stop until it passes); a verification subagent in a fresh context.
- Demand evidence, not claims: the command, its output, the screenshot path.
- Ask for root causes: "fix the root cause, don't suppress the error".
- Here: `tools/verify.ps1` tiers, the SubagentStop gate on implementers, `test-runner`, `playtest-critic`.

## Explore, plan, code, commit
- Plan mode (Shift+Tab) for unclear scope, multi-file changes or unfamiliar code. Ctrl+G edits the plan.
- If you could describe the diff in one sentence, skip the plan.
- Here: `/plan-feature` writes task packets; implementers receive the packet, not the chat history.

## Prompting
- Scope the task: which file, which scenario, which tests. Point at sources and existing patterns to copy.
- Describe bugs as symptom + likely location + what "fixed" looks like; ask for a failing test first.
- `@file` references, pasted images, URLs and piped data beat descriptions.

## CLAUDE.md
- Loaded every session, so only broadly useful content. Per line: "would removing this cause mistakes?"
- Include: commands Claude can't guess, style that differs from defaults, repo etiquette, gotchas, env quirks.
- Exclude: anything derivable from the code, standard conventions, tutorials, file-by-file maps.
- Too long means ignored. Emphasise ("IMPORTANT") one or two lines at most. `/doctor` proposes cuts.
- Rarely needed knowledge goes in skills (loaded on demand); path-specific rules in `.claude/rules/` with `paths:`.
- Here: CLAUDE.md is about 40 lines; rules cover `.gd`, `.tscn`, `.gdshader`, tests; the Godot CLI lives in `skills/godot-cli`.

## Environment
- Permissions: pre-approve trusted tools; auto mode reviews the rest with a classifier.
- CLI tools (`gh`) are the most context-efficient integrations. Claude can learn a tool from `--help`.
- Hooks for things that must happen every time (format after edit, block protected paths). Zero context cost.
- Skills: `.claude/skills/<name>/SKILL.md`; `disable-model-invocation: true` for side-effect workflows you trigger with `/name`.
- Subagents: `.claude/agents/<name>.md`; own context, own tools, own model. Use them for investigation and fresh-context review.
- MCP only for a concrete need; every server adds tool descriptions to every session.

## Communicate
- Ask codebase questions as you would ask a senior engineer.
- For big features: "interview me with AskUserQuestion, then write the spec", then implement in a fresh session.
- Here: `/gdd` is that interview for a game.

## Session management
- Esc stops Claude; Esc Esc or `/rewind` restores conversation and/or code; "undo that" works too.
- `/clear` between unrelated tasks. After two failed corrections, `/clear` and write a better prompt.
- `/compact <focus>` when needed; `/btw` for side questions that should not enter history.
- Subagents keep bulk file reading out of the main context. Name sessions with `/rename`.
- Checkpoints track only Claude's own edits, not Bash changes; they are not a git replacement.

## Automate and scale
- `claude -p "prompt"` for scripts and CI; `--allowedTools` and `--permission-mode dontAsk` for unattended fan-out.
- Parallel work: worktrees (`claude --worktree`), desktop sessions each in a worktree, `/batch` for 5-30 mechanical units.
  Agent teams are experimental, CLI-only and expensive; off here.
- Writer/Reviewer: a fresh context reviews better than the author. Tell reviewers to report only gaps that
  affect correctness or stated requirements; everything else is optional, or you get over-engineering.
- Here: implementers in worktrees, `code-reviewer` on the diff, `playtest-critic` on the evidence.

## Failure patterns
- Kitchen-sink session: unrelated tasks in one context. Fix: `/clear`.
- Correcting over and over: context full of failed approaches. Fix: `/clear` and a better first prompt.
- Over-specified CLAUDE.md: important rules get lost. Fix: prune; turn "every time" rules into hooks.
- Trust-then-verify gap: plausible code, untested edge cases. Fix: never ship what you cannot verify.
- Infinite exploration: unscoped "investigate". Fix: scope it, or send a subagent.

## Grow the setup over time
Add a rule after a mistake repeats, a skill after a procedure is explained twice, a hook when you say
"every time". Run `/doctor` now and then to trim CLAUDE.md.
