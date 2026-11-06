#!/bin/sh
# Caliber check on push: the agent session hook. caliber-hooks-version: 31
# Written by /caliber:setup. Do not edit: the next version replaces the file whole.
#
# Run after each shell command an agent runs:  agent-post-push.sh <agent>
# (claude, codex, cursor, copilot or gemini: the format of its stdin and stdout). After
# a successful `git push`, or a pull request opened from the command line, it tells the
# agent to run the Caliber check in this session. Anything else: no output.
#
# The person's entries (hooks v31) run it everywhere as  agent-post-push.sh <agent> user ,
# the Claude Code plugin as  agent-post-push.sh claude plugin : each acts only with a Caliber
# block or .caliber/ (or caliber.project, below), and not where the repository's own entry
# runs a copy that is there. With the user marker it finds the clone from the hook's input
# when it was not started in one (Cursor runs a user hook from ~/.cursor/), and marks a push it
# placed in a clone (seen-<agent> in the clone's git directory: the git hook leaves a push to
# it only then).
# At a session start,  agent-post-push.sh claude plugin session  replaces older copies of the
# scripts in the clone's git directory and the person's folder with the plugin's own, and
# hands the agent one line:
# the project, its source and the Caliber host. Without a project the line has the agent
# offer the setup once, when a project lists the origin (shown without userinfo); never
# with caliber.askSetup false, on a resume or a compaction. Beside the project line, the
# plugin's version against the ones Caliber serves (/mcp/plugin/versions, read at most once a
# day, kept in ~/.cache/caliber): below the minimum the agent uses no Caliber tool until the
# person updates, below the recommended one it suggests the update, at most once a day.
# python3 runs with -I, so a module planted at the repository's root never runs.
#
# In a virtual repository's clone (caliber.syncActivity, a sync token) a session start
# starts the activity sync and offers no setup; an agent's push starts it too, when the
# clone's git hook does not.
#
# After a push it hands the agent the link step too: link the branch to the spec the session
# built it from, when nothing links it yet (features-links). The link step alone, with no
# check: in a clone with only caliber.project, with caliber.checkInSession false, and while
# the git hook checks the push.
#
#   git config --local caliber.checkInSession false    turn the check off for this clone

agent=${1:-claude}
session=""
if [ -n "${3:-}" ]; then
  [ "$#" -eq 3 ] && [ "$1" = "claude" ] && [ "$2" = "plugin" ] && [ "$3" = "session" ] || exit 0
  session=1
fi

# The hooks version a script carries (its second line).
version() { sed -n '2{s/.*caliber-hooks-version: \([0-9][0-9]*\).*/\1/p;q;}' "$1" 2>/dev/null; }
# What the clone's git hook runs for the check: `copy` (the git directory's, a hook installed
# with hooks v17 or later), `tree` (the working tree's, one installed before) or nothing.
# Read from the wrapper's number, never from a path in it: a version 6 or 7 wrapper names
# the git directory's copy too.
hook_runs() {
  hooks=$(git rev-parse --git-path hooks 2>/dev/null) || return 0
  case "$hooks" in /*) ;; *) hooks="$(pwd -P)/$hooks" ;; esac
  case "$hooks" in */.husky/_) hooks=${hooks%/_} ;; esac
  grep -qsF '# caliber:check-on-push' "$hooks/pre-push" || return 0
  wrapper=$(sed -n 's/^# caliber-wrapper: \([0-9][0-9]*\)$/\1/p' "$hooks/pre-push" | head -n 1)
  if [ -n "$wrapper" ]; then
    if [ "$wrapper" -ge 8 ]; then echo copy; else echo tree; fi
  elif grep -qsF '/.caliber/hooks/pre-push"' "$hooks/pre-push"; then
    echo tree
  elif grep -qsF -- '--git-common-dir)/caliber/hooks/pre-push"' "$hooks/pre-push"; then
    echo copy
  fi
}

user=""
if [ "${2:-}" = "user" ] && [ -z "${3:-}" ]; then
  user=1
  case "$agent" in claude | codex | cursor | copilot) ;; *) exit 0 ;; esac
  input=$(cat)
  printf '%s' "$input" | grep -q -e push -e 'pr create' -e 'mr create' -e pullrequests || exit 0
  command -v python3 >/dev/null 2>&1 || exit 0
  # The clone: where the hook runs, else the input's cwd; Cursor runs a user hook from
  # ~/.cursor/, so its clone is the one workspace root in a git work tree.
  top=""
  [ "$agent" = cursor ] || top=$(git rev-parse --show-toplevel 2>/dev/null) || top=""
  if [ -z "$top" ]; then
    dirs=$(printf '%s' "$input" | python3 -I -c 'import json, sys
try:
    data = json.loads(sys.stdin.read() or "{}")
except ValueError:
    data = {}
data = data if isinstance(data, dict) else {}
roots = data.get("workspace_roots") if sys.argv[1] == "cursor" else [data.get("cwd")]
for root in roots if isinstance(roots, list) else []:
    if isinstance(root, str) and root.startswith("/") and "\n" not in root:
        print(root)' "$agent" 2>/dev/null) || dirs=""
    found=0
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      tree=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || continue
      # Two folders of one clone are one clone.
      [ "$tree" = "$top" ] || found=$((found + 1))
      top=$tree
    done <<EOF
$dirs
EOF
    [ "$found" -eq 1 ] || exit 0
  fi
  cd "$top" || exit 0
  # The mark that this agent runs the hook and places its pushes in this clone: the git hook
  # leaves a push of this clone to it only then.
  mark=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) \
    && [ -d "$mark/caliber" ] && { : >"$mark/caliber/seen-$agent"; } 2>/dev/null
  # The repository's own entry for this agent runs a copy that is there (set up before
  # hooks v31): it speaks, not this one.
  case "$agent" in
    claude) own=.claude/settings.json ;;
    codex) own=.codex/hooks.json ;;
    cursor) own=.cursor/hooks.json ;;
    *) own=.github/hooks/caliber.json ;;
  esac
  if [ -x "$top/.caliber/hooks/agent-post-push.sh" ] \
      && grep -qsF '.caliber/hooks/agent-post-push.sh' "$top/$own"; then
    exit 0
  fi
  # Claude Code with the Caliber plugin on for this session: the plugin's hook speaks.
  if [ "$agent" = claude ] && python3 -I - "$top" 2>/dev/null <<'PY'
