#!/usr/bin/env bash
# Run the whole set in waves: pull the wave's images, run its sessions (JOBS in parallel),
# evaluate them with the official harness while the images are still local, free the images.
# Idempotent: a row whose result exists is skipped, so an interrupted run resumes.
# Retry policy (the one applied in the published run): every row gets ONE completed session.
# Pass 2 reruns only rows that never got a real attempt - killed by the account rate limit
# ("You've hit your session limit"), or with no result and no patch at all. A session that
# ended at the turn cap or by the wall clock keeps its patch and is evaluated as is.
# run-instance.sh skips a row whose .patch exists, so a rerun must clear json+patch+transcript
# and the row's eval directory (the harness skips instances that already have an output).
#   ./orchestrate.sh [WAVE=12] [JOBS=3]
set -uo pipefail
K="$(cd "$(dirname "$0")" && pwd)"; SET="$K/sweb731.jsonl"; WAVE="${1:-12}"; JOBS="${2:-3}"
TOTAL=$(wc -l < "$SET"); LOG="$K/orchestrate.log"
tag() { sed -n "${1}p" "$SET" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["dockerhub_tag"])'; }
iid() { sed -n "${1}p" "$SET" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["instance_id"])'; }
done_ok() {   # 0 = keep as is; 1 = (re)run
  local id="$1" f="$K/preds/$1.json" p="$K/preds/$1.patch"
  if [ -s "$f" ]; then
    python3 -c "import json,sys; d=json.load(open('$f')); sys.exit(1 if d.get('is_error') and 'session limit' in str(d.get('result','')) else 0)" 2>/dev/null
  else
    [ -s "$p" ]   # patch without json = killed mid-run, kept
  fi
}
clear_row() { rm -f "$K/preds/$1.json" "$K/preds/$1.patch" "$K/preds/$1.transcript.jsonl"; rm -rf "$K/eval/$1"; }
for pass in 1 2; do            # pass 2 retries rows killed by the rate limit (see policy above)
  i=1
  while [ "$i" -le "$TOTAL" ]; do
    END=$(( i + WAVE - 1 )); [ "$END" -gt "$TOTAL" ] && END=$TOTAL
    PEND=0; for n in $(seq "$i" "$END"); do done_ok "$(iid "$n")" || PEND=1; done
    if [ "$PEND" = "1" ]; then
      for n in $(seq "$i" "$END"); do T=$(tag "$n"); docker image inspect "jefzda/sweap-images:$T" >/dev/null 2>&1 || timeout 5400 docker pull "jefzda/sweap-images:$T" >>"$LOG" 2>&1; done
      for n in $(seq "$i" "$END"); do
        done_ok "$(iid "$n")" && continue
        while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
        ( id=$(iid "$n"); clear_row "$id"; timeout 3000 bash "$K/run-instance.sh" "$n" >>"$LOG" 2>&1 ) &
      done
      wait
      bash "$K/eval-incr.sh" >>"$K/eval.log" 2>&1 || echo "eval failed for wave $i-$END" >>"$LOG"
      for n in $(seq "$i" "$END"); do docker rmi -f "jefzda/sweap-images:$(tag "$n")" >/dev/null 2>&1; done
      docker image prune -f >/dev/null 2>&1
    fi
    echo "PASS $pass WAVE $i-$END $(date -u)" >>"$LOG"; i=$(( END + 1 ))
  done
done
bash "$K/eval-incr.sh" >>"$K/eval.log" 2>&1; echo "DONE $(date -u)" >>"$LOG"
