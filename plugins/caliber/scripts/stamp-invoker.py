#!/usr/bin/env python3
# Caliber invoker stamp. caliber-hooks-version: 36
# A Claude Code PreToolUse hook on Caliber's submit_audit and verify_spec: it writes `invoker`
# (who made the call, as the harness knows it) into the tool's input, replacing whatever the
# agent put there (brief assure-independent-checks-stamp). Its matcher takes the two tool names
# under any server name, since a client names the server; the input then has to be Caliber's
# (`CALIBER_SHAPE`: what the two tools require to record a result), so a tool of another server
# with the same name is left as it is. Run with `python3 -I`; standard
# library only. On anything it cannot read it prints nothing and the call goes through
# unchanged. A subagent's call carries `agent_id`; the push hook's own run
# (`CALIBER_PUSH_HOOK_RUN=1`, set by check-on-push.sh) is stamped `caliber-push-hook` without
# one.
# Auto mode reviews a call as the model wrote it and refuses one whose input a hook then
# changed, and it refuses the model writing the stamp itself. So in auto mode alone the hook
# also allows the stamped call (`permissionDecision: allow`): auto mode does not review it, and
# what runs is what the hook wrote. Only these two calls, which record a check's result, and only
# under Caliber's own server names (`CALIBER_SERVERS`).
import json
import os
import re
import sys

TOOLS = re.compile(r"mcp__(.*)__(submit_audit|verify_spec)")
MAX = 128
PUSH_HOOK = "caliber-push-hook"
# The mode whose review refuses a call a hook rewrote: there the hook allows the call it stamps,
# but only under a name Caliber's own server goes by (the plugin's, setup's `.mcp.json`, the
# claude.ai connector). A server renamed by hand is still stamped, and left to auto mode.
AUTO = "auto"
CALIBER_SERVERS = {"plugin_caliber_caliber", "caliber", "claude_ai_Caliber"}
# The fields Caliber's tool needs to record what the agent judged: `submit_audit` requires
# `kind`, `head_sha` and the `findings` list; `verify_spec` records only with `key`, the
# `verdicts` list and the `criteria_sha` its first step returned (without them it returns the
# rules and records nothing, so no stamp is needed).
CALIBER_SHAPE = {"submit_audit": (("kind", str), ("head_sha", str), ("findings", list)),
                 "verify_spec": (("key", str), ("verdicts", list), ("criteria_sha", str))}


def caliber_call(tool, tool_input):
    return all(isinstance(tool_input.get(field), kind) for field, kind in CALIBER_SHAPE[tool])


def clean(value):
    return value.strip()[:MAX] if isinstance(value, str) and value.strip() else None


def main():
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input")
    match = TOOLS.fullmatch(str(data.get("tool_name", "")))
    if not isinstance(tool_input, dict) or not match or not caliber_call(match[2], tool_input):
        return
    version = clean(os.environ.get("CLAUDE_CODE_VERSION"))
    stamp = {"harness": clean(f"claude-code/{version}" if version else "claude-code"),
             "agent_id": clean(data.get("agent_id")),
             "agent_type": clean(data.get("agent_type")),
             "session_id": clean(data.get("session_id"))}
    if os.environ.get("CALIBER_PUSH_HOOK_RUN") == "1":
        stamp.update(agent_id=None, agent_type=PUSH_HOOK)
    invoker = {key: value for key, value in stamp.items() if value}
    output = {"updatedInput": {**tool_input, "invoker": invoker}}
    if data.get("permission_mode") == AUTO and match[1] in CALIBER_SERVERS:
        output = {"permissionDecision": "allow",
                  "permissionDecisionReason": "Caliber's stamp hook wrote who ran this check",
                  **output}
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", **output}}))


try:
    main()
except Exception:
    pass
sys.exit(0)
