---
description: "Propose one-line descriptions for Caliber specs that have none, and save the ones I agree to"
allowed-tools: mcp__plugin_caliber_caliber__describe-specs, mcp__plugin_caliber_caliber__list_projects, Read
---
Call the Caliber tool `describe-specs` with `project` = the slug the Caliber block of this repository names
(between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md). Without a block, or with
a block that names no slug (an older one; `/caliber:setup` updates it), call `list_projects`: when it returns
exactly one project, use it; otherwise ask me which project. Then follow the instructions the tool returns, in
this session.
