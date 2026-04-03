#!/usr/bin/env bash
#
# run_bench.sh - CUA-Bench one-click benchmark runner
#
# Usage:
#   ./run_bench.sh                              # Use defaults
#   ./run_bench.sh --api-base <URL>             # Custom API endpoint
#   ./run_bench.sh --model <MODEL>              # Custom model name
#   ./run_bench.sh --dataset <DATASET_DIR>      # Custom dataset
#   ./run_bench.sh --parallel <N>               # Parallelism
#   ./run_bench.sh --skip-build                 # Skip Docker image rebuild
#
# Example:
#   ./run_bench.sh \
#     --api-base https://my-api.example.com/v1 \
#     --model openai/my-model \
#     --parallel 4
#
set -euo pipefail

# ============================================================
# Default Configuration (edit these or override via flags)
# ============================================================
API_BASE="${CUA_API_BASE:-https://ms-xgfhngph-100034032793-sw.gw.ap-zhongwei.ti.tencentcs.com/ms-xgfhngph/v1}"
MODEL="${CUA_MODEL:-openai//data/model}"
DATASET="${CUA_DATASET:-datasets/cua-bench-basic}"
AGENT="${CUA_AGENT:-cua-agent}"
PROVIDER_TYPE="${CUA_PROVIDER_TYPE:-native}"
MAX_PARALLEL="${CUA_MAX_PARALLEL:-4}"
OPENAI_API_KEY="${OPENAI_API_KEY:-dummy}"
SKIP_BUILD="${CUA_SKIP_BUILD:-false}"

# Colima resource settings
COLIMA_CPUS="${COLIMA_CPUS:-8}"
COLIMA_MEMORY="${COLIMA_MEMORY:-16}"

# ============================================================
# Parse CLI arguments
# ============================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --api-base)     API_BASE="$2";      shift 2 ;;
        --model)        MODEL="$2";         shift 2 ;;
        --dataset)      DATASET="$2";       shift 2 ;;
        --agent)        AGENT="$2";         shift 2 ;;
        --provider-type) PROVIDER_TYPE="$2"; shift 2 ;;
        --parallel)     MAX_PARALLEL="$2";  shift 2 ;;
        --api-key)      OPENAI_API_KEY="$2"; shift 2 ;;
        --skip-build)   SKIP_BUILD=true;    shift ;;
        --cpus)         COLIMA_CPUS="$2";   shift 2 ;;
        --memory)       COLIMA_MEMORY="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ============================================================
# Resolve project root (directory containing this script)
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================
# Helper functions
# ============================================================
info()  { echo -e "\033[36m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[92m[OK]\033[0m    $*"; }
err()   { echo -e "\033[91m[ERROR]\033[0m $*"; }
step()  { echo -e "\n\033[1m━━━ Step $1: $2 ━━━\033[0m"; }

# ============================================================
# Step 1: Check prerequisites
# ============================================================
step 1 "Checking prerequisites"

for cmd in docker colima cb; do
    if ! command -v "$cmd" &>/dev/null; then
        err "$cmd is not installed. Please install it first."
        exit 1
    fi
done
ok "All prerequisites found"

# ============================================================
# Step 2: Ensure Colima is running with enough resources
# ============================================================
step 2 "Ensuring Colima has enough resources (${COLIMA_CPUS} CPU / ${COLIMA_MEMORY}GB RAM)"

