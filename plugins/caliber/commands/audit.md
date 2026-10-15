---
description: "Run a Caliber audit of the repository, or every audit the project runs"
argument-hint: "[audit-slug] [scope]"
allowed-tools: mcp__plugin_caliber_caliber__audit, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `audit` with the arguments typed after the command, "$ARGUMENTS": the first word is
`kind` (an audit slug), and the rest is `scope` (a module or directory); leave out every argument not given.
Pass `project` = the slug the Caliber block of this repository names (between `<!-- caliber:start` and
`<!-- caliber:end -->` in CLAUDE.md or AGENTS.md). Without a block, call `list_projects` and ask me which
project. Then follow the instructions the tool returns, in this session.
