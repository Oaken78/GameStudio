---
name: playtest-build
description: Export a Windows playtest build of a game and deliver it to Klas as a temporary playtest branch on the game's GitHub repo; delete the branch once Klas has saved it.
argument-hint: <game-or-checkout-id>
---
Klas plays remotely. Every build for them goes this way (Klas, 2026-10-09: "Always send builds like you did before to
my GitHub"). `$0` is a game or checkout id (`walkers`, `walkers--<branch>`); `<repo>` below is `games/<game>` (the
game's own git repo, whatever checkout the build comes from). `<scratch>` is the session scratchpad.

1. **Preset.** The game needs an `export_presets.cfg` preset named "Windows Playtest" (platform Windows Desktop,
   `custom_features="playtest"`, `binary_format/embed_pck=true`, `exclude_filter="test/*"`) and, in `project.godot`,
   `run/main_scene.playtest="res://<the scene Klas should play>"` so only playtest builds boot there. If either is
   missing, add it on the game's main (lead-only file), run tier 2, commit. To build an unmerged branch, merge main into
   it first so it has the preset.
2. **Export.** `./tools/import.ps1 -Game $0`, create `<scratch>/build/` (empty it first), then
   `./tools/godot.ps1 -TimeoutSec 300 -- --headless --path C:/game-dev/games/$0 --export-release "Windows Playtest" <scratch>/build/<game>.exe`.
   Scan the output for `ERROR` and `failed`; one `Cannot set object script` line at editor shutdown is known and harmless.
3. **Boot check.** `timeout 90 <scratch>/build/<game>.exe --headless --verbose --quit-after 240`: exit 0, the playtest
   scene in a `Completed load for` line, no `SCRIPT ERROR`.
4. **Package.** Write `README.md` next to the exe: how to run it (SmartScreen: "More info", then "Run anyway"), the key
   list, and what to try in the first 5 minutes (ask the playtest-critic for that list when the build is for a gate).
   Zip exe + README with Python `zipfile` (`ZIP_DEFLATED`, level 9) as `<game>-playtest-<yyyymmdd-hhmm>.zip`. It must
   be under 100 MB (GitHub's file limit).
5. **Branch.** In `<repo>`, build an orphan commit with git plumbing (no worktree): `hash-object -w` the zip and the
   README, `mktree`, `commit-tree` (message `chore(<game>): playtest build from <commit>` plus the attribution lines;
   if a `playtest` branch already exists, use its head as the parent and keep its older zips in the tree, so a build
   Klas has not saved yet never disappears), `update-ref refs/heads/playtest <commit>`, then
   `git -C <repo> push origin playtest`.
6. **Send.** Give Klas `https://github.com/<owner>/<repo>/raw/playtest/<zip>` (owner and repo from
   `git -C <repo> remote get-url origin`), the size, what changed since the last build, and the questions to judge.
7. **Remove.** When Klas says the build is saved: `git -C <repo> push origin --delete playtest` and
   `git -C <repo> branch -D playtest`. This standing instruction is Klas's ask for that branch deletion; it covers the
   `playtest` branch only.
