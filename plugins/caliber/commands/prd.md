---
description: "Write a PRD with Caliber and save it for approval"
argument-hint: "<feature>"
allowed-tools: mcp__plugin_caliber_caliber__prd, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `prd` with `feature` = "$ARGUMENTS" and `project` = the slug the Caliber block of this
repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md). Without
a block, or with a block that names no slug (an older one; `/caliber:setup` updates it), call `list_projects`:
when it returns exactly one project, use it; otherwise ask me which project. When nothing follows the command,
ask me what to build first. Then follow the instructions the tool returns, in this session.
