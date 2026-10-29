#!/usr/bin/env python3
# Caliber's activity sync of a virtual repository. caliber-hooks-version: 18
# Written by /caliber:setup-usage. Do not edit: the next version replaces the file whole.
# Run only by the `pre-push --sync` beside it (python3 -I), which decides whether this copy may
# send the token and passes the trigger and state directory in the environment. Authors are
# hashed: clear only the developer's own or an own domain's. One line per run in sync.log;
# nothing on the terminal.
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit

VERSION = 18
STATE = os.environ["CALIBER_SYNC_STATE"]
TRIGGER = os.environ.get("CALIBER_SYNC_TRIGGER") or "manual"
FULL = TRIGGER == "full"
#: `--backfill`: the history from hello's `backfill_since`; done once `sync-backfill` exists.
BACKFILL = TRIGGER == "backfill"
SHA = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?")
PUSHED = [a for a in sys.argv[1:] if SHA.fullmatch(a)] if TRIGGER == "push" else []
#: Bytes a part, requests a run, PRs a page, pages a run (a backfill's).
PART_BYTES, MAX_REQUESTS, PAGE, PAGES, BACKFILL_PAGES = 900 * 1024, 500, 100, 5, 50
#: MESSAGE_CHARS: the server's `COMMIT_MESSAGE_MAX`.
MESSAGE_CHARS, HOUR, LOCK_AGE, WAIT = 4096, 3600, 2 * 3600, 120
UPPER = str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")
SPACE = " \t\n\r\v\f"
#: Git, gh and glab never prompt.
QUIET = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="", SSH_ASKPASS="",
             SSH_ASKPASS_REQUIRE="never", GCM_INTERACTIVE="never", GH_PROMPT_DISABLED="1",
             GH_NO_UPDATE_NOTIFIER="1", GLAB_NO_PROMPT="1", NO_PROMPT="1")
counts = {"commits": 0, "prs": 0, "history": 0, "branches": 0, "tags": 0, "parts": 0,
          "skipped": 0}
#: PRs all read (`done`); the window after each page (`after`).
PAGING = {"done": False, "after": []}
#: Log words besides the counts.
NOTES = {}
os.umask(0o077)


def where(name):
    return os.path.join(STATE, name)


def log(result, **fields):
    """Words and numbers only."""
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    words = " ".join(f"{k}={v}" for k, v in {**counts, **NOTES, **fields}.items())
    try:
        path = where("sync.log")
        lines = []
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.read().splitlines()[-499:]
        lines.append(f"{stamp} trigger={TRIGGER} result={result} {words}")
        with open(path + ".new", "w") as fh:
            fh.write("\n".join(lines) + "\n")
        os.replace(path + ".new", path)
    except OSError:
        pass


def read(name):
    try:
        with open(where(name), encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError):
        return None


def save(name, text):
    if moved():
        return
    with open(where(name) + ".new", "w") as fh:
        fh.write(text)
    os.replace(where(name) + ".new", where(name))


