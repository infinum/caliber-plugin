---
description: "Write a technical brief with Caliber and save it for approval"
argument-hint: "<change>"
allowed-tools: mcp__plugin_caliber_caliber__brief, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `brief` with `change` = "$ARGUMENTS" and `project` = the slug the Caliber block of this
repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md). Without
a block, or with a block that names no slug (an older one; `/caliber:setup` updates it), call `list_projects`:
when it returns exactly one project, use it; otherwise ask me which project. When nothing follows the command,
ask me what the technical change is first. Then follow the instructions the tool returns, in this session.