import json
import os
import sys

ID = "caliber@caliber"
home = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def load(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def enabled(settings):
    value = settings.get("enabledPlugins")
    value = value.get(ID) if isinstance(value, dict) else None
    return value if isinstance(value, bool) else None


entries = load(os.path.join(home, "plugins", "installed_plugins.json")).get("plugins")
entries = entries.get(ID) if isinstance(entries, dict) else None
if isinstance(entries, dict):
    entries = [entries]
present = isinstance(entries, list) and any(
    isinstance(entry, dict) and entry.get("scope", "user") == "user" for entry in entries)
choice = None
for path in ((sys.argv[1], ".claude", "settings.local.json"),
             (sys.argv[1], ".claude", "settings.json"), (home, "settings.json")):
    choice = enabled(load(os.path.join(*path)))
    if choice is not None:
        break
sys.exit(0 if present and choice is True else 1)
PY
  then
    exit 0
  fi
  # As the plugin's marker: the check and the line only in a Caliber repository.
  if [ ! -d "$top/.caliber" ] && ! grep -qsF '<!-- caliber:start' "$top/CLAUDE.md" "$top/AGENTS.md"; then
    plain=1     # link only, with caliber.project (read below)
  fi
fi
if [ "${2:-}" = "plugin" ]; then
  top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
  # Only a Caliber repository gets the check and the project line.
  caliber_repo=1
  sync_push=""
  if [ ! -d "$top/.caliber" ] && ! grep -qsF '<!-- caliber:start' "$top/CLAUDE.md" "$top/AGENTS.md"; then
    caliber_repo=""
    if [ -z "$session" ]; then
      if [ "$(git -C "$top" config --local --type=bool --get caliber.syncActivity 2>/dev/null)" = true ]; then
        # A virtual clone: sync here unless the git hook runs the git directory's copy.
        hook=$(git -C "$top" rev-parse --git-path hooks/pre-push 2>/dev/null) || exit 0
        case "$hook" in /*) ;; *) hook="$top/$hook" ;; esac
        gitdir=$(cd "$top" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || gitdir=""
        if grep -qsF '# caliber:check-on-push' "$hook" && grep -qsF '/caliber/hooks/pre-push"' "$hook" \
            && [ -n "$gitdir" ] && [ -x "$gitdir/caliber/hooks/pre-push" ]; then
          exit 0
        fi
        sync_push=1
      else
        plain=1     # link only, with caliber.project (read after the cheap test below)
      fi
    fi
  fi
  # The repository's own copy runs instead, when it is there (set up before hooks v31).
  [ -n "$session" ] || [ -n "$sync_push" ] || [ ! -x "$top/.caliber/hooks/agent-post-push.sh" ] \
    || ! grep -qsF '.caliber/hooks/agent-post-push.sh' "$top/.claude/settings.json" || exit 0
fi

# The program holds no single quote: it is one shell word.
# shellcheck disable=SC2016
program='
import json
import os
import re
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

agent = sys.argv[1]
ROOT = os.environ.get("CALIBER_HOOK_ROOT") or "."
# Only a slug is repeated.
SLUG = re.compile(r"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?")


# The files with the full block,
FULL_FILES = ["AGENTS.md", "CLAUDE.md"]
# and with a pointer; a test keeps it equal to agents.POINTER_FILES.
POINTER_FILES = [
    ".github/copilot-instructions.md", ".cursor/rules/*.mdc", ".cursorrules",
    ".omp/AGENTS.md", ".devin/rules/*.md", ".junie/AGENTS.md", ".clinerules?",
    ".cline/rules/*.md", ".agents/rules/*.md", ".windsurf/rules/*.md", ".windsurfrules",
    ".kiro/steering/*.md", "QWEN.md", ".hermes.md", "HERMES.md", ".rules", "WARP.md",
]


def marked(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return "<!-- caliber:start" in fh.read(1000000)
    except OSError:
        return False


def expand(entry):
    if entry.endswith("?"):
        path = os.path.join(ROOT, entry[:-1])
        if os.path.isfile(path):
            return [entry[:-1]]
        return expand(entry[:-1] + "/*.md") if os.path.isdir(path) else []
    if "/*." in entry:
        directory, pattern = entry.rsplit("/", 1)
        try:
            names = sorted(os.listdir(os.path.join(ROOT, directory)))
        except OSError:
            return []
        found = []
        for name in names:
            path = os.path.join(ROOT, directory, name)
            if name.endswith(pattern[1:]) and os.path.isfile(path) and marked(path):
                found.append(directory + "/" + name)
        return found
    return [entry] if os.path.isfile(os.path.join(ROOT, entry)) else []


def instruction_files():
    """The full-block files, then the pointer files found, sorted."""
    return FULL_FILES + sorted({p for entry in POINTER_FILES for p in expand(entry)})


def block():
    """(whether a Caliber block is there, the project it names or None)."""
    for name in instruction_files():
        try:
            with open(os.path.join(ROOT, name), encoding="utf-8", errors="replace") as fh:
                text = fh.read(1000000)
        except OSError:
            continue
        start = text.find("<!-- caliber:start")
        if start < 0:
            continue
        end = text.find("<!-- caliber:end -->", start)
        found_in = text[start:end if end >= 0 else len(text)]
        found = re.search(r"get_project\(project=\x22([^\x22]*)\x22\)", found_in) \
            or re.search(r"Caliber project `([^`]*)`", found_in)
        return True, (found.group(1) if found and SLUG.fullmatch(found.group(1)) else None)
    return False, None


def block_slug():
    """The project the Caliber block names, or None."""
    return block()[1]


def origin_for_context():
    """The origin without userinfo (it may hold a token), or `unknown`."""
    raw = (os.environ.get("CALIBER_HOOK_ORIGIN") or "").strip()
    if "://" in raw:
        scheme, _, rest = raw.partition("://")
        netloc, slash, path = rest.partition("/")
        raw = scheme + "://" + netloc.rsplit("@", 1)[-1] + slash + path
    else:
        scp = re.match(r"(?:(.*)@)?([^@:/]+):(.*)\Z", raw, re.DOTALL)
        if scp:
            raw = ("git@" if scp.group(1) == "git" else "") + scp.group(2) + ":" + scp.group(3)
    return raw if re.fullmatch(r"[A-Za-z0-9._:@/+-]{1,200}", raw) else "unknown"


def tag_refspec(spec):
    """Whether a push refspec names a tag."""
    return (spec or "").rpartition(":")[2].startswith("refs/tags/")


def push_sources(args, positional):
    """The local refs a push sends; "*" for every branch; no tags."""
    if any(a in ("--all", "--mirror", "--branches") for a in args):
        return ["*"]
    found = ["HEAD"] if not positional[1:] and "--tags" not in args else []
    for spec in positional[1:]:
        source, colon, dst = (spec or "").lstrip("+").rpartition(":")
        source = source if colon else dst
        if source and not tag_refspec(spec) and not source.startswith("refs/tags/"):
            # A pattern stays one.
            found.append("HEAD" if source == "@" else source)
    return found


def this_directory(paths):
    """Whether `git -C <path>...` names here or the top of this clone."""
    base = os.getcwd()
    for path in paths:
        if path is None:
            return False  # an expansion: unknown here
        base = os.path.join(base, path)
    return os.path.realpath(base) in (os.path.realpath(os.getcwd()), os.path.realpath(ROOT))


def clone_slug():
    """The caliber.project of this clone, when a slug."""
    value = os.environ.get("CALIBER_HOOK_PROJECT") or ""
    return value if SLUG.fullmatch(value) else None


# The plugin against the versions Caliber serves (brief plugin-version-check).
VERSIONS_EVERY = 86400
UPDATE = ("update with `/plugin` \u2192 Installed \u2192 caliber \u2192 Update now, then "
          "`/reload-plugins` (or `claude plugin update caliber@caliber` in a shell)")
AUTO = ("; to get updates without asking, `/plugin` \u2192 Marketplaces \u2192 caliber "
        "\u2192 Enable auto-update")


def version_of(text):
    """x.y.z as three numbers; None for anything else."""
    found = re.fullmatch(r"(\d{1,6})\.(\d{1,6})\.(\d{1,6})", text if isinstance(text, str) else "")
    return tuple(int(part) for part in found.groups()) if found else None


def recent(value, now):
    return isinstance(value, (int, float)) and 0 <= now - value < VERSIONS_EVERY


def ask_versions(base):
    """base/mcp/plugin/versions, or None; at most 4 seconds in all, the name lookup too (the
    timeout of urlopen bounds the socket alone)."""
    answer = {}

    def ask():
        try:
            request = Request(base + "/mcp/plugin/versions", headers={"Accept": "application/json"})
            with urlopen(request, timeout=3) as res:
                answer["got"] = json.loads(res.read(4096))
        except Exception:  # noqa: BLE001 - an old Caliber, offline, a timeout: the kept versions
            pass

    worker = threading.Thread(target=ask, daemon=True)
    worker.start()
    worker.join(4)
    return answer.get("got")


def merged_versions(path, base, entry):
    """The cache as it is now, with the entry of this session for base merged in (v24): a
    session that asked while another one did keeps the newer answer, and the later told_at."""
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError):
        state = {}
    state = state if isinstance(state, dict) else {}
    theirs = state.get(base)
    theirs = theirs if isinstance(theirs, dict) else {}
    now = time.time()
    def stamp(value):
        # A stamp later than now (a clock set back) counts for nothing.
        return value if isinstance(value, (int, float)) and value <= now else 0
    if stamp(theirs.get("read_at")) > stamp(entry.get("read_at")):
        for key in ("minimum", "recommended", "read_at"):
            if key in theirs:
                entry[key] = theirs[key]
    for key in ("tried_at", "told_at"):
        if stamp(theirs.get(key)) > stamp(entry.get(key)):
            entry[key] = theirs[key]
    return state


def keep_versions(path, state):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        temporary = path + "." + str(os.getpid())
        with open(temporary, "w", encoding="utf-8") as f:
            json.dump(state, f)
        os.replace(temporary, path)
    except OSError:
        pass


def plugin_update_note(base):
    """What the agent is told of this plugin against base/mcp/plugin/versions, asked at most
    once a day per instance (tried_at) and used for a day after an answer (read_at), kept with
    when the agent was last told; empty when current, unknown or not read for a day."""
    root = os.environ.get("CALIBER_HOOK_PLUGIN_ROOT")
    # The check run the push hook starts: nobody reads its session, so it is told nothing.
    if not root or os.environ.get("CALIBER_PUSH_HOOK_RUN") == "1":
        return ""
    try:
        with open(os.path.join(root, ".claude-plugin", "plugin.json"), encoding="utf-8") as f:
            own = version_of(json.load(f).get("version"))
    except (OSError, ValueError, AttributeError):
        own = None
    if own is None:
        return ""
    cache = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    path = os.path.join(cache, "caliber", "plugin-versions.json")
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError):
        state = {}
    state = state if isinstance(state, dict) else {}
    entry = state.get(base)
    entry = entry if isinstance(entry, dict) else {}
    now = time.time()
    if not recent(entry.get("tried_at"), now):
        entry["tried_at"] = now  # asked again tomorrow, also when Caliber does not answer
        # Kept before the request: a session hook stopped while it waits does not ask again.
        state[base] = entry
        keep_versions(path, state)
        got = ask_versions(base)
        if isinstance(got, dict) and version_of(got.get("minimum")) \
                and version_of(got.get("recommended")):
            entry["minimum"], entry["recommended"] = got["minimum"], got["recommended"]
            entry["read_at"] = now
    # Another session may have asked meanwhile: its answer counts here too (v24).
    state = merged_versions(path, base, entry)
    # Versions no answer confirmed for a day are not used: an old or unreachable Caliber
    # stops the notes after a day.
    fresh = recent(entry.get("read_at"), now)
    minimum = version_of(entry.get("minimum")) if fresh else None
    recommended = version_of(entry.get("recommended")) if fresh else None
    shown = ".".join(str(part) for part in own)
    note = ""
    if minimum and own < minimum:
        note = ("Caliber: the Caliber plugin " + shown + " is older than " + entry["minimum"]
                + ", the oldest this Caliber serves. Before you use a Caliber tool, tell the "
                "person, and use none until they have updated: " + UPDATE + ".")
    elif recommended and own < recommended and not recent(entry.get("told_at"), now):
        entry["told_at"] = now
        note = ("Caliber: Caliber plugin " + entry["recommended"] + " is out; this one is "
                + shown + ". In your first reply, tell the person once, in one line: " + UPDATE
                + AUTO + ".")
    state = {key: value for key, value in state.items() if key == base or recent(
        value.get("tried_at") if isinstance(value, dict) else None, now)}
    state[base] = entry
    keep_versions(path, state)
    return note


if os.environ.get("CALIBER_HOOK_SESSION"):  # a session start
    override = clone_slug()
    has_block, named = block()
    slug = override or named
    if not slug:
        # No project: offer the setup, unless an old block, the clone or a resume says no.
        try:
            source = (json.load(sys.stdin) or {}).get("source")
        except (ValueError, OSError, AttributeError):
            source = None
        if has_block or (os.environ.get("CALIBER_HOOK_ASK") or "").strip().lower() == "false" \
                or os.environ.get("CALIBER_HOOK_SYNC") or source not in (None, "startup", "clear"):
            sys.exit(0)
        offer = ("Caliber: this repository has no Caliber block and no `caliber.project` "
                 "(origin: `" + origin_for_context() + "`). The first time this session "
                 "needs a Caliber project, call `projects`: when one project lists this "
                 "repository, ask the person once whether to set it up here, with the answers "
                 "Yes (Recommended), Not now and Don\x27t ask again \u2014 yes: the "
                 "`setup` tool with that project\x27s slug, in this session; not now: "
                 "nothing; don\x27t ask again: `git config --local caliber.askSetup false`. "
                 "When none lists it, say nothing.")
        # For the model alone.
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                                 "additionalContext": offer}}))
        sys.exit(0)
    if not os.environ.get("CALIBER_HOOK_CALIBER_REPO"):
        sys.exit(0)  # not a Caliber repository: no line
    if not override:
        source = "the Caliber block"
    elif named and named != override:
        source = "the block names `" + named + "`; this clone\x27s caliber.project overrides it"
    else:
        source = "this clone\x27s caliber.project"
    try:
        host = urlsplit(os.environ.get("CALIBER_URL") or "https://app.caliberhq.io").hostname
    except ValueError:
        host = None
    if not host or not re.fullmatch(r"[a-z0-9.:-]{1,253}", host):
        host = "CALIBER_URL names no plain host"
    line = "Caliber: project `" + slug + "` (" + source + ") \u00b7 " + host
    if host != "CALIBER_URL names no plain host":
        parts = urlsplit(os.environ.get("CALIBER_URL") or "https://app.caliberhq.io")
        if parts.scheme in ("http", "https"):
            note = plugin_update_note(parts.scheme + "://" + parts.netloc)
            line = line + ("\n" + note if note else "")
    if os.environ.get("CALIBER_HOOK_STALE"):
        line = line + ("\nCaliber: this clone\x27s check on push no longer starts: its git hook "
                       "runs `.caliber/hooks/pre-push` of the working tree, which is gone. Tell "
                       "the person once and suggest `/caliber:setup`, which installs the hook "
                       "from the clone\x27s git directory.")
    # For the model alone: a systemMessage would be a warning banner in the Claude apps.
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                             "additionalContext": line}}))
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)


def loads(value):
    """A value some agents send as a JSON string, others as an object."""
    if isinstance(value, str):
        try:
            return json.loads(value)
        except ValueError:
            return value
    return value


def text_of(value):
    """Every string in a tool result, whatever its shape."""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return "\n".join(text_of(v) for v in value.values())
    if isinstance(value, list):
        return "\n".join(text_of(v) for v in value)
    return ""


# Each agent names these its own way.
if agent == "copilot":
    tool_input, result = loads(data.get("toolArgs")), data.get("toolResult")
elif agent == "cursor":
    tool_input, result = loads(data.get("tool_input")), loads(data.get("tool_output"))
else:  # claude, codex, gemini
    tool_input, result = loads(data.get("tool_input")), data.get("tool_response")
command = tool_input.get("command") if isinstance(tool_input, dict) else None
if not isinstance(command, str):
    sys.exit(0)

# The words of each simple command, as the shell reads them (one pass, at most 200 kB);
# a word with an expansion is None. A command substitution is skipped whole, in double
# quotes too, so its quotes and here-documents end nothing outside it.
src, n = command[:200000], min(len(command), 200000)
commands, words, word = [], [], []
has_word = unknown = redirect = False
depth, pending, i = 0, [], 0


def here_document(j):
    """(delimiter, tabs stripped, index after it) of the `<<` at j."""
    j += 2
    tabs = j < n and src[j] == "-"
    j += 1 if tabs else 0
    while j < n and src[j] in " \t":
        j += 1
    k = j
    while k < n and src[k] not in " \t\n;&|<>()":
        k += 1
    return src[j:k].replace("\x27", "").replace("\x22", "").replace("\\", ""), tabs, k


def skip_bodies(j, documents):
    """The index after these here-document bodies, from j."""
    for delimiter, tabs in documents:
        while j < n:
            k = src.find("\n", j)
            k = n if k < 0 else k
            line = src[j:k]
            j = k + 1
            if (line.lstrip("\t") if tabs else line) == delimiter:
                break
    return j


def close_quote(j, nested=0):
    """The index of the closing `"` from j (n: none)."""
    while j < n and src[j] != "\x22":
        if src[j] == "\\":
            j += 2
        elif src.startswith("$(", j):
            j = close_substitution(j + 2, nested + 1)
        elif src[j] == "`":
            k = src.find("`", j + 1)
            j = n if k < 0 else k + 1
        else:
            j += 1
    return min(j, n)


def close_substitution(j, nested=1):
    """The index after the `)` closing the substitution from j (n: none)."""
    if nested > 50:
        return n
    level, documents = 1, []
    while j < n:
        c = src[j]
        if c == "\\":
            j += 2
        elif c == "\x27":
            k = src.find("\x27", j + 1)
            j = n if k < 0 else k + 1
        elif c == "\x22":
            j = close_quote(j + 1, nested) + 1
        elif c == "`":
            k = src.find("`", j + 1)
            j = n if k < 0 else k + 1
        elif src.startswith("$(", j):
            j = close_substitution(j + 2, nested + 1)
        elif src.startswith("<<", j) and not src.startswith("<<<", j):
            delimiter, tabs, j = here_document(j)
            if delimiter:
                documents.append((delimiter, tabs))
        elif c == "\n":
            j, documents = skip_bodies(j + 1, documents), []
        else:
            level += c == "("
            level -= c == ")"
            j += 1
            if level == 0:
                return j
    return n


def end_word():
    global word, has_word, unknown, redirect
    if has_word:
        if redirect:
            redirect = False
        else:
            words.append(None if unknown else "".join(word))
    word, has_word, unknown = [], False, False


def end_command():
    global words
    end_word()
    if words:
        commands.append((depth, words))
    words = []


while i < n:
    c = src[i]
    if c == "\x27":
        j = src.find("\x27", i + 1)
        j = n if j < 0 else j
        word.append(src[i + 1:j])
        has_word, i = True, j + 1
    elif c == "\x22":
        j = i + 1
        while j < n and src[j] != "\x22":
            if src[j] == "\\" and j + 1 < n:
                word.append(src[j + 1])
                j += 2
                continue
            if src.startswith("$(", j):
                unknown, j = True, close_substitution(j + 2)
                continue
            if src[j] == "`":
                k = src.find("`", j + 1)
                unknown, j = True, (n if k < 0 else k + 1)
                continue
            if src[j] == "$":
                unknown = True
            word.append(src[j])
            j += 1
        has_word, i = True, j + 1
    elif c == "\\":
        if i + 1 < n and src[i + 1] != "\n":
            word.append(src[i + 1])
            has_word = True
        i += 2
    elif c == "`":
        j = src.find("`", i + 1)
        has_word, unknown, i = True, True, (n if j < 0 else j + 1)
    elif c == "$" and src.startswith("$(", i):
        has_word, unknown, i = True, True, close_substitution(i + 2)
    elif c == "$":
        word.append(c)
        has_word, unknown, i = True, True, i + 1
    elif c == "#" and not has_word:
        j = src.find("\n", i)
        i = n if j < 0 else j
    elif c in " \t":
        end_word()
        i += 1
    elif c == "\n":
        end_command()
        i, pending = skip_bodies(i + 1, pending), []  # here-document bodies
    elif src.startswith("<<", i) and not src.startswith("<<<", i):
        end_word()
        delimiter, tabs, i = here_document(i)
        if delimiter:
            pending.append((delimiter, tabs))
    elif c in "<>":
        if has_word and "".join(word).isdigit() and not unknown:
            word, has_word = [], False  # the 2 of 2>
        end_word()
        while i < n and src[i] in "<>&":
            i += 1
        redirect = not (i < n and src[i].isdigit() and src[i - 1] == "&")
        if not redirect:
            while i < n and src[i].isdigit():
                i += 1
    elif c in ";&|(){}":
        end_command()
        depth = depth + 1 if c == "(" else max(0, depth - 1) if c == ")" else depth
        i += 1
    else:
        word.append(c)
        has_word, i = True, i + 1
end_command()

WRAPPERS = {"then", "do", "else", "elif", "if", "while", "until", "time", "command",
            "nohup", "exec", "sudo", "!"}
WHERE = {"GIT_DIR", "GIT_WORK_TREE"}
pushed = opened = elsewhere = unnamed = deleted = tagged = more = False
moved, exported = set(), False  # cd at these subshell depths; export GIT_DIR=...
target = None  # the branch a push names
remote = None  # the remote it names
# Where a push naming no remote goes (the sync route asks git), else origin.
PUSH_REMOTE = os.environ.get("CALIBER_HOOK_PUSH_REMOTE") or "origin"
sources = []  # the local refs it sends, for the sync
for level, words in commands:
    moved = {m for m in moved if m <= level}
    k, assigned, env_moved = 0, set(), False
    while k < len(words):
        w = words[k]
        if w in WRAPPERS:
            k += 1
        elif w == "timeout":
            k += 1
            while k < len(words) and words[k] and words[k].startswith("-"):
                k += 1
            k += 1  # the duration
        elif w == "env":
            k += 1
            while k < len(words) and words[k] and words[k].startswith("-"):
                flag = words[k]
                k += 1
                if flag in ("-C", "--chdir", "-u", "--unset") and k < len(words):
                    k += 1
                env_moved = env_moved or flag in ("-C", "--chdir") or flag.startswith("--chdir=")
        elif w and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
            assigned.add(w.split("=", 1)[0])
            k += 1
        else:
            break
    if k >= len(words):
        continue
    name, rest = words[k], words[k + 1:]
    if name in ("cd", "pushd"):
        if not pushed:
            moved.add(level)
        continue
    if name == "export":
        exported = exported or (not pushed and any(
            w and w.split("=", 1)[0] in WHERE for w in rest))
        continue
    if name == "git":
        j, here, chdir = 0, False, []
        while j < len(rest) and rest[j] and rest[j].startswith("-"):
            option = rest[j]
            j += 1
            if option == "-C" and j < len(rest):
                chdir.append(rest[j])
            if option in ("-C", "-c", "--git-dir", "--work-tree", "--namespace") and j < len(rest):
                j += 1
            here = here or option in ("--git-dir", "--work-tree") \
                or option.startswith(("--git-dir=", "--work-tree="))
        here = here or bool(chdir) and not this_directory(chdir)
        if j >= len(rest) or rest[j] != "push":
            continue
        args = rest[j + 1:]
        if any(a in ("--dry-run", "-n", "--delete", "-d") for a in args):
            continue
        positional, m = [], 0
        while m < len(args):
            a = args[m]
            m += 1
            if a is None or not a.startswith("-"):
                positional.append(a)
            elif a in ("-o", "--push-option", "--repo", "--receive-pack", "--exec") \
                    and m < len(args):
                m += 1
        # Tags alone: no check, but a release for the sync.
        if "--tags" in args and all(tag_refspec(s) for s in positional[1:]) \
                and not os.environ.get("CALIBER_HOOK_SYNC_PUSH"):
            continue
        if pushed:
            unnamed = True  # a second push: which to name?
            # Its commits go to the sync too if it sends from here to the same remote.
            later = positional[0] if positional else PUSH_REMOTE
            if not (here or env_moved or bool(moved) or exported or bool(assigned & WHERE)) \
                    and later is not None and later == remote:
                found = push_sources(args, positional)
                sources += found
                more = more or bool(found) or "--tags" in args
            continue
        pushed = True
        elsewhere = here or env_moved or bool(moved) or exported or bool(assigned & WHERE)
        unnamed = unnamed or any(a in ("--all", "--mirror", "--branches") for a in args)
        tagged = "--tags" in args
        remote = positional[0] if positional else PUSH_REMOTE
        refspecs = positional[1:]
        # Local refs: a --single-branch clone has no tracking ref for another branch.
        sources = push_sources(args, positional)
        if len(refspecs) > 1 or None in refspecs:
            unnamed = True
        elif refspecs:
            spec = refspecs[0].lstrip("+")
            source, colon, dst = spec.rpartition(":")
            dst = dst if colon else spec
            if colon and not source:
                deleted = True  # git push origin :branch
            elif dst.startswith("refs/tags/") or (dst.startswith("refs/") and not
                                                  dst.startswith("refs/heads/")):
                unnamed = True
            else:
                dst = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
                target = "HEAD" if dst in ("HEAD", "@") else dst
        continue
    if [name] + rest[:2] in (["gh", "pr", "create"], ["glab", "mr", "create"]):
        opened = True
    elif name == "curl" and any(w and "pullrequests" in w for w in rest) and (
            "POST" in rest or any(w in ("-d", "--data", "--json") or (w or "").startswith(
                ("-XPOST", "--data=", "--request=POST")) for w in rest)):
        opened = True
if deleted and not opened and not ((tagged or more) and os.environ.get("CALIBER_HOOK_SYNC_PUSH")):
    sys.exit(0)  # a deletion (tags or a later push still go to the sync)
if not (pushed or opened):
    sys.exit(0)
current = os.environ.get("CALIBER_HOOK_BRANCH") or ""
if target not in (None, "HEAD", current):
    elsewhere_branch = target  # not the branch checked out here
else:
    elsewhere_branch = None
link_only = bool(os.environ.get("CALIBER_HOOK_LINK_ONLY"))
if not (elsewhere or unnamed) and elsewhere_branch is None \
        and os.environ.get("CALIBER_HOOK_RUNNING"):
    link_only = True  # the git hook is checking this branch; the link is still made here


def checked_here(checked):
    """Whether the git hook checks what this command pushed: `any` (a copy older than v31), else
    the commits its record names; a push it cannot place (several refs) counts as checked."""
    if not checked:
        return False
    if checked == "any" or unnamed:
        return True
    ref = (elsewhere_branch or "HEAD") + "^{commit}"
    try:
        sha = subprocess.run(["git", "rev-parse", "--verify", "--quiet", ref], cwd=ROOT,
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return False
    return bool(sha) and sha in checked.split()


if pushed and not elsewhere and checked_here(os.environ.get("CALIBER_HOOK_CHECKED") or ""):
    link_only = True  # the git hook checks this push (its record); the link is still made here

# A failed command pushed nothing.
if isinstance(result, dict):
    for key in ("exitCode", "exit_code", "returncode", "code"):
        if isinstance(result.get(key), int) and result[key] != 0:
            sys.exit(0)
    if result.get("resultType") in ("failure", "error", "denied", "rejected"):
        sys.exit(0)
    if result.get("error") or result.get("interrupted") is True:
        sys.exit(0)
output = text_of(result)
# A ref updated by any push of the command counts. The lines of a fetch (after From <url>,
# as in git pull --rebase && git push) have the same shape and do not.
updated, fetched = False, False
for line in output.splitlines():
    if re.match(r"^(From|To)\s", line):
        fetched = line.startswith("From")
    elif not fetched and re.match(
            r"^\s*(?:\*|\+|[0-9a-f]{7,}\.\.\.?[0-9a-f]{7,})\s.*\S -> \S", line):
        updated = True
if not updated and (re.search(
        r"(?m)^\s*(?:fatal:|error: failed to push|! \[(?:rejected|remote rejected)\])", output)
        or "Everything up-to-date" in output):
    sys.exit(0)

# A virtual clone: no check. The remote of a push made here (another directory may be
# another repository), then the refs it sent, one a line, none taken for an option.
if os.environ.get("CALIBER_HOOK_SYNC_PUSH"):
    if pushed and not elsewhere:
        print(remote if remote and re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$", remote)
              else "origin")
        for ref in dict.fromkeys(sources):
            plain = re.match(r"^[A-Za-z0-9][A-Za-z0-9._/@+-]{0,254}$", ref or "")
            pattern = re.match(r"^refs/heads/[A-Za-z0-9._/@+-]{0,200}\*[A-Za-z0-9._/@+-]{0,50}$",
                               ref or "")
            if ref == "*" or ((plain or pattern) and ".." not in ref and "@{" not in ref):
                print(ref)
    sys.exit(0)

branch = "" if elsewhere or unnamed else elsewhere_branch or current
if not re.match(r"^[A-Za-z0-9][A-Za-z0-9._/@+#=,-]{0,254}$", branch) or ".." in branch:
    branch = ""
# No project for a command run elsewhere: it may be another repository.
slug = None if elsewhere else clone_slug() or block_slug()
if slug:
    project = ", project=\x22" + slug + "\x22"
    named = " and `project=\x22" + slug + "\x22`"
    hint = ""
else:
    project = named = ""
    hint = ("Pass `project` = the slug the repository\x27s Caliber block names "
            "(`get_project(project=\x22<slug>\x22)`), when it names one, to both calls.\n")

if link_only and not (slug and branch):
    sys.exit(0)  # the link needs the project and the branch
what = ("opened a pull request" if opened and not pushed else "pushed") + (
    " for `" + branch + "`" if opened and not pushed and branch
    else " `" + branch + "`" if branch else " (in the repository and on the branch the command used)")
head = "<git rev-parse " + (branch if branch and branch != current else "HEAD") + ">"
status = ("In the repository the command pushed from: `get_check_status(head_sha=" + head
          + project + ")`")
# The link step (features-links): the spec the session built the change from, only where
# nothing links the branch yet; never a branch other pull requests merge into.
link = ("Link: when its `spec` is empty, `" + branch + "` is not one of its `base_branches`, "
        "and this session built the change from a Caliber spec (the spec it set In progress, "
        "or else the plan, tech spec or brief it built it from), call `link_pr(spec_key=<that "
        "key>, head_branch=\x22" + branch + "\x22, head_sha=" + head + project + ")`; it links "
        "only what nothing links yet. Otherwise link nothing.\n") if branch else ""
if link_only:
    message = (
        "Caliber (link on push): this session just " + what + ". If this session has the "
        "Caliber MCP tools, now, here, without asking first:\n"
        "1. " + status + ".\n"
        "2. " + link +
        "Without the Caliber tools, ignore this."
    )
else:
    message = (
        "Caliber (check on push): this session just " + what + ". If this session has the "
        "Caliber MCP tools, check it now, here, without asking first:\n"
        "1. " + status + " and read `check_timing`.\n"
        + ("2. " + link if link else "") +
        "`manual`: this project runs no automatic checks, do nothing more.\n"
        "`after_pr` and the branch has no pull request yet: do nothing more.\n"
        "Otherwise call the Caliber `check` tool with `push=no`" + named + " and follow "
        "what it returns "
        "(the same as the `/caliber:check` prompt); when it finds nothing with a gap, say so "
        "in one line.\n" + hint +
        "Without the Caliber tools, ignore this. To turn the check off for this clone (the "
        "link stays): `git config --local caliber.checkInSession false`."
    )

if agent == "cursor":
    out = {"additional_context": message}
elif agent == "copilot":
    out = {"additionalContext": message}
else:
    event = "AfterTool" if agent == "gemini" else "PostToolUse"
    out = {"hookSpecificOutput": {"hookEventName": event, "additionalContext": message}}
print(json.dumps(out))'

# A session start: the line alone.
if [ -n "$session" ]; then
  command -v python3 >/dev/null 2>&1 || exit 0
  project=$(git -C "$top" config --local --get caliber.project 2>/dev/null) || project=""
  origin=$(git -C "$top" remote get-url origin 2>/dev/null) || origin=""
  # As git reads a boolean: false, no, off and 0 say no.
  ask=$(git -C "$top" config --type=bool --get caliber.askSetup 2>/dev/null) || ask=""
  # The SessionStart input is on stdin; never read a terminal.
  if [ -t 0 ]; then exec </dev/null; fi
  # A virtual clone: start the sync, detached, and offer no setup. Run the plugin's
  # pre-push, else the git directory's: never the working tree's, which a merge may change.
  sync=""
  if [ "$(git -C "$top" config --local --type=bool --get caliber.syncActivity 2>/dev/null)" = true ]; then
    common=$(cd "$top" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || common=""
    beside=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || beside=""
    syncer="$beside/pre-push"
    if [ -z "$beside" ] || [ ! -x "$syncer" ]; then syncer="$common/caliber/hooks/pre-push"; fi
    if [ -n "$common" ] && [ -f "$common/caliber/sync-token" ] && [ -x "$syncer" ]; then
      sync=1
      (cd "$top" && nohup python3 -I -c 'import os, sys
try:
    os.setsid()
except OSError:
    pass
os.execv(sys.argv[1], sys.argv[1:])' "$syncer" --sync --session \
        </dev/null >/dev/null 2>&1 &)
    fi
  fi
  # Older copies of the scripts, in the clone's git directory and the person's folders (the
  # folder an entry names, and the default one), become the plugin's own: never a newer one,
  # a missing one or one without a version line.
  mine=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || mine=""
  refresh() {
    [ -n "$mine" ] && [ -d "$1" ] || return 0
    there=$(cd "$1" 2>/dev/null && pwd -P) || return 0
    [ "$there" != "$mine" ] || return 0
    for name in pre-push check-on-push.sh agent-post-push.sh sync.py stamp-invoker.py; do
      if [ ! -f "$there/$name" ] || [ ! -f "$mine/$name" ]; then continue; fi
      old=$(version "$there/$name")
      new=$(version "$mine/$name")
      if [ -z "$old" ] || [ -z "$new" ] || ! [ "$new" -gt "$old" ] 2>/dev/null; then continue; fi
      if cp "$mine/$name" "$there/$name.new" 2>/dev/null && chmod 755 "$there/$name.new" \
          && mv -f "$there/$name.new" "$there/$name" 2>/dev/null; then :; else
        rm -f "${there:?}/${name:?}.new"
      fi
    done
  }
  common=$(cd "$top" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || common=""
  [ -z "$common" ] || refresh "$common/caliber/hooks"
  folders=$(sed -n "s/.*h='\([^']*\)\/agent-post-push\.sh'.*/\1/p" \
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "${CODEX_HOME:-$HOME/.codex}/hooks.json" \
    "$HOME/.cursor/hooks.json" "${COPILOT_HOME:-$HOME/.copilot}/hooks/caliber.json" 2>/dev/null)
  while IFS= read -r folder; do
    [ -z "$folder" ] || refresh "$folder"
  done <<EOF
$folders
${XDG_CONFIG_HOME:-$HOME/.config}/caliber/hooks
EOF
  # A git hook installed before hooks v17 runs the working tree's script: once that is gone
  # (removed from the repository), the check on push has stopped.
  stale=""
  if [ "$(git -C "$top" config --local --type=bool --get caliber.checkOnPush 2>/dev/null)" = true ] \
      && [ "$(cd "$top" && hook_runs)" = tree ] && [ ! -x "$top/.caliber/hooks/pre-push" ]; then
    stale=1
  fi
  # The plugin's own root, for its version (plugin.json).
  plugin_root=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P) || plugin_root=""
  CALIBER_HOOK_SESSION=1 CALIBER_HOOK_ROOT=$top CALIBER_HOOK_PROJECT=$project \
    CALIBER_HOOK_CALIBER_REPO=$caliber_repo CALIBER_HOOK_ORIGIN=$origin CALIBER_HOOK_ASK=$ask \
    CALIBER_HOOK_SYNC=$sync CALIBER_HOOK_PLUGIN_ROOT=$plugin_root CALIBER_HOOK_STALE=$stale \
    python3 -I -c "$program" "$agent"
  exit 0
