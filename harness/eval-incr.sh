#!/bin/bash
# Official SWE-bench Pro evaluation (Scale AI harness, MIT, vendored in scale-harness/), incremental:
# the harness skips instances whose output already exists, so this only evaluates new predictions.
set -eu
K="$(cd "$(dirname "$0")" && pwd)"
python3 "$K/build-patches.py"
cd "$K/scale-harness"
python3 swe_bench_pro_eval.py --raw_sample_path "$K/sweb731.jsonl" --patch_path "$K/patches.json" \
  --output_dir "$K/eval" --dockerhub_username jefzda --scripts_dir run_scripts --use_local_docker --num_workers 3
