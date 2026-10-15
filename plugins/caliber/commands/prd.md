---
description: "Write a PRD with Caliber and save it for approval"
argument-hint: "<feature>"
allowed-tools: mcp__plugin_caliber_caliber__prd, mcp__plugin_caliber_caliber__projects, Bash(git config --local --get caliber.project), Read
---
Call the Caliber tool `prd` with `feature` = "$ARGUMENTS" and `project` = the slug
`git config --local --get caliber.project` prints (this clone's project; a value that is not a slug, of
lower-case letters, digits and hyphens, starting and ending with a letter or digit, at most 64 characters,
does not count: ignore it and tell me without repeating it), else the slug the Caliber block of this
repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md; a block
that names no slug is an older one, which `/caliber:setup` updates). Without either, call `projects`: when it
returns exactly one project, use it; otherwise ask me which project. If Caliber's only tool here is
`authenticate`, Caliber is not signed in yet: say so (run `/mcp` and sign in to caliber) and stop. When
nothing follows the command, ask me what to build first. Then follow the instructions the tool returns, in
this session.
