#!/usr/bin/env python3
# Caliber invoker stamp. caliber-hooks-version: 20
# A Claude Code PreToolUse hook on Caliber's submit_audit and verify_spec: it writes `invoker`
# (who made the call, as the harness knows it) into the tool's input, replacing whatever the
# agent put there (brief assure-independent-checks-stamp). Run with `python3 -I`; standard
# library only. It never blocks a call and asks for no permission: on anything it cannot read
# it prints nothing and the call goes through unchanged. A subagent's call carries `agent_id`;
# the push hook's own run (`CALIBER_PUSH_HOOK_RUN=1`, set by check-on-push.sh) is stamped
# `caliber-push-hook` without one.
import json
import os
import re
import sys

TOOLS = re.compile(r"mcp__.*__(submit_audit|verify_spec)")
MAX = 128
PUSH_HOOK = "caliber-push-hook"


def clean(value):
    return value.strip()[:MAX] if isinstance(value, str) and value.strip() else None


def main():
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict) or not TOOLS.fullmatch(str(data.get("tool_name", ""))):
        return
    version = clean(os.environ.get("CLAUDE_CODE_VERSION"))
    stamp = {"harness": clean(f"claude-code/{version}" if version else "claude-code"),
             "agent_id": clean(data.get("agent_id")),
             "agent_type": clean(data.get("agent_type")),
             "session_id": clean(data.get("session_id"))}
    if os.environ.get("CALIBER_PUSH_HOOK_RUN") == "1":
        stamp.update(agent_id=None, agent_type=PUSH_HOOK)
    invoker = {key: value for key, value in stamp.items() if value}
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": {**tool_input, "invoker": invoker}}}))


try:
    main()
except Exception:
    pass
sys.exit(0)