COLIMA_RUNNING=false
if colima status &>/dev/null; then
    COLIMA_RUNNING=true
    CURRENT_CPUS=$(colima list -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['cpus'])" 2>/dev/null || echo 0)
    CURRENT_MEM=$(colima list -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['memory'] // (1024*1024*1024))" 2>/dev/null || echo 0)

    if [[ "$CURRENT_CPUS" -lt "$COLIMA_CPUS" ]] || [[ "$CURRENT_MEM" -lt "$COLIMA_MEMORY" ]]; then
        info "Colima running with ${CURRENT_CPUS} CPU / ${CURRENT_MEM}GB RAM, need ${COLIMA_CPUS} CPU / ${COLIMA_MEMORY}GB RAM"
        info "Restarting Colima with more resources..."
        colima stop
        COLIMA_RUNNING=false
    else
        ok "Colima already running with sufficient resources (${CURRENT_CPUS} CPU / ${CURRENT_MEM}GB RAM)"
    fi
fi

if [[ "$COLIMA_RUNNING" == "false" ]]; then
    info "Starting Colima with ${COLIMA_CPUS} CPU / ${COLIMA_MEMORY}GB RAM..."
    colima start --cpu "$COLIMA_CPUS" --memory "$COLIMA_MEMORY"
    ok "Colima started"
fi

# ============================================================
# Step 3: Build Docker image
# ============================================================
step 3 "Building Docker image"

if [[ "$SKIP_BUILD" == "true" ]] && docker image inspect cua-bench:latest &>/dev/null; then
    ok "Skipping build (--skip-build flag set, image exists)"
else
    info "Building cua-bench:latest ..."
    docker build -t cua-bench:latest .
    ok "Docker image built"
fi

# ============================================================
# Step 4: Verify API endpoint is reachable
# ============================================================
step 4 "Verifying API endpoint"

info "Testing: $API_BASE"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 10 \
    -X POST "${API_BASE}/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -d '{"model":"'"${MODEL#openai/}"'","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' \
    2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "000" ]]; then
    err "Cannot reach API endpoint. Please check the URL and network connectivity."
    err "URL: $API_BASE"
    exit 1
elif [[ "$HTTP_CODE" == "503" ]]; then
    err "API endpoint returned 503 (Service Unavailable). The model service may be down."
    exit 1
elif [[ "$HTTP_CODE" =~ ^(200|400|401|422)$ ]]; then
    ok "API endpoint reachable (HTTP $HTTP_CODE)"
else
    info "API returned HTTP $HTTP_CODE - proceeding anyway"
fi

# ============================================================
# Step 5: Run benchmark
# ============================================================
step 5 "Running benchmark"

echo ""
info "Configuration:"
echo "  Dataset:      $DATASET"
echo "  Agent:        $AGENT"
echo "  Model:        $MODEL"
echo "  API Base:     $API_BASE"
echo "  Provider:     $PROVIDER_TYPE"
echo "  Parallelism:  $MAX_PARALLEL"
echo ""

export OPENAI_API_KEY
RUN_OUTPUT=$(cb run dataset "$DATASET" \
    --agent "$AGENT" \
    --model "$MODEL" \
    --api-base "$API_BASE" \
    --provider-type "$PROVIDER_TYPE" \
    --max-parallel "$MAX_PARALLEL" \
    2>&1)

echo "$RUN_OUTPUT"

# Extract run ID
RUN_ID=$(echo "$RUN_OUTPUT" | grep -oE '[a-f0-9]{8}' | head -1)

if [[ -z "$RUN_ID" ]]; then
    err "Failed to extract run ID from output"
    exit 1
fi

ok "Benchmark started with Run ID: $RUN_ID"

# ============================================================
# Step 6: Wait for completion
# ============================================================
step 6 "Waiting for benchmark to complete"

info "Monitoring progress (Ctrl+C to detach, run continues in background)..."
echo ""

while true; do
    sleep 30
    INFO_OUTPUT=$(cb run info "$RUN_ID" 2>&1)
    PROGRESS=$(echo "$INFO_OUTPUT" | grep "Progress:" | grep -oE '[0-9]+/[0-9]+')
    AVG_REWARD=$(echo "$INFO_OUTPUT" | grep "Avg Reward:" | grep -oE '[0-9]+\.[0-9]+')

    if [[ -n "$PROGRESS" ]]; then
        DONE=$(echo "$PROGRESS" | cut -d/ -f1)
        TOTAL=$(echo "$PROGRESS" | cut -d/ -f2)
        info "Progress: ${PROGRESS} | Avg Reward: ${AVG_REWARD:-N/A}"

        if [[ "$DONE" -eq "$TOTAL" ]]; then
            break
        fi
    fi
done

# ============================================================
# Step 7: Show final results
# ============================================================
step 7 "Final Results"

cb run info "$RUN_ID"

RESULT_DIR="$HOME/.local/share/cua-bench/runs/$RUN_ID"
echo ""
ok "Benchmark complete!"
echo ""
echo "  Run ID:     $RUN_ID"
echo "  Results:    $RESULT_DIR"
echo "  View:       cb run info $RUN_ID"
echo "  Traces:     cb trace grid $RUN_ID"
echo ""
