---
description: "Show the Caliber project's status and the next step"
allowed-tools: mcp__plugin_caliber_caliber__status, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `status` with `plugin_version` = "1.0.0" and `project` = the slug the Caliber block of
this repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md).
Without a block, call `list_projects` and ask me which project. Then follow the instructions the tool returns,
in this session.