def run(args, stdin=None, timeout=120, env=QUIET, raw=False):
    """None on a failure or timeout."""
    try:
        proc = subprocess.run(args, input=stdin, capture_output=True, timeout=timeout,
                              env=env, stdin=None if stdin is not None else subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout if raw else proc.stdout.decode("utf-8", "replace")


def git(*args, timeout=120):
    return run(["git", *args], timeout=timeout)


def config(key):
    return (git("config", "--get", key) or "").strip()


QUIET["GIT_SSH_COMMAND"] = (os.environ.get("GIT_SSH_COMMAND") or config("core.sshCommand")
                            or "ssh") + " -o BatchMode=yes"


def norm(value):
    """The server's rule."""
    return value.strip(SPACE).translate(UPPER)


def hashed(kind, value):
    return hashlib.sha256(f"{SALT}:{kind}:{norm(value)}".encode()).hexdigest()


def b64(text):
    return base64.urlsafe_b64encode(text.encode("utf-8")).decode().rstrip("=")


def field(value):
    return re.sub(r"[\t\r\n]", " ", value or "")


def when(value):
    """An ISO date, or "" (GitHub's zero date too)."""
    return value if isinstance(value, str) and value and not value.startswith("0001-") else ""


def count(value):
    return str(value) if isinstance(value, int) and not isinstance(value, bool) else ""


def plain(url):
    """As --install records it."""
    try:
        parts = urlsplit(url)
    except ValueError:
        return False
    host = parts.hostname or ""
    local = host in ("localhost", "127.0.0.1", "::1")
    return bool(re.fullmatch(r"https?://[A-Za-z0-9.\-:\[\]]+(/[A-Za-z0-9._~/%\-]*)?", url)) \
        and (parts.scheme == "https" or (parts.scheme == "http" and local)) and bool(host) \
        and parts.username is None and parts.password is None


def repository_of(url):
    """`host/owner/name`, or None."""
    url = (url or "").strip()
    if "://" in url:
        try:
            parts = urlsplit(url)
            host, path = parts.hostname or "", parts.path
        except ValueError:
            return None
    else:
        found = re.fullmatch(r"(?:[^@/:]+@)?([^@/:]+):(.+)", url)
        if not found:
            return None
        host, path = found.group(1), found.group(2)
    path = path.strip("/")
    path = path[:-4] if path.endswith(".git") else path
    host = host.lower()
    host = host[4:] if host.startswith("www.") else host
    key = f"{host}/{path}"
    return key if re.fullmatch(r"[a-z0-9.-]+(?:/[A-Za-z0-9._-]+){2,}", key) else None


class Stay(urllib.request.HTTPRedirectHandler):
    """The token goes to the recorded endpoint only."""

    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(Stay())


def post(path, body, kind):
    request = urllib.request.Request(BASE + path, data=body, method="POST", headers={
        "Authorization": "Bearer " + TOKEN, "Content-Type": kind,
        "User-Agent": f"caliber-hooks/{VERSION}"})
    try:
        with OPENER.open(request, timeout=60) as answer:
            return answer.status, answer.read(65536).decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(65536).decode("utf-8", "replace")
    except (OSError, ValueError):
        return 0, ""


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except (PermissionError, OverflowError):
        return True
    return True


# 1. Token and endpoint.
TOKEN = (read("sync-token") or "").strip()
endpoint = config("caliber.mcpUrl")
if not re.fullmatch(r"clb_[A-Za-z0-9_-]{16,200}", TOKEN) or not plain(endpoint):
    sys.exit(0)
base_path = urlsplit(endpoint).path.rstrip("/")
for suffix in ("/mcp/plugin", "/mcp"):
    if base_path.endswith(suffix):
        base_path = base_path[:-len(suffix)]
        break
BASE = f"{urlsplit(endpoint).scheme}://{urlsplit(endpoint).netloc}{base_path}"
SALT = ""


def moved():
    """Whether setup-usage moved the sync since this run read them."""
    return (read("sync-token") or "").strip() != TOKEN or config("caliber.mcpUrl") != endpoint


# 2. After the push (2 min at most); a session's run hourly; one at a time.
waited = os.environ.get("CALIBER_SYNC_WAIT") or ""
if waited.isdigit():
    deadline = time.time() + WAIT
    while alive(int(waited)) and time.time() < deadline:
        time.sleep(0.2)
if TRIGGER == "session":
    try:
        last = float((read("sync-last") or "0").split()[0])
    except (ValueError, IndexError):
        last = 0.0
    if time.time() - last < HOUR:
        sys.exit(0)


def take_lock():
    path = where("sync.lock")
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        try:
            pid, started = (int(x) for x in (read("sync.lock") or "0 0").split()[:2])
        except ValueError:
            pid, started = 0, 0
        if pid > 0 and alive(pid) and time.time() - started < LOCK_AGE:
            return False
        try:
            os.remove(path)            # dead or stale: taken over
        except OSError:
            return False
        return take_lock()
    with os.fdopen(fd, "w") as fh:
        fh.write(f"{os.getpid()} {int(time.time())}\n")
    return True


deadline = time.time() + (WAIT if TRIGGER in ("push", "backfill") else 0)
while not take_lock():
    if time.time() >= deadline:
        sys.exit(0)                    # another run holds it
    time.sleep(1)


def release():
    try:
        if (read("sync.lock") or "").split()[:1] == [str(os.getpid())]:
            os.remove(where("sync.lock"))
    except OSError:
        pass


# Again under the lock setup-usage holds to move the sync: never the old token or state.
if moved():
    log("moved")
    release()
    sys.exit(0)

own_email = config("user.email")
logins = {}
#: gh, glab and APIs allowed: the last hello's `cli` until this one answers.
CLI = {"on": (read("sync-cli") or "").strip() == "1"}


def own_login(host):
    """From the host's CLI: never guessed, never asked without `cli`."""
    if not CLI["on"]:
        return ""
    if host not in logins:
        login = ""
        if host == "github.com" and shutil.which("gh"):
            login = run(["gh", "api", "--hostname", "github.com", "user", "--jq", ".login"],
                        timeout=30) or ""
        elif host == "gitlab.com" and shutil.which("glab") and shutil.which("jq"):
            out = run(["glab", "api", "--hostname", "gitlab.com", "user"], timeout=30)
            login = run(["jq", "-r", ".username // empty"], stdin=out.encode(),
                        timeout=30) or "" if out else ""
        login = login.strip()
        logins[host] = login if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,254}", login) else ""
    return logins[host]


def default_branch(remote, host, path):
    found = re.search(r"^ref: refs/heads/(\S+)\tHEAD$",
                      git("ls-remote", "--symref", remote, "HEAD", timeout=30) or "", re.M)
    branch = found.group(1) if found else ""
    if not branch and CLI["on"] and host == "github.com" and shutil.which("gh"):
        branch = run(["gh", "repo", "view", f"{host}/{path}", "--json", "defaultBranchRef",
                      "--jq", ".defaultBranchRef.name"], timeout=30) or ""
    if not branch and CLI["on"] and host == "gitlab.com" and shutil.which("glab") \
            and shutil.which("jq"):
        out = run(["glab", "api", "--hostname", "gitlab.com",
                   "projects/" + urllib.parse.quote(path, safe="")], timeout=30)
        branch = (run(["jq", "-r", ".default_branch // empty"], stdin=out.encode(),
                      timeout=30) or "") if out else ""
    if not branch:
        branch = (git("symbolic-ref", "--quiet", "--short", f"refs/remotes/{remote}/HEAD")
                  or "").strip()
        branch = branch[len(remote) + 1:] if branch.startswith(remote + "/") else ""
    branch = branch.strip()
    return branch if re.fullmatch(r"[A-Za-z0-9._/-]{1,255}", branch) and ".." not in branch \
        else ""


first = read("sync-tips") is None
platform = sys.platform if sys.platform in ("darwin", "linux") else "other"
asked = {"suggest": True}


def hello(remote, key):
    """A dict, {} for a 204, None on a failure."""
    host, path = key.split("/", 1)
    asked["branch"] = default_branch(remote, host, path)
    fields = {"repository": key, "default_branch": asked["branch"],
              "own_email": own_email, "own_login": own_login(host),
              "first": "1" if first else "0", "suggest": "1" if asked["suggest"] else "0",
              "trigger": TRIGGER, "version": str(VERSION), "platform": platform}
    asked["suggest"] = False
    status, text = post("/caliber/sync/hello", urllib.parse.urlencode(fields).encode(),
                        "application/x-www-form-urlencoded")
    if status == 204:
        return {}
    if status != 200:
        return None
    answer = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
    return answer if answer.get("run") else None


