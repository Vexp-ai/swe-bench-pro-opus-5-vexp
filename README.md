# Claude Opus 5 + vexp 3.1.1 on SWE-bench Pro

**81.7% resolved (597 of 731) at $1.52 per task.** That is above the figures Anthropic published for
both **Claude Fable 5 (80.3%)** and **Claude Opus 5 (79.2%)** on the same benchmark, at half of Fable 5's
token price. Full run of Claude Code (Opus 5) with [vexp](https://vexp.dev) 3.1.1 on the SWE-bench Pro
public set, every session published, everything needed to reproduce it in this repository.

| System | Resolved | Token price, in / out per Mtok | Source |
|---|---|---|---|
| **Claude Opus 5 + vexp 3.1.1** (Claude Code 2.1.220) | **81.7%** · 597/731 · 95% CI 78.7 – 84.3 | $5 / $25 | this repository |
| Claude Fable 5 | 80.3% | $10 / $50 | Anthropic, vendor-reported |
| Claude Opus 5 | 79.2% | $5 / $25 | Anthropic, vendor-reported |

**What vexp changes.** Same model as Anthropic's Opus 5 row, 2.5 points higher; 1.4 points above Fable 5
with tokens that cost half as much. vexp adds one orientation block before the first model turn, a
4-tool MCP catalog and a project `CLAUDE.md`; nothing leaves the task container.

**How to read the table** (details and arithmetic in [COMPARISON.md](COMPARISON.md)):
- The interval of this run, 78.7 – 84.3, contains both published points. What the numbers establish is
  "level with Fable 5 at half the token price"; the 1.4-point gap is inside single-run noise.
- The scaffolds differ: Anthropic's figures come from its own harness, this run from Claude Code with a
  120-turn cap. On Scale AI's public leaderboard, where every entry uses the minimal mini-swe-agent
  scaffold, the best score is 61.5% and neither Opus 5 nor Fable 5 is listed. This repository does not
  isolate vexp's own contribution: no same-scaffold run without vexp is published here.
- This run cost $1,111.55 in API usage as metered by Claude Code, $1.52 per task. Anthropic does not
  publish what its runs cost; the price column is Anthropic's list, on which every Fable 5 component is
  twice the Opus 5 one.

`summary/SUMMARY.txt` is computed from the files in this repository alone.

## Setup as measured
| | |
|---|---|
| Benchmark | SWE-bench Pro public set, 731 instances (`harness/sweb731.jsonl`; task images `jefzda/sweap-images:<tag>`) |
| Agent | Claude Code `2.1.220`, headless: `claude -p --model claude-opus-5 --output-format json --max-turns 120 --dangerously-skip-permissions --setting-sources project --strict-mcp-config --mcp-config /app/.mcp.json` |
| vexp | `vexp-core 3.1.1` (sha256 in `harness/`; the binary is the `-binary.tar.gz` release asset, same build as the 3.1.1 release; put it in `harness/` before running), default configuration: orientation seed on `UserPromptSubmit`, 4-tool MCP catalog, project `CLAUDE.md` written by `horizon-setup.sh`; stop gate and Grep/Glob guard off (see `run-instance.sh`) |
| Evaluation | Scale AI's official harness (`harness/scale-harness`, MIT, vendored as used): resolved iff every FAIL_TO_PASS and PASS_TO_PASS test passes |
| Prompt | the issue text verbatim, preceded by one fixed sentence - see `run-instance.sh` |

## Reproduce
```
cd harness
export CLAUDE_CODE_OAUTH_TOKEN=...      # your Anthropic account
cp <your-vexp-licence> bench-license.jwt # see below
./run-instance.sh 1                      # one instance -> preds/
./orchestrate.sh 12 3                    # everything, in waves of 12, 3 sessions in parallel
./eval-incr.sh                           # official evaluation -> eval/
```
`DRY_RUN=1 ./run-instance.sh 1` sets a container up without calling the model, so you can inspect exactly
what the agent saw (`/app/CLAUDE.md`, `/app/.mcp.json`, `/app/.claude/settings.json`).

**Licence.** vexp's free tier caps an index at 2,000 nodes. This run used a paid-tier licence with no cap;
on large repositories (ansible ~60k nodes, teleport) a free-tier index is a different, smaller index and
results will not match. Any vexp plan without a node cap reproduces the run.

## Results
`results/` (366 MB unpacked, 11,713 files) ships as the release asset `swebpro-vexp-3.1.1-results.tar.gz`
attached to this run's tag; untar it at the repository root to get the layout below. The vexp binary is the
release asset `swebpro-vexp-3.1.1-binary.tar.gz` (sha256 in `harness/`). `MANIFEST.sha256` covers both.

`results/preds/` per-session usage JSON, patch and full transcript; `results/eval/` per-instance harness
output; `results/logs/` session logs; `summary/per-instance.json` one row per session (cost, turns,
tokens, resolved, whether the orientation seed was injected).

**Headline: 597/731 resolved = 81.7% (Wilson 95% CI 78.7-84.3).** Cost and turns per instance are in
`summary/SUMMARY.txt`, recomputed from the files here.

The comparison with the published Opus 5 and Fable 5 figures, with the cost arithmetic and sources, is in
[COMPARISON.md](COMPARISON.md).

## One completed session per instance
Every instance has exactly one completed agent session in `results/preds/`. Nine sessions were killed by the
account rate limit (`429 You've hit your session limit`) before doing real work; they were rerun once, and the
killed attempts are kept as they were in `results/rate-limited-first-attempts/`. One session ended at the
120-turn cap with its patch in place; that patch was evaluated like any other. One session made no change
(empty patch: the agent judged the fix already present) and counts as not resolved. No instance was run to
completion twice and nothing was selected.

## Redaction
The only edit to any artifact: the runner's public IP, echoed into three transcripts by GitHub's
"API rate limit exceeded for <ip>" message, is replaced with `<runner-ip>`. Nothing else was touched.

## Known limitation in 3.1.1
On the largest repositories the orientation seed can hit a 3-second client timeout and the session runs
without it (`seed_injected: false`). Those sessions are included; nothing was filtered.

## Licence
Scripts, summaries and results in this repository: MIT (`LICENSE`). The vendored Scale AI evaluation
harness in `harness/scale-harness/` keeps its own MIT licence. The task set `harness/sweb731.jsonl` is
the SWE-bench Pro public set as distributed by Scale AI.
