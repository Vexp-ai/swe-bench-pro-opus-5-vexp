#!/usr/bin/env bash
# One SWE-bench Pro session: Claude Code (headless) + vexp 3.1.1 on one instance.
#
#   ./run-instance.sh <row>            row = 1-based line in sweb731.jsonl
#   DRY_RUN=1 ./run-instance.sh <row>  set the container up, do not call the model
#
# Environment: CLAUDE_CODE_OAUTH_TOKEN (your Anthropic account), Docker, python3.
# Layout: this directory holds sweb731.jsonl, horizon-setup.sh, the vexp binary
# (vexp-core-3.1.1-linux-x64-musl) and a vexp licence file named bench-license.jwt
# (see README: the free tier caps an index at 2,000 nodes).
set -u
N="$1"; K="$(cd "$(dirname "$0")" && pwd)"; SET="$K/sweb731.jsonl"
MODEL=claude-opus-5
OUT="$K/preds"; LOGD="$K/logs"; mkdir -p "$OUT" "$LOGD"
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || { echo "CLAUDE_CODE_OAUTH_TOKEN not set"; exit 3; }
ROW=$(sed -n "${N}p" "$SET"); [ -z "$ROW" ] && { echo "no row $N"; exit 0; }
IID=$(echo "$ROW" | python3 -c "import json,sys; print(json.load(sys.stdin)['instance_id'])")
TAG=$(echo "$ROW" | python3 -c "import json,sys; print(json.load(sys.stdin)['dockerhub_tag'])")
LOG="$LOGD/$N.log"
[ -f "$OUT/$IID.patch" ] && { echo "[$N] $IID already done"; exit 0; }
CN="swebpro-$N"
docker rm -f "$CN" >/dev/null 2>&1
docker run -d --name "$CN" --entrypoint sleep "jefzda/sweap-images:$TAG" infinity >/dev/null 2>&1 \
  || { echo "[$N] RUN FAIL"; exit 1; }

# --- Claude Code 2.1.220 inside the task image: prebuilt binary, else npm.
docker cp "$K/claude.gz" "$CN":/tmp/claude.gz 2>/dev/null || true
timeout 180 docker exec "$CN" sh -c "[ -f /tmp/claude.gz ] && gunzip -f /tmp/claude.gz && chmod +x /tmp/claude && mkdir -p /usr/local/bin && mv /tmp/claude /usr/local/bin/claude" >>"$LOG" 2>&1
CLAUDE_BIN=/usr/local/bin/claude
if ! timeout 60 docker exec "$CN" sh -c "$CLAUDE_BIN --version" >/dev/null 2>&1; then
  timeout 30 docker exec "$CN" sh -c "rm -f /usr/local/bin/claude" >>"$LOG" 2>&1
  if ! timeout 60 docker exec "$CN" sh -c "command -v npm" >/dev/null 2>&1; then
    timeout 600 docker exec "$CN" sh -c "apk add --no-cache nodejs npm" >>"$LOG" 2>&1 \
      || timeout 600 docker exec "$CN" sh -c "apt-get update -qq && apt-get install -y -qq nodejs npm" >>"$LOG" 2>&1 || true
  fi
  timeout 900 docker exec "$CN" sh -c "npm install -g @anthropic-ai/claude-code@2.1.220" >>"$LOG" 2>&1
  CLAUDE_BIN=claude
  timeout 60 docker exec "$CN" sh -c "claude --version" >>"$LOG" 2>&1 \
    || { echo "[$N] CLAUDE UNAVAILABLE"; docker rm -f "$CN" >/dev/null 2>&1; exit 1; }
fi

# --- an unprivileged user owning /app (Claude Code refuses --dangerously-skip-permissions as root).
timeout 60 docker exec "$CN" sh -c "id agent >/dev/null 2>&1 || useradd -m -s /bin/bash agent 2>/dev/null || adduser -D -s /bin/sh agent 2>/dev/null" >>"$LOG" 2>&1
AGENT_USER=$(timeout 60 docker exec "$CN" sh -c "id agent >/dev/null 2>&1 && echo agent || (getent passwd 1000 | cut -d: -f1)" 2>/dev/null | tr -d '\r\n ')
[ -z "$AGENT_USER" ] && AGENT_USER=root
AGENT_HOME=$(timeout 60 docker exec "$CN" sh -c "getent passwd $AGENT_USER | cut -d: -f6" 2>/dev/null | tr -d '\r\n ')
[ -z "$AGENT_HOME" ] && AGENT_HOME=/root
timeout 600 docker exec "$CN" sh -c "chown -R $AGENT_USER /app 2>/dev/null; true" >>"$LOG" 2>&1
if ! timeout 30 docker exec -u "$AGENT_USER" "$CN" sh -c "touch /app/.wt && rm -f /app/.wt" >>"$LOG" 2>&1; then
  AGENT_USER=root; AGENT_HOME=/root