fi

[ -n "$user" ] || input=$(cat)

# Most commands end here, after one grep.
printf '%s' "$input" | grep -q -e push -e 'pr create' -e 'mr create' -e pullrequests || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# A virtual clone: sync a successful push, with the pre-push chosen as above.
if [ -n "${sync_push:-}" ]; then
  common=$(cd "$top" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || exit 0
  [ -f "$common/caliber/sync-token" ] || exit 0
  beside=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || beside=""
  syncer="$beside/pre-push"
  if [ -z "$beside" ] || [ ! -x "$syncer" ]; then syncer="$common/caliber/hooks/pre-push"; fi
  [ -x "$syncer" ] || exit 0
  # Where a push naming no remote goes, as git decides.
  current=$(git -C "$top" symbolic-ref --quiet --short HEAD 2>/dev/null) || current=""
  push_remote=""
  [ -z "$current" ] \
    || push_remote=$(git -C "$top" config --get "branch.$current.pushRemote" 2>/dev/null) || push_remote=""
  [ -n "$push_remote" ] || push_remote=$(git -C "$top" config --get remote.pushDefault 2>/dev/null) || push_remote=""
  [ -n "$push_remote" ] || [ -z "$current" ] \
    || push_remote=$(git -C "$top" config --get "branch.$current.remote" 2>/dev/null) || push_remote=""
  pushed=$(printf '%s' "$input" | CALIBER_HOOK_SYNC_PUSH=1 CALIBER_HOOK_ROOT=$top \
    CALIBER_HOOK_PUSH_REMOTE=$push_remote python3 -I -c "$program" "$agent") || exit 0
  remote=$(printf '%s\n' "$pushed" | sed -n 1p)
  [ -n "$remote" ] || exit 0
  # The branches a pattern names; as in git push, "*" spans slashes. A function:
  # bash 3.2 misreads a `case` inside $(...).
  matching() {
    git -C "$top" for-each-ref --format='%(refname) %(objectname)' refs/heads/ 2>/dev/null \
      | while read -r name sha; do
          # shellcheck disable=SC2254 # the pattern is the refspec's, matched as git does
          case "$name" in $1) printf '%s\n' "$sha" ;; esac
        done
  }
  # The pushed commits, as the git hook would hand them over.
  shas=""
  set -f  # "*" is a word here, never a file name
  for ref in $(printf '%s\n' "$pushed" | sed 1d); do
    if [ "$ref" = "*" ]; then
      found=$(git -C "$top" for-each-ref --format='%(objectname)' refs/heads/ 2>/dev/null) || found=""
    elif [ "${ref#*\*}" != "$ref" ]; then
      found=$(matching "$ref")
    else
      found=$(git -C "$top" rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null) || found=""
    fi
    for sha in $found; do
      case "$sha" in *[!0-9a-f]* | "") ;; *) shas="$shas $sha" ;; esac
    done
  done
  set +f
  # shellcheck disable=SC2086 # the pushed shas: one word each
  (cd "$top" && nohup python3 -I -c 'import os, sys
try:
    os.setsid()
except OSError:
    pass
os.execv(sys.argv[1], sys.argv[1:])' "$syncer" --sync "$remote" $shas \
    </dev/null >/dev/null 2>&1 &)
  exit 0
fi
top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
project=$(git -C "$top" config --local --get caliber.project 2>/dev/null) || project=""
# Link only (see the header): checkInSession false, or a plain clone with caliber.project.
link_only=""
[ "$(git config --type=bool --get caliber.checkInSession 2>/dev/null)" != "false" ] || link_only=1
if [ -n "${plain:-}" ]; then
  [ -n "$project" ] || exit 0
  link_only=1
fi

branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=""
# Whether the git hook's check of this push is running: one check per push.
running=""
if [ -n "$branch" ]; then
  common=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || common=""
  name=$(printf '%s' "$branch" | tr -c 'A-Za-z0-9._-' '_')
  if [ "$name" != "$branch" ]; then
    name="$name-$(printf '%s' "$branch" | git hash-object --stdin | cut -c1-8)"
  fi
  lock="$common/caliber/check-$name.pid"
  if [ -n "$common" ] && [ -f "$lock" ]; then
    read -r pid lock_sha _ <"$lock" 2>/dev/null || pid=""
    case "$pid" in '' | *[!0-9]*) pid="" ;; esac
    # Only a run for this push: the lock is "<pid> <sha>".
    [ "${lock_sha:-}" = "$(git rev-parse --verify --quiet HEAD 2>/dev/null)" ] || pid=""
    # Alive and still the runner (a pid is reused).
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      if [ -r "/proc/$pid/cmdline" ]; then
        tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q 'check-on-push\.sh' && running=1
      else
        ps -o command= -p "$pid" 2>/dev/null | grep -q 'check-on-push\.sh' && running=1
      fi
    fi
  fi
