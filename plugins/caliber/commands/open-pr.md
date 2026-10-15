---
description: "Open the pull request, link it to its spec and check it"
argument-hint: "[spec-key] [check=before|after]"
allowed-tools: mcp__plugin_caliber_caliber__open-pr, mcp__plugin_caliber_caliber__projects, Bash(git config --local --get caliber.project), Read
---
Call the Caliber tool `open-pr` with the arguments typed after the command, "$ARGUMENTS": a word without `=`
is `spec_key`, and `check=…` passes as that argument; leave out every argument not given. Pass `project` = the
slug `git config --local --get caliber.project` prints (this clone's project; ignore a value that is not a
slug of lower-case letters, digits and hyphens, and tell me), else the slug the Caliber block of this
repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md; a block
that names no slug is an older one, which `/caliber:setup` updates). Without either, call `projects`: when it
returns exactly one project, use it; otherwise ask me which project. Then follow the instructions the tool
returns, in this session.
