#!/bin/bash
# Horizon layer bootstrap inside the task container. FAIL-OPEN at every
# step: any failure leaves a perfectly stock claude-code agent behind.
set +e
WD="$PWD"
# SAFE DEFAULTS FIRST: claude runs with --mcp-config .mcp.json, so this
# file must exist even when the layer cannot (fail-open at flag level).
[ -f "$WD/.mcp.json" ] || printf '{ "mcpServers": {} }\n' > "$WD/.mcp.json"
mkdir -p "$WD/.claude"
[ -f "$WD/.claude/settings.json" ] || printf '{}\n' > "$WD/.claude/settings.json"
B=/tmp/vexp-core
chmod +x "$B" 2>/dev/null
if ! "$B" --version >/dev/null 2>&1; then
  # glibc binary dead: musl twin (Alpine images - teleport, webclients,
  # tutanota). Same engine, same version, different libc.
  if [ -x /tmp/vexp-core-musl ] && /tmp/vexp-core-musl --version >/dev/null 2>&1; then
    B=/tmp/vexp-core-musl
  else
    echo "VEXP_BINARY_INCOMPATIBLE" > /tmp/vexp-layer-status
    exit 0
  fi
fi
# git powers ONLY the verify baseline (git status diff). Orientation
# (run_pipeline/get_skeleton, the MCP tools) needs just the index, so a
# missing git must NOT disable the whole layer - it only skips the
# baseline commit. This was the third engagement bug: NO_GIT killed
# everything, including orientation which does not need git at all.
if command -v git >/dev/null 2>&1; then
  if ! git -C "$WD" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$WD" init -q &&
    git -C "$WD" config user.email horizon@vexp.dev &&
    git -C "$WD" config user.name horizon &&
    git -C "$WD" add -A >/dev/null 2>&1
    git -C "$WD" commit -qm baseline >/dev/null 2>&1
    touch /tmp/vexp-git-created
  fi
fi
# Index SYNCHRONOUSLY then start the daemon and WAIT for the socket:
# the MCP stdio server claude launches needs a serving daemon at connect
# time, or it registers zero tools and claude drops it (mcp: []). Task
# repos are small (seconds to index); the earlier background warmup
# raced and left the layer silently absent on every trial.
# Bench license (when bundled): full engine - no node cap, no daily
# gate, horizon entitled. Installed to $HOME/.vexp where the engine
# looks first. Without it the layer still works, FREE-capped.
if [ -f /tmp/bench-license.jwt ]; then
  mkdir -p "$HOME/.vexp"
  cp /tmp/bench-license.jwt "$HOME/.vexp/license.jwt" 2>/dev/null
fi
"$B" index "$WD" >/tmp/vexp-index.log 2>&1
nohup "$B" daemon --workspace "$WD" >/tmp/vexp-daemon.log 2>&1 &
for i in $(seq 1 45); do [ -S "$WD/.vexp/daemon.sock" ] && break; sleep 1; done
# Benchmark serves 100%: the holdback court is a field instrument.
grep -q "^holdback_pct" "$WD/.vexp/vexp.toml" 2>/dev/null || printf 'holdback_pct = 0\n' >> "$WD/.vexp/vexp.toml"
# Full Horizon anti-drift: STRICT scope gate (entitled by the bench
# license; zero false positives across ~70 runs after the infra/stem
# fixes). SWE-Pro scoring punishes broken pass_to_pass tests - exactly
# what out-of-scope edits cause; the one-shot "revert or justify"
# challenge is the mechanism that protects them.
grep -q "^scope_gate" "$WD/.vexp/vexp.toml" 2>/dev/null || printf 'scope_gate = "strict"\n' >> "$WD/.vexp/vexp.toml"
mkdir -p "$WD/.claude/hooks"
printf '#!/bin/bash\n[ -x %s ] || exit 0\n%s prompt-hint 2>/dev/null\nexit 0\n' "$B" "$B" > "$WD/.claude/hooks/vexp-hint.sh"
printf '#!/bin/bash\n[ -x %s ] || exit 0\n%s stop-gate 2>/dev/null\nexit 0\n' "$B" "$B" > "$WD/.claude/hooks/vexp-verify.sh"
chmod +x "$WD/.claude/hooks/"*.sh
printf '#!/bin/bash\n# vexp guard: nudge Grep/Glob to run_pipeline when the daemon serves.\n[ -S "$CLAUDE_PROJECT_DIR/.vexp/daemon.sock" ] || exit 0\nprintf %%s '"'"'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"vexp daemon is running. AGENT INSTRUCTION: call run_pipeline (task-anchored on real identifiers) instead of Grep/Glob for code discovery; use expand_vexp_ref for bodies. Filesystem reads outside code discovery are fine via Bash."}}'"'"'\nexit 0\n' > "$WD/.claude/hooks/vexp-guard.sh"
chmod +x "$WD/.claude/hooks/vexp-guard.sh"
cat > "$WD/.claude/settings.json" <<'SETEOF'
{
  "enableAllProjectMcpServers": true,
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/vexp-hint.sh\"", "timeout": 5 } ] }
    ],
    "PreToolUse": [
      { "matcher": "Grep|Glob", "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/vexp-guard.sh\"", "timeout": 5 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/vexp-verify.sh\"", "timeout": 15 } ] }
    ]
  }
}
SETEOF
cat > "$WD/.mcp.json" <<MCPEOF
{ "mcpServers": { "vexp": { "command": "$B", "args": ["mcp"] } } }
MCPEOF
echo "LAYER_ACTIVE sock=$([ -S "$WD/.vexp/daemon.sock" ] && echo yes || echo no)" > /tmp/vexp-layer-status
cat > "$WD/CLAUDE.md" <<'MDEOF'
## vexp - local code context (this machine only)
- `run_pipeline({ "task": "..." })` - one call returns ranked pivot files
  with line ranges and blast radius when the task does NOT name the
  files/symbols to touch. If it does, skip it.
- `verify_done` - call once BEFORE declaring a multi-file task complete:
  returns mechanically broken references (imports of removed names, parse
  errors) and untouched dependents of changed files, with file:line.
- Work methodically: confirm the root cause before expanding your search,
  and stop reading once it is confirmed.
MDEOF
exit 0
