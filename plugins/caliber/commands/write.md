---
description: "Write a document of one of the project's types (PRD, brief, tech spec, plan, or its own) with Caliber"
argument-hint: "<type> <what to write>"
allowed-tools: mcp__plugin_caliber_caliber__write, mcp__plugin_caliber_caliber__projects, Bash(git config --local --get caliber.project), Read
---
Call the Caliber tool `write` with `type` = the first word of "$ARGUMENTS" as a type's slug (lower case,
`-` as `_`; `tech spec` or `tech-spec` is `tech_spec`), `about` = the rest of it, and
`project` = the slug `git config --local --get caliber.project` prints (this clone's project; a value that is
not a slug, of lower-case letters, digits and hyphens, starting and ending with a letter or digit, at most 64
characters, does not count: ignore it and tell me without repeating it), else the slug the Caliber block of
this repository names (between `<!-- caliber:start` and `<!-- caliber:end -->` in CLAUDE.md or AGENTS.md; a
block that names no slug is an older one, which `/caliber:setup` updates). Without either, call `projects`:
when it returns exactly one project, use it; otherwise ask me which project. When the rest starts with
`parent=<key>`, pass that key as `parent` and leave it out of `about`. If Caliber's only tool here is
`authenticate`, Caliber is not signed in yet: say so (run `/mcp` and sign in to caliber) and stop. If the
tool `write` is missing, document types are off in this organization: say so and stop. When
nothing follows the command, call `write` without `type`: it lists the types this project can start. Then
follow the instructions the tool returns, in this session.
