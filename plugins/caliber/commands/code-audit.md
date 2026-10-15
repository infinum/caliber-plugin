---
description: "Run a full code audit of the repository with Caliber"
argument-hint: "[scope]"
allowed-tools: mcp__plugin_caliber_caliber__code-audit, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `code-audit` with the arguments typed after the command, "$ARGUMENTS": they are `scope`
(a module or directory); leave out every argument not given. Pass `project` = the slug the Caliber block of
this repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md).
Without a block, call `list_projects` and ask me which project. Then follow the instructions the tool returns,
in this session.
