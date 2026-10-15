---
description: "Fix the open Caliber findings on the pull request"
argument-hint: "[pr-number] [kind=<audit>] [head_sha=<sha>]"
allowed-tools: mcp__plugin_caliber_caliber__fix, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `fix` with the arguments typed after the command, "$ARGUMENTS": a number is `pr_number`,
and `kind=…` and `head_sha=…` pass as those arguments; leave out every argument not given. Pass `project` =
the slug the Caliber block of this repository names (between `<!-- caliber:start` and `<!-- caliber:end -->`
in CLAUDE.md or AGENTS.md). Without a block, or with a block that names no slug (an older one;
`/caliber:setup` updates it), call `list_projects`: when it returns exactly one project, use it; otherwise ask
me which project. Then follow the instructions the tool returns, in this session.
