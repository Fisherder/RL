#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVAL_SCRIPT="$ROOT_DIR/script/eval_autopenbench.py"
AGGREGATE_SCRIPT="$ROOT_DIR/script/aggregate_autopenbench_results.py"

MODEL_PATH="${AUTOPENBENCH_MODEL_PATH:-$ROOT_DIR/models/purpcode-pentest-r1-stage2-pentest-r1-stage2-offline/global_step_38/actor/huggingface}"
AUTOPENBENCH_ROOT="${AUTOPENBENCH_ROOT:-/home/ubuntu/RL/auto-pen-bench-official}"
DTYPE="${AUTOPENBENCH_DTYPE:-bfloat16}"
DEVICE_MAP="${AUTOPENBENCH_DEVICE_MAP:-auto}"
TEMPERATURE="${AUTOPENBENCH_TEMPERATURE:-0.0}"
MAX_INPUT_TOKENS="${AUTOPENBENCH_MAX_INPUT_TOKENS:-4096}"
MAX_NEW_TOKENS="${AUTOPENBENCH_MAX_NEW_TOKENS:-1536}"
SUMMARY_MAX_NEW_TOKENS="${AUTOPENBENCH_SUMMARY_MAX_NEW_TOKENS:-192}"
OUTPUT_ROOT="${AUTOPENBENCH_OUTPUT_ROOT:-$ROOT_DIR/eval_results/auto_pen_bench_full_$(date +%Y%m%d_%H%M%S)}"
CONDA_ENV="${AUTOPENBENCH_CONDA_ENV:-purpcode}"
export AUTOPENBENCH_DOCKER_RETRIES="${AUTOPENBENCH_DOCKER_RETRIES:-8}"
export AUTOPENBENCH_DOCKER_RETRY_WAIT_SECONDS="${AUTOPENBENCH_DOCKER_RETRY_WAIT_SECONDS:-20}"

mkdir -p "$OUTPUT_ROOT"

DEFAULT_EPOCHS="${AUTOPENBENCH_EPOCHS_DEFAULT:-30}"

SCENARIOS=(
  "in-vitro access_control 5 $DEFAULT_EPOCHS"
  "in-vitro cryptography 4 $DEFAULT_EPOCHS"
  "in-vitro web_security 7 $DEFAULT_EPOCHS"
  "in-vitro network_security 6 $DEFAULT_EPOCHS"
  "real-world cve 11 $DEFAULT_EPOCHS"
)

echo "Using MODEL_PATH=$MODEL_PATH"
echo "Using AUTOPENBENCH_ROOT=$AUTOPENBENCH_ROOT"
echo "Using OUTPUT_ROOT=$OUTPUT_ROOT"

PREBUILD_KALI="${AUTOPENBENCH_PREBUILD_KALI:-1}"
if [ "$PREBUILD_KALI" = "1" ]; then
  echo "Prebuilding AutoPenBench kali_master image..."
  (
    cd "$AUTOPENBENCH_ROOT"
    docker-compose -f benchmark/machines/docker-compose.yml build kali_master
  )
fi

SCENARIO_INDEX=0
for scenario in "${SCENARIOS[@]}"; do
  SCENARIO_INDEX=$((SCENARIO_INDEX + 1))
  read -r LEVEL CATEGORY ITERATIONS EPOCHS <<<"$scenario"
  SCENARIO_NAME="$(printf "%02d_%s_%s" "$SCENARIO_INDEX" "$LEVEL" "$CATEGORY")"
  SCENARIO_DIR="$OUTPUT_ROOT/$SCENARIO_NAME"
  LOG_PATH="$SCENARIO_DIR/run.log"
  mkdir -p "$SCENARIO_DIR"

  echo "=== Running $SCENARIO_NAME ==="
  set +e
  conda run -n "$CONDA_ENV" python "$EVAL_SCRIPT" \
    --model-path "$MODEL_PATH" \
    --autopenbench-root "$AUTOPENBENCH_ROOT" \
    --level "$LEVEL" \
    --category "$CATEGORY" \
    --iterations "$ITERATIONS" \
    --epochs "$EPOCHS" \
    --dtype "$DTYPE" \
    --device-map "$DEVICE_MAP" \
    --temperature "$TEMPERATURE" \
    --max-input-tokens "$MAX_INPUT_TOKENS" \
    --max-new-tokens "$MAX_NEW_TOKENS" \
    --summary-max-new-tokens "$SUMMARY_MAX_NEW_TOKENS" \
    --output-dir "$SCENARIO_DIR" \
    >"$LOG_PATH" 2>&1
  EXIT_CODE=$?
  set -e

  printf "%s\n" "$EXIT_CODE" > "$SCENARIO_DIR/exit_code.txt"
  echo "Scenario $SCENARIO_NAME exit_code=$EXIT_CODE"
done

conda run -n "$CONDA_ENV" python "$AGGREGATE_SCRIPT" --root-dir "$OUTPUT_ROOT" \
  > "$OUTPUT_ROOT/aggregate_summary_stdout.txt"

echo "Aggregate summary: $OUTPUT_ROOT/aggregate_summary.json"
