#!/bin/sh
# Fails unless this commit is a consistent release of the plugin:
#   - plugin.json's version equals the plugin_version that commands/status.md passes;
#   - .mcp.json's server has no headers (they are part of the sign-in's key) and its URL is .../mcp/plugin;
#   - scripts/agent-post-push.sh is the server's file for its hooks version (scripts/server-hooks.sha256,
#     and the file itself when CALIBER_SERVER_DIR names a checkout of infinum/caliber), and is executable;
#   - hooks/hooks.json runs agent-post-push.sh with the `claude plugin` marker after each Bash command, and
#     with `claude plugin session` at the start of a session;
#   - every command exists and allows exactly its own tool, projects and Read, plus reading this clone's
#     caliber.project (a command that resolves the project) or setting and unsetting it (/caliber:project).
# Run from anywhere:  scripts/check-release.sh
#
# CI has no checkout of the server, so it compares the hook script with the pinned sha256 only and cannot see
# the server's file change under the same hooks version. Before tagging a release, run it by hand against a
# current checkout of infinum/caliber as well:  CALIBER_SERVER_DIR=../caliber scripts/check-release.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
plugin="$root/plugins/caliber"
failed=0
fail() { echo "check-release: $*" >&2; failed=1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# 1. The version, in plugin.json and in the status command.
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
  "$plugin/.claude-plugin/plugin.json")
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "plugin.json version '$version' is not x.y.z"
# shellcheck disable=SC2016 # the backticks are literal: the command file quotes the argument name
passed=$(grep -o '`plugin_version` = "[^"]*"' "$plugin/commands/status.md" | sed 's/.*= "\(.*\)"/\1/')
[ "$(printf '%s\n' "$passed" | grep -c .)" -eq 1 ] \
  || fail "commands/status.md must pass plugin_version exactly once (found: '$passed')"
[ "$passed" = "$version" ] \
  || fail "commands/status.md passes plugin_version '$passed', plugin.json says '$version'"

# 2. The MCP server: URL only, on /mcp/plugin.
python3 - "$plugin/.mcp.json" <<'PY' || failed=1
import json, sys
servers = json.load(open(sys.argv[1]))["mcpServers"]
bad = []
if list(servers) != ["caliber"]:
    bad.append(f"expected one server 'caliber', found {list(servers)}")
for name, server in servers.items():
    if "headers" in server:
        bad.append(f"server '{name}' has headers")
    if not str(server.get("url", "")).endswith("/mcp/plugin"):
        bad.append(f"server '{name}' url does not end in /mcp/plugin")
for b in bad:
    print(f"check-release: .mcp.json: {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

# 3. The hook script: the server's, byte for byte.
hook="$plugin/scripts/agent-post-push.sh"
[ -x "$hook" ] || fail "scripts/agent-post-push.sh is not executable"
hooks_version=$(sed -n 's/.*caliber-hooks-version: \([0-9][0-9]*\).*/\1/p' "$hook" | head -n 1)
if [ -z "$hooks_version" ]; then
  fail "scripts/agent-post-push.sh has no caliber-hooks-version line"
else
  pinned=$(awk -v v="$hooks_version" '$1 == v { print $2 }' "$root/scripts/server-hooks.sha256")
  if [ -z "$pinned" ]; then
    fail "scripts/server-hooks.sha256 has no line for hooks version $hooks_version"
  elif [ "$(sha256 "$hook")" != "$pinned" ]; then
    fail "scripts/agent-post-push.sh differs from the server's file for hooks version $hooks_version"
  fi
  if [ -n "${CALIBER_SERVER_DIR:-}" ]; then
    server="$CALIBER_SERVER_DIR/backend/app/services/caliber/hooks/agent-post-push.sh"
    if ! grep -q "caliber-hooks-version: $hooks_version\$" "$server" 2>/dev/null; then
      fail "$server is not hooks version $hooks_version"
    elif ! cmp -s "$hook" "$server"; then
      fail "scripts/agent-post-push.sh differs from $server"
    fi
  fi
fi

# 4. The session hooks, with the marker that keeps them quiet outside Caliber repositories: after each Bash
#    command, and the session's line at its start (every SessionStart: startup, resume, clear, compact).
python3 - "$plugin/hooks/hooks.json" <<'PY' || failed=1
import json, sys
script = '"${CLAUDE_PLUGIN_ROOT}"/scripts/agent-post-push.sh'
hooks = json.load(open(sys.argv[1]))["hooks"]
bad = []
for event, matcher, args in (("PostToolUse", "Bash", "claude plugin"),
                             ("SessionStart", None, "claude plugin session")):
    want = f"{script} {args}"
    found = [h for e in hooks.get(event, []) if e.get("matcher") == matcher
             for h in e.get("hooks", []) if h.get("type") == "command" and h.get("command") == want]
    runs = [h for e in hooks.get(event, []) for h in e.get("hooks", [])
            if script in str(h.get("command", ""))]
    if len(found) != 1 or len(runs) != 1:
        on = f"{event} {matcher}" if matcher else f"{event} (no matcher)"
        bad.append(f"hooks/hooks.json must run {want} once on {on}, and the script nothing else there")
for b in bad:
    print(f"check-release: {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

# 5. The commands, each allowing exactly what it needs: its own tool (/caliber:project has none of its own),
#    projects and Read, and nothing else. Every other command resolves the project, so it reads this clone's
#    caliber.project; /caliber:project sets and unsets it. An allowed tool is one entry between commas.
get='Bash(git config --local --get caliber.project)'
set_project='Bash(git config --local caliber.project:*)'
unset_project='Bash(git config --local --unset caliber.project)'
nl='
'
# The lines of $1 that are not lines of $2, each after a space.
absent() {
  printf '%s\n' "$1" | while IFS= read -r line; do
    case "$nl$2$nl" in
      *"$nl$line$nl"*) ;;
      *) printf ' %s' "$line" ;;
    esac
  done
}
for name in prd brief tech-spec plan comments check fix open-pr audit code-audit security-audit status setup \
    setup-usage describe-specs projects project; do
  file="$plugin/commands/$name.md"
  if [ ! -f "$file" ]; then
    fail "commands/$name.md is missing"
    continue
  fi
  case $name in
    project) wanted="mcp__plugin_caliber_caliber__projects,$set_project,$unset_project,Read" ;;
    projects) wanted="mcp__plugin_caliber_caliber__projects,$get,Read" ;;
    *) wanted="mcp__plugin_caliber_caliber__$name,mcp__plugin_caliber_caliber__projects,$get,Read" ;;
  esac
  have=$(sed -n 's/^allowed-tools:[[:space:]]*//p' "$file" | sed 's/[[:space:]]*,[[:space:]]*/,/g; s/[[:space:]]*$//' \
    | tr ',' '\n' | sort)
  want=$(printf '%s\n' "$wanted" | tr ',' '\n' | sort)
  [ "$have" = "$want" ] && continue
  missing=$(absent "$want" "$have")
  extra=$(absent "$have" "$want")
  [ -z "$missing" ] || fail "commands/$name.md does not allow:$missing"
  [ -z "$extra" ] || fail "commands/$name.md allows more than it needs:$extra"
  [ -n "$missing$extra" ] || fail "commands/$name.md lists an allowed tool twice"
done
count=$(find "$plugin/commands" -name '*.md' | wc -l | tr -d ' ')
[ "$count" -eq 17 ] || fail "expected 17 commands, found $count"

[ "$failed" -eq 0 ] || exit 1
echo "check-release: ok (plugin $version, hooks version $hooks_version)"