def main():
    global SALT
    # 3. Remotes, in order.
    remotes = (git("remote") or "").split()
    wanted = config("caliber.syncRepository").lower()
    wanted = wanted[:-4] if wanted.endswith(".git") else wanted
    keys = {r: repository_of(config(f"remote.{r}.url")) for r in remotes}
    named = [r for r in remotes if wanted and (keys[r] or "").lower() == wanted]
    order = named or sorted((r for r in remotes if keys[r]),
                            key=lambda r: ({"origin": 0, "upstream": 1}.get(r, 2), r))
    if not order:
        log("no-remote")
        return
    # 4. hello, remote by remote.
    remote = key = answer = None
    status = 204
    for candidate in order:
        answer = hello(candidate, keys[candidate])
        if answer:
            remote, key = candidate, keys[candidate]
            break
        if answer is None:
            status = "failed"
            break
    save("sync-last", f"{int(time.time())}\n")
    if not remote:
        log("not-virtual" if status == 204 else "hello-failed", hello=status)
        return
    # `cli=0`: no gh, glab or API from here on; an older server's silence allows them.
    CLI["on"] = (answer.get("cli") or "1").strip() != "0"
    save("sync-cli", ("1" if CLI["on"] else "0") + "\n")
    try:
        if VERSION < int(answer.get("min_version") or 0):
            log("upgrade", hello=200)
            return
        limit = max(1, min(int(answer.get("max") or 2000), 10000))
    except ValueError:
        log("hello-failed", hello=200)
        return
    SALT = (answer.get("salt") or "").strip().lower()
    if not re.fullmatch(r"[0-9a-f]{16,128}", SALT):
        log("hello-failed", hello=200)
        return
    run_id = answer["run"].strip()
    domains = {d.strip().lower() for d in (answer.get("domains") or "").split(",") if d.strip()}
    text = answer.get("text") == "1"
    since = (answer.get("backfill_since" if BACKFILL else "first_since") or "").strip()
    since = since if re.fullmatch(r"\d{4}-\d{2}-\d{2}", since) else ""
    if BACKFILL and not since:
        log("no-backfill", hello=200)          # an older server
        return
    host, path = key.split("/", 1)
    me = norm(own_email) if own_email else None
    login = own_login(host)

    def clear_email(email):
        """Clear only the developer's own address or an own domain's."""
        value = norm(email)
        domain = value.rsplit("@", 1)[-1] if "@" in value else ""
        return value if value and (value == me or domain in domains) else ""

    def clear_login(value):
        return value.strip(SPACE) if login and value and norm(value) == norm(login) else ""

    # 5. Fetch; a failure sends what the clone has.
    git("fetch", remote, "--no-tags", "--quiet", timeout=600)

    # 6. Commits past the saved tips; a failed read (None, not "") sends nothing.
    refs = git("for-each-ref", "--format=%(objectname)", f"refs/remotes/{remote}/")
    if refs is None:
        log("history-failed", hello=200)
        return
    tips = [line.split()[0] for line in refs.splitlines() if line.strip()]
    tips = list(dict.fromkeys(tips + PUSHED))
    batch = run(["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
                stdin="\n".join(tips + (read("sync-tips") or "").split()).encode())
    if batch is None:
        log("history-failed", hello=200)
        return
    commits_known = {line.split()[0] for line in batch.splitlines()
                     if line.endswith(" commit")}
    tips = [t for t in tips if t in commits_known]
    saved = [t for t in (read("sync-tips") or "").split()
             if SHA.fullmatch(t) and t in commits_known]
    cut = [] if FULL or BACKFILL else saved
    window_since = since if BACKFILL or ((first or not saved) and not FULL) else ""
    rangeargs = list(tips)
    if cut:
        rangeargs += ["--not", *cut]
    if window_since:
        rangeargs.insert(0, f"--since={window_since}")
    partial = config(f"remote.{remote}.promisor") == "true" \
        or bool(config("extensions.partialclone"))
    shallow = set((read_shallow() or "").split())
    lines_of = {}
    groups = []
    if tips:
        # --no-show-signature: else `log.showSignature` mixes in gpg's lines.
        log_args = ["log", "--no-show-signature", "--no-merges", "--reverse",
                    "--format=%x00%H%x09%aI%x09%ae"]
        out = git(*log_args, *([] if partial else ["--numstat"]), *rangeargs, "--",
                  timeout=1800)
        written = None
        if out is not None and text:
            written = git("log", "--no-show-signature", "-z", "--no-merges", "--format=%H%n%B",
                          *rangeargs, "--", timeout=1800)
        if out is None or (text and written is None):
            log("history-failed", hello=200)
            return
        messages = {}
        for chunk in (written or "").split("\0"):
            sha, _, body = chunk.lstrip("\n").partition("\n")
            if SHA.fullmatch(sha):
                # One more: the server marks it `truncated`.
                messages[sha] = body.rstrip("\n")[:MESSAGE_CHARS + 1]
        for chunk in out.split("\0")[1:]:
            head, *stats = chunk.split("\n")
            sha, _, rest = head.partition("\t")
            authored, _, email = rest.partition("\t")
            if not SHA.fullmatch(sha) or not authored:
                continue
            added = deleted = 0
            for stat in stats:
                parts = stat.split("\t", 2)
                if len(parts) == 3:
                    added += int(parts[0]) if parts[0].isdigit() else 0
                    deleted += int(parts[1]) if parts[1].isdigit() else 0
            sizes = ("", "") if partial or sha in shallow else (str(added), str(deleted))
            email = email.strip(SPACE)
            group = ["\t".join(("C", sha, authored, *sizes, hashed("e", email),
                                clear_email(email)))]
            if text and sha in messages:
                group.append("\t".join(("M", sha, b64(messages[sha]))))
            groups.append((group, None))
            lines_of[sha] = authored
        counts["commits"] = len(lines_of)

    # 6a, 6b. Branch fingerprints; PRs the default branch names. Git only.
    branch = asked.get("branch") or ""
    default_tip = (git("rev-parse", "--verify", "--quiet",
                       f"refs/remotes/{remote}/{branch}^{{commit}}") or "").strip() \
        if branch else ""
    if SHA.fullmatch(default_tip):
        done = set(saved) if not FULL else set()
        if not partial and not shallow:
            groups += branch_groups(remote, branch, default_tip, PUSHED, done)
        history = history_groups(default_tip, cut, window_since,
                                 host, path, branch, text, partial or bool(shallow),
                                 clear_email)
        if history is None:
            log("history-failed", hello=200)
            return
        groups += history
        counts["history"] = len(history)

    # 6c. Release tags; a failed read sends the rest.
    tags_kept = None
    if SHA.fullmatch(default_tip):
        found = tag_groups(remote, default_tip,
                           since if (BACKFILL or read("sync-tags") is None) and not FULL
                           else "")
        if found is None:
            NOTES["note"] = "tags-failed"
        else:
            tag_lines, tags_kept = found
            groups += tag_lines
            counts["tags"] = len(tag_lines)

    # 7. Pull requests since the window, oldest first; only with `cli`.
    window_file = "sync-backfill-window" if BACKFILL else "sync-window"
    window = (read(window_file) or "").strip() or None
    start = None if FULL else (window or since or None)
    limit_pages = BACKFILL_PAGES if BACKFILL else PAGES
    pages = []
    PAGING["done"] = True
    if not CLI["on"]:
        pass
    elif host == "github.com" and shutil.which("gh"):
        PAGING["done"] = False
        pages = github_pages(f"{host}/{path}", start, text, limit_pages)
        for rows, after in zip(pages, PAGING["after"]):
            for index, pr in enumerate(rows):
                last = index == len(rows) - 1
                groups.append((github_lines(pr, text, clear_login), after if last else None))
    elif host == "gitlab.com" and shutil.which("glab") and shutil.which("jq"):
        PAGING["done"] = False
        pages = gitlab_pages(path, start, text, limit_pages)
        for rows, after in zip(pages, PAGING["after"]):
            for index, mr in enumerate(rows):
                last = index == len(rows) - 1
                groups.append((gitlab_lines(path, mr, text, clear_login), after if last else None))
    counts["prs"] = sum(len(rows) for rows in pages)

    # 8. Send in parts.
    parts = deque(pack(groups, limit))
    if not parts:
        parts.append(Part())
    requests = rehellos = 0
    while parts:
        part = parts.popleft()
        body = "".join(line + "\n" for group, _ in part for line in group).encode("utf-8")
        last = not parts
        requests += 1
        if requests > MAX_REQUESTS:
            log("too-many", hello=200)
            return
        status, reply = post(f"/caliber/sync/activity?run={urllib.parse.quote(run_id)}"
                             f"&last={1 if last else 0}", body,
                             "text/tab-separated-values; charset=utf-8")
        reason = reply.strip().split()[0] if reply.strip() else ""
        if status == 200:
            counts["parts"] += 1
            found = re.search(r"skipped=(\d+)", reply)
            counts["skipped"] += int(found.group(1)) if found else 0
            for _, window_after in part:
                if window_after:
                    save(window_file, window_after + "\n")
            continue
        if status == 409 and reason == "run-expired" and rehellos < 3:
            rehellos += 1
            again = hello(remote, key)
            if again:
                run_id = again["run"].strip()
                parts.appendleft(part)
                continue
        if status == 413 and not getattr(part, "halved", False) and len(part_lines(part)) > 1:
            first_half, second_half = halves(part)
            parts.appendleft(second_half)
            parts.appendleft(first_half)
            continue
        log("refused", hello=200, status=status, reason=re.sub(r"[^a-z-]", "", reason)[:20])
        return
    # Only now: the next run's start.
    save("sync-tips", "".join(t + "\n" for t in tips))
    if tags_kept is not None:
        save("sync-tags", "".join(f"{name}\t{obj}\n" for name, obj in sorted(tags_kept.items())))
    if BACKFILL:
        if PAGING["done"] and tags_kept is not None:
            save("sync-backfill", since + "\n")
            try:
                os.remove(where("sync-backfill-window"))
            except OSError:
                pass
        else:
            NOTES["note"] = "backfill-partial"   # the next --backfill goes on
    log("ok", hello=200, status=200)


def read_shallow():
    path = os.environ.get("CALIBER_SYNC_SHALLOW") or ""
    try:
        with open(path, encoding="ascii", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


#: 6a: branches a run; commits a branch (more: no `B` line).
BRANCHES, BRANCH_COMMITS = 100, 250


def fingerprint(base, tip):
    """Patch-id of base..tip or "", in a diff form the clone's settings can't change."""
    diff = run(["git", "diff", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames",
                "--no-relative", "--full-index", "--src-prefix=a/", "--dst-prefix=b/",
                "--diff-algorithm=default", "--indent-heuristic", "--unified=3",
                "--inter-hunk-context=0", base, tip, "--"], timeout=600, raw=True)
    if not diff:
        return ""
    found = (run(["git", "patch-id", "--stable"], stdin=diff, timeout=600) or "").split()
    return found[0] if found and SHA.fullmatch(found[0]) else ""


def branch_groups(remote, branch, default_tip, pushed, done):
    """6a. `B` lines of unmerged branches; saved tips left out."""
    refs = git("for-each-ref", "--format=%(refname)%09%(objectname)", f"refs/remotes/{remote}/")
    skip = (f"refs/remotes/{remote}/{branch}", f"refs/remotes/{remote}/HEAD")
    tips = [sha.strip() for name, _, sha in (line.partition("\t")
                                             for line in (refs or "").splitlines())
            if name not in skip]
    groups, seen, examined = [], set(), 0
    for tip in [*pushed, *tips]:
        if not SHA.fullmatch(tip) or tip in seen or tip in done:
            continue
        seen.add(tip)
        if git("merge-base", "--is-ancestor", tip, default_tip) is not None:
            continue
        examined += 1
        if examined > BRANCHES:
            break
        base = (git("merge-base", default_tip, tip) or "").strip()
        if not SHA.fullmatch(base):
            continue
        shas = [s for s in (git("rev-list", "--no-merges", f"--max-count={BRANCH_COMMITS + 1}",
                                f"{base}..{tip}", "--") or "").split() if SHA.fullmatch(s)]
        if not shas or len(shas) > BRANCH_COMMITS:
            continue
        mark = fingerprint(base, tip)
        if mark:
            groups.append(([f"B\t{mark}\t{sha}" for sha in shas], None))
            counts["branches"] += 1
    return groups


def body_line(message):
    _, _, body = message.partition("\n\n")
    return next((line.strip() for line in body.splitlines() if line.strip()), "")


def named_pull_request(host, path, parents, message):
    """(number, title, head ref) of a PR named in the default form, else None."""
    first = message.split("\n", 1)[0]
    if host == "github.com":
        found = re.match(r"Merge pull request #(\d{1,10}) from (\S+)", first)
        if found and len(parents) == 2:
            head = found.group(2)
            return found.group(1), body_line(message), head.split("/", 1)[1] if "/" in head \
                else head
        found = re.search(r" \(#(\d{1,10})\)$", first)
        if found and len(parents) == 1:
            return found.group(1), first[:found.start()], ""
    elif host == "gitlab.com" and len(parents) in (1, 2):
        for found in re.finditer(r"^See merge request (\S+)!(\d{1,10})$", message, re.M):
            if found.group(1).lower() == path.lower():
                paragraphs = [p for p in re.split(r"\n[ \t]*\n", message.strip("\n")) if p.strip()]
                title = paragraphs[1].split("\n", 1)[0].strip() if len(paragraphs) > 1 else ""
                head = re.match(r"Merge branch '([^']+)' into ", first)
                return found.group(2), title, head.group(1) if head else ""
    elif host == "bitbucket.org" and len(parents) in (1, 2):
        found = re.match(r"Merged in (\S+) \(pull request #(\d{1,10})\)", first)
        if found:
            return found.group(2), body_line(message), found.group(1)
    return None


def earliest(dates):
    moments = []
    for value in dates:
        try:
            moments.append((datetime.fromisoformat(value.replace("Z", "+00:00")), value))
        except ValueError:
            continue
    return min(moments)[1] if moments else ""


def history_groups(default_tip, saved, since, host, path, branch, text, sizeless, clear_email):
    """6b. `H`, `S`, `T` lines of first-parent commits naming a PR; None when unread."""
    args = ["log", "--no-show-signature", "--first-parent",
            "--format=%x1e%H%x00%P%x00%aI%x00%cI%x00%ae%x00%B"]
    if since:
        args.append(f"--since={since}")
    args.append(default_tip)
    if saved:
        args += ["--not", *saved]
    out = git(*args, "--", timeout=1800)
    if out is None:
        return None
    groups, numbers = [], set()
    for record in out.split("\x1e")[1:]:
        fields = record.split("\0", 5)
        if len(fields) != 6:
            continue
        sha, parents, authored, committed, email, message = fields
        parents = parents.split()
        if not SHA.fullmatch(sha) or not parents:
            continue
        found = named_pull_request(host, path, parents, message.rstrip("\n"))
        if not found or int(found[0]) < 1 or str(int(found[0])) in numbers:
            continue                   # newest first: a number's last merge
        number, title, head_ref = str(int(found[0])), found[1], found[2]
        numbers.add(number)
        first_parent, merge, head, brought = parents[0], sha, "", []
        if len(parents) == 2:
            head = parents[1]
            listed = git("log", "--no-show-signature", "--no-merges", "--format=%H%x09%aI",
                         f"{first_parent}..{head}", "--") or ""
            brought = [(s, a) for s, _, a in (line.partition("\t")
                                              for line in listed.splitlines())
                       if SHA.fullmatch(s)]
            authored = earliest(a for _, a in brought) or authored
            if brought:                # else the merge's own author
                email = (git("log", "--no-show-signature", "-1", "--format=%ae", head, "--")
                         or "").strip() or email
            base = (git("merge-base", first_parent, head) or "").strip()
            mark = fingerprint(base, head) if SHA.fullmatch(base) and not sizeless else ""
            if host == "gitlab.com":
                # GitLab's squash: one commit, one parent.
                rows = (git("rev-list", "--parents", f"{first_parent}..{head}", "--")
                        or "").splitlines()
                if len(rows) == 1 and len(rows[0].split()) == 2:
                    merge = rows[0].split()[0]
        else:
            mark = "" if sizeless else fingerprint(first_parent, sha)
        added = deleted = ""
        if not sizeless:
            stats = git("diff", "--no-color", "--no-ext-diff", "--numstat", first_parent, sha,
                        "--")
            if stats is not None:
                rows = [row.split("\t", 2) for row in stats.splitlines()]
                added = str(sum(int(r[0]) for r in rows if len(r) == 3 and r[0].isdigit()))
                deleted = str(sum(int(r[1]) for r in rows if len(r) == 3 and r[1].isdigit()))
        email = email.strip(SPACE)
        group = ["\t".join(("H", number, committed, authored, added, deleted, field(branch),
                            head, merge, hashed("e", email), clear_email(email), mark))]
        group += [f"S\t{number}\t{s}" for s, _ in brought]
        if text:
            group.append("\t".join(("T", number, b64(title), "", field(head_ref),
                                    field(branch))))
        groups.append((group, None))
    groups.reverse()                   # oldest first
    return groups


#: 6c: a release tag's name, as `local_wire.release_tag`.
VERSION_TAG = re.compile(r"[vV]?[0-9]+(?:\.[0-9]+)+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?"
                         r"(?:\+[0-9A-Za-z.-]+)?")
#: 6c: tags examined a run; refspecs a fetch.
TAGS, TAG_FETCH = 5000, 100


def tagged_dates(objects):
    """Tagger dates ("" without a tagger); missing objects left out."""
    out = run(["git", "cat-file", "--batch"], stdin="".join(o + "\n" for o in objects).encode(),
              timeout=600, raw=True) or b""
    found, at = {}, 0
    while at < len(out):
        end = out.find(b"\n", at)
        if end < 0:
            break
        head = out[at:end].decode("ascii", "replace").split()
        at = end + 1
        if len(head) != 3 or not head[2].isdigit():
            continue                   # `<sha> missing`
        size = int(head[2])
        body, at = out[at:at + size], at + size + 1
        if head[1] != "tag":
            continue
        header = body.split(b"\n\n", 1)[0].decode("utf-8", "replace")
        tagger = re.search(r"^tagger .* ([0-9]+) ([+-])([0-9]{2})([0-9]{2})$", header, re.M)
        if tagger is None:
            found[head[0]] = ""
            continue
        offset = (int(tagger.group(3)) * 60 + int(tagger.group(4))) * \
            (-1 if tagger.group(2) == "-" else 1)
        try:
            found[head[0]] = datetime.fromtimestamp(
                int(tagger.group(1)), timezone(timedelta(minutes=offset))).isoformat()
        except (OverflowError, OSError, ValueError):
            found[head[0]] = ""
    return found


def tag_groups(remote, default_tip, since):
    """6c. (`G` lines, tags to save) or None; no tag ref fetched, an unsent tag not saved."""
    listed = run(["git", "ls-remote", "--tags", remote], timeout=120)
    if listed is None:
        return None
    objects, peeled = {}, {}
    for line in listed.splitlines():
        sha, _, ref = line.strip().partition("\t")
        if not SHA.fullmatch(sha) or not ref.startswith("refs/tags/"):
            continue
        name = ref[len("refs/tags/"):]
        if name.endswith("^{}"):
            peeled[name[:-3]] = sha
        elif VERSION_TAG.fullmatch(name) and len(name) <= 255:
            objects[name] = sha
    saved = dict(line.split("\t", 1) for line in (read("sync-tags") or "").splitlines()
                 if "\t" in line)
    kept = {name: obj for name, obj in objects.items() if saved.get(name) == obj}
    new = sorted(name for name in objects
                 if FULL or BACKFILL or saved.get(name) != objects[name])
    if len(new) > TAGS:
        # The rest: the next regular run; never a full run or backfill.
        NOTES["tags"] = "truncated"
        new = new[:TAGS]
    commit_of = {name: peeled.get(name, objects[name]) for name in new}
    batch = run(["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
                stdin="".join(c + "\n" for c in set(commit_of.values())).encode()) or ""
    present = {line.split()[0] for line in batch.splitlines() if line.endswith(" commit")}
    dates = run(["git", "log", "--no-walk=unsorted", "--no-show-signature",
                 "--format=%H%x09%cI", "--stdin"],
                stdin="".join(c + "\n" for c in present).encode()) if present else ""
    committed = dict(line.split("\t", 1) for line in (dates or "").splitlines() if "\t" in line)
    held = {}
    for commit in set(committed):
        held[commit] = git("merge-base", "--is-ancestor", commit, default_tip) is not None
    new = [name for name in new if held.get(commit_of[name])]
    annotated = [objects[name] for name in new if name in peeled]
    tagged = tagged_dates(annotated) if annotated else {}
    missing = [name for name in new if name in peeled and objects[name] not in tagged]
    for start in range(0, len(missing), TAG_FETCH):
        refspecs = [f"refs/tags/{name}" for name in missing[start:start + TAG_FETCH]]
        if git("fetch", remote, "--no-tags", "--quiet", "--no-write-fetch-head", *refspecs,
               timeout=600) is None:
            git("fetch", remote, "--no-tags", "--quiet", *refspecs, timeout=600)
    if missing:
        tagged.update(tagged_dates([objects[name] for name in missing]))
    groups = []
    for name in new:
        obj = objects[name]
        if name in peeled and obj not in tagged:
            continue                   # not fetched yet
        at = tagged.get(obj, "") if name in peeled else ""
        commit_at = committed[commit_of[name]]
        kept[name] = obj
        if since and (at or commit_at)[:10] < since:
            continue                   # before the window
        groups.append((["\t".join(("G", name, commit_of[name], at, commit_at))], None))
    return groups, kept


class Part(list):
    halved = False


def part_lines(part):
    return [line for group, _ in part for line in group]


def history_marker(group):
    """`H <n> -` heads each later piece of a history PR, so its lines stay with it."""
    fields = group[0].split("\t") if group else []
    return f"H\t{fields[1]}\t-" if len(fields) > 2 and fields[0] == "H" else None


def halves(part):
    if len(part) > 1:
        cut = len(part) // 2
        pieces = Part(part[:cut]), Part(part[cut:])
    else:
        (group, window_after), = part
        cut = len(group) // 2
        marker = history_marker(group)
        rest = ([marker] if marker else []) + group[cut:]
        pieces = Part([(group[:cut], None)]), Part([(rest, window_after)])
    for piece in pieces:
        piece.halved = True
    return pieces


def pack(groups, limit):
    """Groups whole into parts; one too large alone is cut by lines."""
    parts, current, size, lines = [], Part(), 0, 0
    for group, window_after in groups:
        weight = sum(len(line.encode("utf-8")) + 1 for line in group)
        if current and (len(group) > limit or weight > PART_BYTES
                        or lines + len(group) > limit or size + weight > PART_BYTES):
            parts.append(current)
            current, size, lines = Part(), 0, 0
        if len(group) > limit or weight > PART_BYTES:
            piece, piece_size = [], 0
            marker = history_marker(group)
            for line in group:
                line_size = len(line.encode("utf-8")) + 1
                if piece and (len(piece) >= limit or piece_size + line_size > PART_BYTES):
                    parts.append(Part([(piece, None)]))
                    piece = [marker] if marker else []
                    piece_size = len(marker) + 1 if marker else 0
                piece.append(line)
                piece_size += line_size
            parts.append(Part([(piece, window_after)]))
            continue
        current.append((group, window_after))
        size += weight
        lines += len(group)
    if current:
        parts.append(current)
    return parts


GITHUB_FIELDS = ("number,state,createdAt,updatedAt,mergedAt,closedAt,additions,deletions,"
                 "baseRefName,headRefName,headRefOid,mergeCommit,labels,commits,author")
TEXT_FIELDS = ",title,body,files,changedFiles"
#: `__typename` tells an app from a person.
REVIEWS_QUERY = ("p{n}: pullRequest(number: {n}) {{ "
                 "reviews(first: 100) {{ nodes {{ author {{ __typename login }} submittedAt }} }} "
                 "comments(first: 100) {{ nodes {{ author {{ __typename login }} createdAt }} }} }}")  # noqa: E501


def github_reviews(repository, rows):
    """{} when GraphQL does not answer."""
    if not rows:
        return {}
    owner, _, name = repository.split("/", 1)[1].partition("/")
    query = ("query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { "
             + " ".join(REVIEWS_QUERY.format(n=r["number"]) for r in rows) + " } }")
    out = run(["gh", "api", "graphql", "--hostname", "github.com", "-f", "query=" + query,
               "-f", "owner=" + owner, "-f", "name=" + name], timeout=300)
    try:
        found = json.loads(out)["data"]["repository"] if out else None
    except (ValueError, KeyError, TypeError):
        found = None
    result = {}
    for r in rows:
        pr = found.get(f"p{r['number']}") if isinstance(found, dict) else None
        if isinstance(pr, dict):
            result[r["number"]] = {kind: ((pr.get(kind) or {}).get("nodes") or [])
                                   for kind in ("reviews", "comments")}
    return result


def next_start(start, last):
    """`last` (inclusive), or a second later when the whole page is at `start` (no loop)."""
    if last != start:
        return last
    try:
        moment = datetime.fromisoformat(last.replace("Z", "+00:00"))
    except ValueError:
        return last
    return (moment.astimezone(timezone.utc) + timedelta(seconds=1)).strftime(
        "%Y-%m-%dT%H:%M:%SZ")


def github_pages(repository, start, text, limit=PAGES):
    pages = []
    PAGING["after"] = []
    for _ in range(limit):
        query = ("" if start is None else f"updated:>={start} ") + "sort:updated-asc"
        out = run(["gh", "pr", "list", "-R", repository, "--state", "all", "--limit", str(PAGE),
                   "--search", query, "--json", GITHUB_FIELDS + (TEXT_FIELDS if text else "")],
                  timeout=300)
        try:
            rows = json.loads(out) if out else None
        except ValueError:
            rows = None
        if not isinstance(rows, list):
            break
        rows = sorted((r for r in rows
                       if isinstance(r, dict) and isinstance(r.get("number"), int)),
                      key=lambda r: r.get("updatedAt") or "")
        reviews = github_reviews(repository, rows)
        if rows and not reviews:
            # Reviews unread: the window must not pass this page.
            break
        for r in rows:
            r.update(reviews.get(r["number"], {}))
        pages.append(rows)
        if len(rows) < PAGE or not rows[-1].get("updatedAt"):
            PAGING["after"].append((rows[-1].get("updatedAt") or None) if rows else None)
            PAGING["done"] = True
            break
        start = next_start(start, rows[-1]["updatedAt"])
        PAGING["after"].append(start)
    return pages


def login_of(who):
    return (who or {}).get("login") or "" if isinstance(who, dict) else ""


def is_bot(who):
    who = who if isinstance(who, dict) else {}
    return who.get("__typename") == "Bot" or who.get("is_bot") is True \
        or login_of(who).startswith("app/")


def merged_at(oid, fallback):
    if oid and SHA.fullmatch(oid):
        found = (git("log", "--no-show-signature", "-1", "--format=%cI", oid, "--")
                 or "").strip()
        if found:
            return found
    return fallback


def github_lines(pr, text, clear_login):
    number = str(pr["number"])
    state = {"OPEN": "open", "MERGED": "merged", "CLOSED": "closed"}.get(pr.get("state"), "")
    commits = [c for c in pr.get("commits") or [] if isinstance(c, dict)]
    dates = sorted(when(c.get("authoredDate")) for c in commits if when(c.get("authoredDate")))
    merge = (pr.get("mergeCommit") or {}).get("oid") or "" if isinstance(
        pr.get("mergeCommit"), dict) else ""
    author = login_of(pr.get("author")) or "ghost"
    lines = ["\t".join(("P", number, state, when(pr.get("createdAt")), when(pr.get("mergedAt")),
                        when(pr.get("closedAt")), dates[0] if dates else "",
                        merged_at(merge, when(pr.get("mergedAt"))),
                        count(pr.get("additions")), count(pr.get("deletions")),
                        field(pr.get("baseRefName")), pr.get("headRefOid") or "", merge,
                        hashed("l", author), clear_login(author)))]
    for label in pr.get("labels") or []:
        name = label.get("name") if isinstance(label, dict) else None
        if isinstance(name, str) and name.strip():
            lines.append("\t".join(("L", number, field(name))))
    for commit in commits:
        oid = commit.get("oid") or ""
        if SHA.fullmatch(oid):
            lines.append("\t".join(("S", number, oid)))
    if text:
        lines.append("\t".join(("T", number, b64(pr.get("title") or ""), b64(pr.get("body") or ""),
                                field(pr.get("headRefName")), field(pr.get("baseRefName")))))
        files = [f.get("path") for f in pr.get("files") or [] if isinstance(f, dict)
                 and isinstance(f.get("path"), str)]
        lines += ["\t".join(("F", number, b64(p))) for p in files]
        changed = pr.get("changedFiles")
        if len(files) >= 100 or (isinstance(changed, int) and changed > len(files)):
            lines.append("\t".join(("F", number, "-")))
    # Reviews: time and hashed author, never text; not the author's or `[bot]`s.
    me = norm(author)
    reviewed = len(lines)
    for kind, at in (("reviews", "submittedAt"), ("comments", "createdAt")):
        for item in pr.get(kind) or []:
            if not isinstance(item, dict):
                continue
            who = login_of(item.get("author"))
            moment = when(item.get(at))
            if not who or not moment or who.endswith("[bot]") or norm(who) == me:
                continue
            lines.append("\t".join(("R", number, moment, hashed("l", who), clear_login(who),
                                    "1" if is_bot(item.get("author")) else "0")))
    # Read, none by others: a marker of no first review.
    if len(lines) == reviewed and "reviews" in pr and "comments" in pr:
        lines.append("\t".join(("R", number, "-")))
    return lines


#: What `jq` keeps of GitLab's merge requests.
GITLAB_JQ = ("[.[] | {iid, state, created_at, merged_at, closed_at, updated_at, target_branch, "
             "source_branch, sha, merge_commit_sha, squash_commit_sha, labels, "
             "author: (.author.username // \"\"), title, description}]")


def gitlab(path, endpoint, program):
    out = run(["glab", "api", "--hostname", "gitlab.com",
               f"projects/{urllib.parse.quote(path, safe='')}/{endpoint}"], timeout=300)
    if out is None:
        return None
    kept = run(["jq", "-c", program], stdin=out.encode(), timeout=120)
    try:
        return json.loads(kept) if kept else None
    except ValueError:
        return None


def gitlab_pages(path, start, text, limit=PAGES):
    pages = []
    PAGING["after"] = []
    for _ in range(limit):
        query = "merge_requests?state=all&scope=all&order_by=updated_at&sort=asc&per_page=100"
        if start is not None:
            query += "&updated_after=" + urllib.parse.quote(start, safe="")
        rows = gitlab(path, query, GITLAB_JQ)
        if not isinstance(rows, list):
            break
        rows = sorted((r for r in rows
                       if isinstance(r, dict) and isinstance(r.get("iid"), int)),
                      key=lambda r: r.get("updated_at") or "")
        pages.append(rows)
        if len(rows) < PAGE or not rows[-1].get("updated_at"):
            PAGING["after"].append((rows[-1].get("updated_at") or None) if rows else None)
            PAGING["done"] = True
            break
        start = next_start(start, rows[-1]["updated_at"])
        PAGING["after"].append(start)
    return pages


def gitlab_lines(path, mr, text, clear_login):
    number = str(mr["iid"])
    state = {"opened": "open", "locked": "open", "merged": "merged",
             "closed": "closed"}.get(mr.get("state"), "")
    merge = mr.get("merge_commit_sha") or mr.get("squash_commit_sha") or ""
    author = mr.get("author") or "ghost"
    # Not in the listing: line counts, commits.
    lines = ["\t".join(("P", number, state, when(mr.get("created_at")), when(mr.get("merged_at")),
                        when(mr.get("closed_at")), "", merged_at(merge, when(mr.get("merged_at"))),
                        "", "", field(mr.get("target_branch")), mr.get("sha") or "", merge,
                        hashed("l", author), clear_login(author)))]
    for label in mr.get("labels") or []:
        if isinstance(label, str) and label.strip():
            lines.append("\t".join(("L", number, field(label))))
    if text:
        lines.append("\t".join(("T", number, b64(mr.get("title") or ""),
                                b64(mr.get("description") or ""), field(mr.get("source_branch")),
                                field(mr.get("target_branch")))))
        if FULL:                       # a call per merge request
            changes = gitlab(path, f"merge_requests/{number}/changes",
                             "{paths: [.changes[]?.new_path], overflow: (.overflow // false)}")
            if isinstance(changes, dict):
                lines += ["\t".join(("F", number, b64(p))) for p in changes.get("paths") or []
                          if isinstance(p, str)]
                if changes.get("overflow"):
                    lines.append("\t".join(("F", number, "-")))
    return lines


try:
    main()
except Exception as exc:  # noqa: BLE001 -- one log line, never the text of what failed
    log("error", kind=type(exc).__name__)
finally:
    release()
