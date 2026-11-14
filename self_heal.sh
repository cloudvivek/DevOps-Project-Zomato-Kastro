
#!/bin/bash

set -Eeuo pipefail

MODEL="${OLLAMA_MODEL:-qwen2.5-coder:3b}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/generate}"
BUILD_LOG="${1:-build_output.log}"

echo "=========================================="
echo "       JENKINS OLLAMA AI ANALYZER"
echo "=========================================="

echo "Build Number : ${BUILD_NUMBER:-unknown}"
echo "Model        : $MODEL"
echo "Build Log    : $BUILD_LOG"

# 1. Check dependencies
for CMD in curl jq; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: Required command missing: $CMD"
        exit 1
    fi
done

# 2. Verify build log
if [ ! -s "$BUILD_LOG" ]; then
    echo "ERROR: Build log missing or empty."
    exit 1
fi

echo ""
echo "Build log verified."

# 3. Verify Ollama connectivity
OLLAMA_HOST="${OLLAMA_URL%/api/generate}"

echo ""
echo "Checking Ollama connectivity..."

curl --fail --silent --show-error \
    --connect-timeout 15 \
    "$OLLAMA_HOST/api/tags" >/dev/null

echo "Ollama API is reachable."

# 4. Read Jenkins failure log
ERROR_LOG=$(tail -n 100 "$BUILD_LOG")

echo ""
echo "Captured Jenkins error:"
echo "------------------------------------------"
echo "$ERROR_LOG"
echo "------------------------------------------"

# 5. Prepare AI prompt
PROMPT=$(cat <<EOF
You are an expert DevOps and Jenkins engineer.

Analyze this failed Jenkins pipeline.

Please provide:

1. Exact error message.
2. Root cause of the failure.
3. File or command responsible.
4. Recommended correction.
5. Corrected command or code example.

Do not create GitHub branches.
Do not create pull requests.
Do not modify files.

JENKINS BUILD LOG:

$ERROR_LOG
EOF
)

# 6. Build Ollama request
PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "$PROMPT" \
    '{
        model: $model,
        prompt: $prompt,
        stream: false,
        options: {
            temperature: 0.1,
            num_ctx: 8192
        }
    }')

# 7. Send log to Ollama
echo ""
echo "Sending Jenkins failure log to Ollama..."
echo "Waiting for AI response..."

RESPONSE=$(curl \
    --fail \
    --silent \
    --show-error \
    --connect-timeout 15 \
    --max-time 900 \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$OLLAMA_URL")

# 8. Extract AI response
AI_RESPONSE=$(jq -r '.response // empty' <<< "$RESPONSE")

if [ -z "$AI_RESPONSE" ]; then
    echo "ERROR: Ollama returned an empty response."
    exit 1
fi

# 9. Display AI analysis
echo ""
echo "=========================================="
echo "          OLLAMA AI ANALYSIS"
echo "=========================================="

echo "$AI_RESPONSE"

# 10. Save analysis
REPORT_DIR="$WORKSPACE/ai-reports"
mkdir -p "$REPORT_DIR"

REPORT_FILE="$REPORT_DIR/ai-analysis-${BUILD_NUMBER:-manual}.md"

{
    echo "# Jenkins AI Failure Analysis"
    echo ""
    echo "**Build:** ${BUILD_NUMBER:-unknown}"
    echo ""
    echo "**Model:** $MODEL"
    echo ""
    echo "## AI Analysis"
    echo ""
    echo "$AI_RESPONSE"
} > "$REPORT_FILE"

echo ""
echo "AI report saved: $REPORT_FILE"
echo ""
echo "=========================================="
echo "OLLAMA ANALYSIS COMPLETED SUCCESSFULLY"
echo "=========================================="
