---
description: "Set up your own usage for Caliber (a client repository's commit sync, your agents' telemetry)"
argument-hint: "[project-slug]"
allowed-tools: mcp__plugin_caliber_caliber__setup-usage, mcp__plugin_caliber_caliber__projects, Bash(git config --local --get caliber.project), Read
---
Call the Caliber tool `setup-usage` with `plugin_version` = "1.8.2" and `project` = the slug typed after the
command, "$ARGUMENTS", when there is one; else the slug `git config --local --get caliber.project` prints (this
clone's project), else the slug the Caliber block of this repository names (between `<!-- caliber:start` and
`<!-- caliber:end -->` in CLAUDE.md or AGENTS.md). A value that is not a slug, of lower-case letters, digits
and hyphens, starting and ending with a letter or digit, at most 64 characters, does not count: ignore it and
tell me without repeating it. Without any, call it without `project`: it needs no Caliber project. If Caliber's only tool here is `authenticate`, Caliber
is not signed in yet: say so (run `/mcp` and sign in to caliber) and stop. When the Caliber server has no
`setup-usage` tool (an older server), say that `/caliber:setup` still sets up your usage too, and stop. Then
follow the instructions the tool returns, in this session. When they name the plugin's sync script, it is
`${CLAUDE_PLUGIN_ROOT}/scripts/pre-push`.
