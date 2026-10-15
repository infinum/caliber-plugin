---
description: "Design the approach and write the tech spec for a Caliber PRD"
argument-hint: "<prd-key>"
allowed-tools: mcp__plugin_caliber_caliber__tech-spec, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `tech-spec` with `prd_key` = "$ARGUMENTS" and `project` = the slug the Caliber block of
this repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md).
Without a block, or with a block that names no slug (an older one; `/caliber:setup` updates it), call
`list_projects`: when it returns exactly one project, use it; otherwise ask me which project. When nothing
follows the command, ask me the key of the PRD first. Then follow the instructions the tool returns, in this
session.
