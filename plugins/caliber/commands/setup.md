---
description: "Set up this repository for Caliber (the Caliber block, the MCP configs and the hooks)"
allowed-tools: mcp__plugin_caliber_caliber__setup, mcp__plugin_caliber_caliber__projects, Bash(git config --local --get caliber.project), Bash(git remote -v), Read
---
First: when this session has no `mcp__plugin_caliber_caliber__` tool at all (not even `authenticate`), the
Caliber plugin was installed or updated in this session and its Caliber server is not loaded yet. Use no other Caliber server's tools (another
connection may be signed in to another organisation, and would say this repository is not there): tell me to run
`/reload-plugins` (or start a new session) and then this command again, and stop.
When its only Caliber tool is `authenticate`, Caliber is loaded but not signed in: the sign-in rule below applies.
Call the Caliber tool `setup` with `plugin_version` = "1.9.7" and `project` = the slug `git config --local --get caliber.project` prints
(this clone's project; a value that is not a slug, of lower-case letters, digits and hyphens, starting and
ending with a letter or digit, at most 64 characters, does not count: ignore it and tell me without repeating
it), else the slug the Caliber block of this repository names (between `<!-- caliber:start` and
`<!-- caliber:end -->` in CLAUDE.md or AGENTS.md; a block that names no slug is an older one, which
`/caliber:setup` updates). Without either, call `projects`: when it returns exactly one project, use it;
otherwise ask me which project. If Caliber's only tool here is `authenticate`, Caliber is not signed in yet:
say so (run `/mcp` and sign in to caliber) and stop. When this clone's `caliber.project` and the block name
different projects, ask me which one to set up before calling `setup`, and pass the one I choose; that counts
as me naming the project for setup. Before calling it, run exactly `git remote -v` and take its `(fetch)` lines, origin first: each URL as
`host/path` (drop the scheme, any `user@`, a port and a trailing `.git`; in the scp form `git@host:o/n` the `:` becomes `/`; never
repeat a user or token a URL holds). Pass them, separated by spaces, as `repository`; when the command fails or
prints no remote, pass no `repository`.
Then follow the instructions the tool returns, in this session.
When they name the plugin's sync script, it is `${CLAUDE_PLUGIN_ROOT}/scripts/pre-push`; when they call
the `setup-usage` tool, pass it `plugin_version` = "1.9.7" and the same `repository` too.
