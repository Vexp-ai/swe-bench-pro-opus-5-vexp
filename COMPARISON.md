# Opus 5 + vexp 3.1.1 against the published Opus 5 and Fable 5 numbers

SWE-bench Pro, public set, 731 instances. One row is this repository's run; the other two are the figures
Anthropic published for its models, relayed and labelled "vendor-reported" by DataCamp on 2026-07-29
(<https://www.datacamp.com/it/blog/claude-opus-5-vs-claude-fable-5>). Prices are Anthropic's list
(<https://platform.claude.com/docs/en/about-claude/pricing>, read 2026-09-05).

| System | Resolved | Token price, in / out per Mtok | Source |
|---|---|---|---|
| **Claude Opus 5 + vexp 3.1.1** (Claude Code 2.1.220, this repository) | **81.7%** (597/731) | $5 / $25 | every session, patch and harness output in `results/` |
| Claude Fable 5 | 80.3% | $10 / $50 | Anthropic, vendor-reported |
| Claude Opus 5 | 79.2% | $5 / $25 | Anthropic, vendor-reported |

This run is a single pass over the 731 instances; its 95% Wilson interval is 78.7 – 84.3. Anthropic
publishes point estimates without intervals.

## Resolution

- An Opus 5 agent running with vexp lands **above both published figures**: 2.5 points above Anthropic's
  own Opus 5 number with the same model, 1.4 above Fable 5.
- The confidence interval of this run (78.7 – 84.3) contains both published points. Anthropic publishes
  point estimates without intervals; on 731 instances a 1–2 point gap is inside the noise of a single run
  of either system. The statistically defensible statement is **"level with Fable 5 at half the token
  price"**, not "beats Fable 5".
- **The three numbers do not come from the same scaffold.** Anthropic's figures come from its own harness;
  this run uses Claude Code 2.1.220 headless with a 120-turn cap and the official Scale AI evaluation
  harness. Scale AI's public leaderboard (<https://labs.scale.com/leaderboard/swe_bench_pro_public>)
  runs every model through the minimal mini-swe-agent scaffold, tops out at 61.5%, and lists neither
  Opus 5 nor Fable 5: the scaffold moves this benchmark by tens of points. This repository does not
  isolate vexp's own contribution, because no same-scaffold run without vexp is published here. What is
  published is everything needed to run one.

## Cost of this run

Anthropic does not publish what its SWE-bench Pro runs cost, and Scale's leaderboard carries no cost or
token column, so no per-task cost comparison is made here. What this run cost is exact. Token usage of
the 731 sessions (`summary/per-instance.json`, summed) at Anthropic's list prices for Claude Opus 5:

| Component | Tokens | List price | Cost |
|---|---|---|---|
| Base input | 35,689 | $5 / Mtok | $0.18 |
| Cache writes (1-hour) | 31,828,430 | $10 / Mtok | $318.28 |
| Cache reads | 1,054,236,113 | $0.50 / Mtok | $527.12 |
| Output | 10,419,759 | $25 / Mtok | $260.49 |
| **Total** | | | **$1,106.07 · $1.51 per task** |

Claude Code's own meter for the run, summed over the 731 result files, is $1,111.55 ($1.52 per task),
within 0.5% of the list-price recomputation. Ninety-seven percent of billed input is cache reads: an
agent loop replays its context every turn, and the model's per-token price sets the bill. On Anthropic's
list every Fable 5 component (base input, cache write, cache read, output) is twice the Opus 5 one.

## What vexp does inside the loop

vexp 3.1.1 runs entirely inside the task container. Before the first model turn it indexes the
repository and injects one orientation block on `UserPromptSubmit` (ranked entry points and blast
radius for the issue), exposes a 4-tool MCP catalog (`run_pipeline`, `get_skeleton`, `verify_done`,
and `expand_vexp_ref`) and writes the project `CLAUDE.md` in `harness/horizon-setup.sh`. Nothing leaves the
container. The orientation seed was injected in 624 of 731 sessions; in the other 107, all on the
largest repositories, it hit a 3-second client timeout and the session ran without it (see README,
"Known limitation"). Those sessions are included in the 597/731.

## How to check any number here

`summary/SUMMARY.txt` and `summary/per-instance.json` are recomputed from `results/` by the packaging
script; the resolution rule is the harness's own (every FAIL_TO_PASS and PASS_TO_PASS test passes).
To reproduce the run itself, see README, "Reproduce".