fi
timeout 120 docker exec -u "$AGENT_USER" -e HOME="$AGENT_HOME" "$CN" sh -c "cd /app && git config --global --add safe.directory /app && git config --global user.email bench@vexp.dev && git config --global user.name bench && git add -A >/dev/null 2>&1; git commit -qm pre-agent-baseline >/dev/null 2>&1" >>"$LOG" 2>&1

# --- vexp: binary + in-container setup (index, daemon, hooks, CLAUDE.md, .mcp.json).
gzip -c "$K/vexp-core-3.1.1-linux-x64-musl" > /tmp/vexp-$N.gz
docker cp /tmp/vexp-$N.gz "$CN":/tmp/vexp-core.gz
docker cp /tmp/vexp-$N.gz "$CN":/tmp/vexp-core-musl.gz
docker cp "$K/horizon-setup.sh" "$CN":/tmp/horizon-setup.sh
docker cp "$K/bench-license.jwt" "$CN":/tmp/bench-license.jwt
timeout 120 docker exec "$CN" sh -c "gunzip -f /tmp/vexp-core.gz && gunzip -f /tmp/vexp-core-musl.gz && chmod +x /tmp/vexp-core /tmp/vexp-core-musl && chmod 644 /tmp/bench-license.jwt" >>"$LOG" 2>&1
timeout 900 docker exec -u "$AGENT_USER" -e HOME="$AGENT_HOME" "$CN" sh -c "cd /app && bash /tmp/horizon-setup.sh" >>"$LOG" 2>&1
MCPFLAGS="--setting-sources project --strict-mcp-config --mcp-config /app/.mcp.json"

# --- vexp 3.1.1 default configuration: the orientation seed on UserPromptSubmit only.
# horizon-setup.sh also registers a Stop gate and a Grep/Glob guard; the shipped 3.1.1
# default has both off, so they are removed here, exactly as in the measured run.
timeout 60 docker exec -u "$AGENT_USER" "$CN" sh -c 'python3 - <<QUIETEOF
import json,os
p="/app/.claude/settings.json"
d=json.load(open(p)) if os.path.exists(p) else {}
h=d.get("hooks",{})
h.pop("Stop",None)
h.pop("PostToolUse",None)
h["PreToolUse"]=[e for e in h.get("PreToolUse",[]) if "vexp-guard" not in json.dumps(e)]
if not h["PreToolUse"]: h.pop("PreToolUse")
d["hooks"]=h
json.dump(d,open(p,"w"),indent=2)
print("hooks left =", sorted(h))
QUIETEOF' >>"$LOG" 2>&1

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[$N] DRY RUN: container $CN is set up; inspect it, then: docker rm -f $CN"; exit 0
fi

# --- the task, verbatim, on stdin.
PROMPT=$(echo "$ROW" | python3 -c "
import json,sys
r=json.load(sys.stdin)
p='You are working in /app, a checkout of '+r['repo']+' at a fixed commit. Solve the issue below by editing files under /app. Keep changes minimal and focused; do not modify tests unless the issue requires it. Leave your changes in the working tree (no commit).\n\n<issue>\n'+r['problem_statement']+'\n</issue>\n'
if r.get('requirements'): p+='\n<requirements>\n'+r['requirements']+'\n</requirements>\n'
if r.get('interface'): p+='\n<interface>\n'+r['interface']+'\n</interface>\n'
print(p)")
S=$(date +%s)
printf '%s' "$PROMPT" | timeout 2400 docker exec -i -u "$AGENT_USER" -e CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" -e HOME="$AGENT_HOME" "$CN" sh -c \
  "cd /app && timeout 2100 env IS_SANDBOX=$([ "$AGENT_USER" = root ] && echo 1 || echo 0) $CLAUDE_BIN -p --model $MODEL --output-format json --max-turns 120 --dangerously-skip-permissions $MCPFLAGS" > "$OUT/$IID.json" 2>>"$LOG"
RC=$?; E=$(date +%s)

# --- collect: the diff (excluding vexp's own files), the transcript, the summary line.
timeout 120 docker exec -u "$AGENT_USER" -e HOME="$AGENT_HOME" "$CN" sh -c "cd /app && git add -A >/dev/null 2>&1 && git diff --cached -- . ':(exclude).vexp' ':(exclude).claude' ':(exclude)CLAUDE.md' ':(exclude).mcp.json' ':(exclude)*.log'" > "$OUT/$IID.patch" 2>>"$LOG"
timeout 60 docker exec -u "$AGENT_USER" "$CN" sh -c "cat $AGENT_HOME/.claude/projects/*/*.jsonl 2>/dev/null" > "$OUT/$IID.transcript.jsonl" 2>/dev/null
COST=$(python3 -c "import json;print(json.load(open('$OUT/$IID.json')).get('total_cost_usd','?'))" 2>/dev/null)
TURNS=$(python3 -c "import json;print(json.load(open('$OUT/$IID.json')).get('num_turns','?'))" 2>/dev/null)
docker rm -f "$CN" >/dev/null 2>&1; rm -f /tmp/vexp-$N.gz
echo "[$N] $IID rc=$RC patch=$(wc -c < "$OUT/$IID.patch")b cost=\$$COST turns=$TURNS wall=$((E-S))s"
