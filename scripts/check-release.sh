#!/bin/sh
# Fails unless this commit is a consistent release of the plugin:
#   - plugin.json's version equals the plugin_version that commands/status.md passes;
#   - .mcp.json's server has no headers (they are part of the sign-in's key) and its URL is .../mcp/plugin;
#   - scripts/agent-post-push.sh is the server's file for its hooks version (scripts/server-hooks.sha256,
#     and the file itself when CALIBER_SERVER_DIR names a checkout of infinum/caliber), and is executable;
#   - every command exists and allows its own tool.
# Run from anywhere:  scripts/check-release.sh
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

# 4. The commands, each allowing its own tool.
for name in prd brief tech-spec plan comments check fix open-pr audit code-audit security-audit status setup; do
  file="$plugin/commands/$name.md"
  if [ ! -f "$file" ]; then
    fail "commands/$name.md is missing"
  elif ! grep -Eq "^allowed-tools:.*mcp__plugin_caliber_caliber__$name(,|\$| )" "$file"; then
    fail "commands/$name.md does not allow mcp__plugin_caliber_caliber__$name"
  fi
done
count=$(find "$plugin/commands" -name '*.md' | wc -l | tr -d ' ')
[ "$count" -eq 13 ] || fail "expected 13 commands, found $count"

[ "$failed" -eq 0 ] || exit 1
echo "check-release: ok (plugin $version, hooks version $hooks_version)"
