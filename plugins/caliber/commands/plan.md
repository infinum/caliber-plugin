---
description: "Write the implementation plan for a Caliber tech spec or brief"
argument-hint: "<spec-key>"
allowed-tools: mcp__plugin_caliber_caliber__plan, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `plan` with `spec_key` = "$ARGUMENTS" and `project` = the slug the Caliber block of this
repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md). Without
a block, or with a block that names no slug (an older one; `/caliber:setup` updates it), call `list_projects`:
when it returns exactly one project, use it; otherwise ask me which project. When nothing follows the command,
ask me the key of the tech spec or brief first. Then follow the instructions the tool returns, in this
session.
