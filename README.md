# Caliber plugin for Claude

[Caliber](https://caliber.infinum.com) is Infinum's AI delivery platform: it holds a project's specs, checks
its pull requests and measures its delivery. This plugin brings Caliber to Claude Code, the Claude Desktop
Code tab and Cowork:

- **The Caliber MCP server**, signed in with your Caliber account. No token to create, copy or export.
- **One command per Caliber ability**: `/caliber:prd`, `/caliber:brief`, `/caliber:tech-spec`,
  `/caliber:plan`, `/caliber:comments`, `/caliber:check`, `/caliber:fix`, `/caliber:open-pr`,
  `/caliber:audit`, `/caliber:code-audit`, `/caliber:security-audit`, `/caliber:status` and `/caliber:setup`.
- **The session hook**: after the agent's own `git push` (or a pull request it opens from the command line)
  in a repository set up for Caliber, Claude runs the Caliber check in the same session.

The plugin does nothing without a Caliber account. It holds configuration and short command files only: no
secret, no token, no prompt text. Each command calls the Caliber tool of the same name and follows the
instructions the server returns, so a command's behaviour changes with Caliber, not with a plugin release.

## Install

Install it one way only: from the terminal, or from your Claude account. Installed both ways, Claude Code
shows two copies.

### Claude Code (terminal) and the Claude Desktop Code tab

```
/plugin marketplace add infinum/caliber-plugin
/plugin install caliber@caliber
```

Then sign in once: run `/mcp`, choose `plugin:caliber:caliber` and sign in with your Caliber account (or run
`claude mcp login plugin:caliber:caliber` in a shell). Claude Code renews the sign-in from then on; the
background check on push uses the same sign-in.

Update with `/plugin update caliber@caliber`. `/caliber:status` tells you when the installed plugin is older
than your Caliber expects.

### Cowork, and every Claude app of your account

1. Customize → Plugins → Add marketplace, and paste `https://github.com/infinum/caliber-plugin`.
2. Install **caliber** from it.
3. In the plugin's Connectors tab, connect the Caliber server and sign in with your Caliber account.

An install from your account also reaches your Claude Code sessions; a terminal install stays on that machine.

### Claude chat, or Claude Desktop without the plugin

Add Caliber as a connector with the URL `https://app.caliberhq.io/mcp` and sign in. On a Claude Team or
Enterprise plan an owner of the Claude organisation adds the connector once; every member then signs in with
their own Caliber account.

## Use it

Open a repository whose `CLAUDE.md` or `AGENTS.md` carries the Caliber block (`/caliber:setup` writes it).
The block names the project, and every command works on that project. In a repository without a block, a
command lists the projects you can see and asks which one.

| Command | What it does |
|---|---|
| `/caliber:prd <feature>` | Write a PRD and save it for approval |
| `/caliber:brief <change>` | Write a technical brief |
| `/caliber:tech-spec <prd-key>` | Design the approach and write the tech spec |
| `/caliber:plan <spec-key>` | Write the implementation plan |
| `/caliber:comments <spec-key>` | Work through a spec's open comment threads (when collaboration is on) |
| `/caliber:check [pr-number]` | Check the pull request with the project's audits |
| `/caliber:fix [pr-number]` | Fix the open findings, one commit each |
| `/caliber:open-pr [spec-key]` | Open the pull request, link it to its spec and check it |
| `/caliber:audit [audit-slug] [scope]` | Run one audit, or every audit the project runs |
| `/caliber:code-audit [scope]` | Full code audit |
| `/caliber:security-audit [scope]` | Full security audit |
| `/caliber:status` | The project's status and the next step |
| `/caliber:setup` | Set up this repository for Caliber |

The session hook runs only in a repository with the Caliber block or a `.caliber/` directory, and stays quiet
when the repository's own `.claude/settings.json` already runs Caliber's hook. Turn it off for one clone with
`git config --local caliber.checkInSession false`.

## Another Caliber instance

The plugin connects to `https://app.caliberhq.io`. Set `CALIBER_URL` (for example
`export CALIBER_URL=https://caliber.example.com`) before starting Claude Code to point it at another instance;
you sign in to each instance once. A plugin installed from your Claude account has no environment, so it
always connects to `https://app.caliberhq.io`: reach another instance with the terminal install or a
connector.

## CI and clients that cannot sign in

CI and clients that cannot sign in use a project token from the project's Connect tab in Caliber; the plugin
is not needed there.

## Releasing

A release is one commit that bumps `version` in `plugins/caliber/.claude-plugin/plugin.json` and the
`plugin_version` that `plugins/caliber/commands/status.md` passes, together. The server address never changes
between releases, so installed copies keep their sign-in after `/plugin update`.

`plugins/caliber/scripts/agent-post-push.sh` is a byte-identical copy of the server's
`backend/app/services/caliber/hooks/agent-post-push.sh` in `infinum/caliber`. When the server's hooks version
moves, copy the file and add its `<hooks version> <sha256>` line to `scripts/server-hooks.sha256`.

```
scripts/check-release.sh                                   # what CI runs
CALIBER_SERVER_DIR=../caliber scripts/check-release.sh     # also compares with a checkout of the server
claude plugin validate --strict .
claude plugin validate --strict plugins/caliber
```

## Licence

Apache License 2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE).
