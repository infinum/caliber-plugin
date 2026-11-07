# Caliber plugin for Claude

[Caliber](https://caliber.infinum.com) is Infinum's AI delivery platform: it holds a project's specs, checks
its pull requests and measures its delivery. This plugin brings Caliber to Claude Code, the Claude Desktop
Code tab and Cowork:

- **The Caliber MCP server**, signed in with your Caliber account. No token to create, copy or export.
- **One command per Caliber ability**: `/caliber:prd`, `/caliber:brief`, `/caliber:tech-spec`,
  `/caliber:plan`, `/caliber:comments`, `/caliber:check`, `/caliber:fix`, `/caliber:open-pr`,
  `/caliber:audit`, `/caliber:code-audit`, `/caliber:security-audit`, `/caliber:describe-specs`,
  `/caliber:status`, `/caliber:setup` and `/caliber:setup-usage`, plus `/caliber:projects` and `/caliber:project` to see and choose
  this clone's project.
- **The session hooks**: at the start of a session in a repository set up for Caliber, Claude is handed one line
  naming the project, where it comes from and the Caliber instance; in a clone of a project's repository that has no
  Caliber block, the line instead has Claude offer the setup once (Yes, recommended; Not now; Don't ask again); after the
  agent's own `git push` (or a pull request it opens from the command line), Claude runs the Caliber check in
  the same session; and before each audit or spec verdict it sends, a stamp of who sent it (a subagent or the
  session itself), so Caliber can show that an independent subagent ran the check (in auto mode, which would
  refuse a call a hook changed, the hook also allows that one call of Caliber's own server, so it runs as stamped).

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

Installed in a session that was already running, the plugin's Caliber server is not loaded yet: run
`/reload-plugins`, or start a new session, before `/caliber:setup` (from 1.8.8 the commands say so instead of
using another Caliber connection you may have).

Then sign in once: run `/mcp`, choose `plugin:caliber:caliber` and sign in with your Caliber account (or run
`claude mcp login plugin:caliber:caliber` in a shell). Claude Code renews the sign-in from then on; the
background check on push uses the same sign-in.

#### Keep the plugin up to date

Claude Code updates a plugin by itself only when its marketplace has auto-update on, and for a marketplace
outside Anthropic's own, like `caliber`, it is off by default. Turn it on once:

1. In Claude Code, run `/plugin` and open the **Marketplaces** tab.
2. Select **caliber**, then **Enable auto-update**.

From then on Claude Code checks the marketplace when a session starts and downloads a new version; it says
`Plugin updated: caliber · Run /reload-plugins to apply`. Run `/reload-plugins`, or start a new session, to
use it.

To update now instead: in a session, `/plugin` → **Installed** → **caliber** → **Update now**; from a shell,
`claude plugin update caliber@caliber`. `/caliber:status` tells you when the installed plugin is older than
your Caliber expects.

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
The block names the project, and every command works on that project.

A clone can name its own project instead: `/caliber:project <slug>`, or
`git config --local caliber.project <slug>`. It is for that clone only (only the clone's local git config
counts, never a global one), it comes before the block in every command and in the hooks, and nothing is
stored on the server. Use it in a repository that cannot carry a block, in a monorepo of several projects, or
before setup. `/caliber:project --unset` (or `git config --local --unset caliber.project`) goes back to the
block. With neither, a command uses your only project, or lists the projects you can see and asks which one.

A session in a repository set up for Caliber starts with one line of context for Claude (not shown to you) such as
``Caliber: project `checkout` (the Caliber block) · app.caliberhq.io``: the project, where it comes from
(this clone's `caliber.project`, the block, or a warning when the two name different projects) and the
instance the plugin talks to. `/caliber:status` starts with the same.

From plugin 1.8.7 the same session start also compares the plugin with the versions your Caliber recommends
and needs (`<instance>/mcp/plugin/versions`, read at most once a day and kept in `~/.cache/caliber`): below the
recommended version Claude tells you once a day that a newer plugin is out, and below the oldest one Caliber
serves it asks you to update before it uses Caliber.

From plugin 1.9.0 `/caliber:setup` and `/caliber:setup-usage` read the clone's remotes (`git remote -v`, passed as
`host/owner/name`, never with a user or token) so that Caliber sends only the steps that fit this repository.

A clone that has no Caliber block and no `caliber.project` is offered the setup instead, the first time the
session needs a Caliber project and one of your projects lists the clone's origin: **Yes (Recommended)** runs
`/caliber:setup` for that project, **not now** leaves it for the next session, and **don't ask again** is
remembered for the clone (`git config --local caliber.askSetup false`; `--unset` turns the offer back on).
Nothing is written without your answer.

| Command | What it does |
|---|---|
| `/caliber:prd <feature>` | Write a PRD and save it for approval |
| `/caliber:brief <change>` | Write a technical brief |
| `/caliber:tech-spec <prd-key>` | Design the approach and write the tech spec |
| `/caliber:plan <spec-key>` | Write the implementation plan |
| `/caliber:write <type> <what>` | Write a document of one of the project's types: its own (an ADR, a runbook…) or a built-in one (when the organization has document types on) |
| `/caliber:comments <spec-key>` | Work through a spec's open comment threads (when collaboration is on) |
| `/caliber:check [pr-number]` | Check the pull request with the project's audits |
| `/caliber:fix [pr-number]` | Fix the open findings, one commit each |
| `/caliber:open-pr [spec-key]` | Open the pull request, link it to its spec and check it |
| `/caliber:audit [audit-slug] [scope]` | Run one audit, or every audit the project runs |
| `/caliber:code-audit [scope]` | Full code audit |
| `/caliber:security-audit [scope]` | Full security audit |
| `/caliber:describe-specs` | Propose one-line descriptions for specs that have none, and save the ones you agree to |
| `/caliber:status` | The project's status and the next step |
| `/caliber:setup` | Set up this repository for Caliber, then your own usage (`/caliber:setup-usage`) |
| `/caliber:setup-usage [project-slug]` | Set up your own usage: a client repository's commit sync (the last 30 days at once; a self-hosted GitHub, GitLab or Bitbucket server's too) and your agents' telemetry |
| `/caliber:projects` | The projects you can use, this clone's marked, and the instance |
| `/caliber:project [slug\|--unset]` | Show, set or clear this clone's project (`caliber.project`) |

The check after a push runs only in a repository with the Caliber block or a `.caliber/` directory; the
session's line names the project there and offers the setup elsewhere (above). The check after
a push stays quiet when the repository's own `.claude/settings.json` still runs Caliber's hook from
`.caliber/hooks/` (a setup from before hooks version 31); turn it off for one clone with
`git config --local caliber.checkInSession false`. From hooks version 31 nothing of the hooks is in the
repository: the git hook's scripts are in the clone's git directory (`<git common dir>/caliber/hooks/`), and
at the start of a session the plugin replaces older copies there with its own.

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
`plugin_version` that `plugins/caliber/commands/status.md`, `setup.md` and `setup-usage.md` pass, together. The
server address never changes between releases, so installed copies keep their sign-in after an update.

`plugins/caliber/scripts/` holds byte-identical copies of the server's five hook files
(`backend/app/services/caliber/hooks/` in `infinum/caliber`: `agent-post-push.sh`, `pre-push`, `sync.py`,
`check-on-push.sh` and, from hooks version 20, `stamp-invoker.py`), of one hooks version. When the server's
scripts change, copy all of them and record each
`<hooks version> <sha256> [<file>]` in `scripts/server-hooks.sha256` (a line without a file name is
`agent-post-push.sh`'s): new lines for a new hooks version; a line is fixed once its hooks version is released.
The session hook starts a virtual clone's commit sync with the plugin's own `pre-push` (from 1.4.0), and from
1.8.0 `/caliber:setup` and `/caliber:setup-usage` copy these files when their sha256 is the server's, instead of
fetching them one by one.

CI has no checkout of the server, so it compares the copy with the pinned sha256 only: it cannot see the
server's script change under the same hooks version. Before every release, run `check-release.sh` by hand with
`CALIBER_SERVER_DIR` pointing at a current checkout of `infinum/caliber`.

```
scripts/check-release.sh                                   # what CI runs
CALIBER_SERVER_DIR=../caliber scripts/check-release.sh     # also compares with a checkout of the server
claude plugin validate --strict .
claude plugin validate --strict plugins/caliber
```

## Licence

Apache License 2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE).
