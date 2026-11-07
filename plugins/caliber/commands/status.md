---
description: "Show the Caliber project's status and the next step"
allowed-tools: mcp__plugin_caliber_caliber__status, mcp__plugin_caliber_caliber__projects, Bash(git config --local --get caliber.project), Read
---
First: when this session has no `mcp__plugin_caliber_caliber__` tool at all (not even `authenticate`), the
Caliber plugin was installed or updated in this session and its Caliber server is not loaded yet. Use no other Caliber server's tools (another
connection may be signed in to another organisation, and would say this repository is not there): tell me to run
`/reload-plugins` (or start a new session) and then this command again, and stop.
When its only Caliber tool is `authenticate`, Caliber is loaded but not signed in: the sign-in rule below applies.
Call the Caliber tool `status` with `plugin_version` = "1.9.7" and `project` = the slug
`git config --local --get caliber.project` prints (this clone's project; a value that is not a slug, of
lower-case letters, digits and hyphens, starting and ending with a letter or digit, at most 64 characters,
does not count: ignore it and tell me without repeating it), else the slug the Caliber block of this
repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md; a block
that names no slug is an older one, which `/caliber:setup` updates). Without either, call `projects`: when it
returns exactly one project, use it; otherwise ask me which project. If Caliber's only tool here is
`authenticate`, Caliber is not signed in yet: say so (run `/mcp` and sign in to caliber) and stop. Then follow
the instructions the tool returns, in this session.