fi

# Whether the clone's git hook checks this push itself (one check per push): its record of
# the push (hooks v31; `background` within 10 minutes, with the commits it checks), or, without
# a fresh one, for the person's entry, a git hook that runs a copy older than v31, which never
# leaves a push to a person's entry (`any`). The program leaves the check out of a push of one
# of those commits (the link step stays); a pull request opened is no push.
checked=""
if [ "$(git config --local --type=bool --get caliber.checkOnPush 2>/dev/null)" = true ]; then
  common=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || common=""
  when=""
  decision=""
  if [ -n "$common" ] && [ -f "$common/caliber/last-push" ]; then
    read -r when decision shas <"$common/caliber/last-push" 2>/dev/null || when=""
  fi
  now=$(date +%s)
  case "$when" in
    "" | *[!0-9]*) when="" ;;
    *) { [ $((now - when)) -ge 0 ] && [ $((now - when)) -le 600 ]; } || when="" ;;
  esac
  if [ -n "$when" ]; then
    [ "$decision" != background ] || checked=$shas
  elif [ -n "$user" ]; then
    case "$(hook_runs)" in
      copy)
        copy=$(version "$common/caliber/hooks/pre-push")
        [ -z "$copy" ] || [ "$copy" -ge 31 ] 2>/dev/null || checked=any
        ;;
      tree) [ ! -x "$top/.caliber/hooks/pre-push" ] || checked=any ;;
    esac
  fi
fi

# The agent's JSON goes to the program on stdin.
printf '%s' "$input" | CALIBER_HOOK_SESSION='' CALIBER_HOOK_BRANCH=$branch \
  CALIBER_HOOK_RUNNING=$running CALIBER_HOOK_ROOT=$top CALIBER_HOOK_PROJECT=$project \
  CALIBER_HOOK_LINK_ONLY=$link_only CALIBER_HOOK_CHECKED=$checked python3 -I -c "$program" "$agent"
