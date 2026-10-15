---
description: "Open the pull request, link it to its spec and check it"
argument-hint: "[spec-key] [check=before|after]"
allowed-tools: mcp__plugin_caliber_caliber__open-pr, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `open-pr` with the arguments typed after the command, "$ARGUMENTS": a word without `=`
is `spec_key`, and `check=…` passes as that argument; leave out every argument not given. Pass `project` = the
slug the Caliber block of this repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in
CLAUDE.md or AGENTS.md). Without a block, call `list_projects` and ask me which project. Then follow the
instructions the tool returns, in this session.
