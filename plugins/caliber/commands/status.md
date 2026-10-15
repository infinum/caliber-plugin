---
description: "Show the Caliber project's status and the next step"
allowed-tools: mcp__plugin_caliber_caliber__status, mcp__plugin_caliber_caliber__projects, Bash(git config --local --get caliber.project), Read
---
Call the Caliber tool `status` with `plugin_version` = "1.1.0" and `project` = the slug
`git config --local --get caliber.project` prints (this clone's project; ignore a value that is not a slug of
lower-case letters, digits and hyphens, and tell me), else the slug the Caliber block of this repository names
(between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md; a block that names no slug
is an older one, which `/caliber:setup` updates). Without either, call `projects`: when it returns exactly one
project, use it; otherwise ask me which project. Then follow the instructions the tool returns, in this
session.
