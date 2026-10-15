---
description: "Check the pull request with Caliber's audits"
argument-hint: "[pr-number] [push=ask|yes|no] [wait_for_ci=auto|yes|no]"
allowed-tools: mcp__plugin_caliber_caliber__check, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `check` with the arguments typed after the command, "$ARGUMENTS": a number is
`pr_number`, and `push=…` and `wait_for_ci=…` pass as those arguments; leave out every argument not given.
Pass `project` = the slug the Caliber block of this repository names (between `<!-- caliber:start` and
`<!-- caliber:end -->` in CLAUDE.md or AGENTS.md). Without a block, or with a block that names no slug (an
older one; `/caliber:setup` updates it), call `list_projects`: when it returns exactly one project, use it;
otherwise ask me which project. Then follow the instructions the tool returns, in this session.
