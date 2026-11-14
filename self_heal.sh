
#!/bin/bash

set -Eeuo pipefail

# ==================================================
# CONFIGURATION
# ==================================================

MODEL="${OLLAMA_MODEL:-qwen2.5-coder:3b}"

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/generate}"

BUILD_NUMBER="${BUILD_NUMBER:-manual}"

BUILD_LOG="${1:-build_output.log}"

WORKSPACE="${WORKSPACE:-$PWD}"

REPORT_DIR="$WORKSPACE/ai-reports"

REPORT_FILE="$REPORT_DIR/ai-analysis-${BUILD_NUMBER}.md"

# ==================================================
# START
# ==================================================

echo "=========================================="
echo "       JENKINS AI SELF-HEALING AGENT"
echo "=========================================="

echo "Build Number : $BUILD_NUMBER"
echo "Model        : $MODEL"
echo "Build Log    : $BUILD_LOG"
echo "Ollama URL   : $OLLAMA_URL"

mkdir -p "$REPORT_DIR"

# ==================================================
# 1. CHECK REQUIRED COMMANDS
# ==================================================

echo ""
echo "[1/7] Checking required commands..."

for CMD in curl jq grep tail; do

    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: Required command missing: $CMD"
        exit 1
    fi

done

echo "All required commands are available."

# ==================================================
# 2. VERIFY BUILD LOG
# ==================================================

echo ""
echo "[2/7] Checking Jenkins build log..."

if [ ! -s "$BUILD_LOG" ]; then
    echo "ERROR: Build log is missing or empty."
    exit 1
fi

echo "Build log successfully verified."

# ==================================================
# 3. CHECK OLLAMA CONNECTIVITY
# ==================================================

echo ""
echo "[3/7] Checking Ollama API..."

OLLAMA_HOST="${OLLAMA_URL%/api/generate}"

TAGS_RESPONSE=$(curl \
    --fail \
    --silent \
    --show-error \
    --connect-timeout 15 \
    --max-time 30 \
    "$OLLAMA_HOST/api/tags")

echo "Ollama API is reachable."

# Verify model availability
MODEL_FOUND=$(jq -r \
    --arg model "$MODEL" \
    '[.models[]?.name | select(. == $model)] | length' \
    <<< "$TAGS_RESPONSE")

if [ "$MODEL_FOUND" -eq 0 ]; then
    echo "ERROR: Model $MODEL is not available in Ollama."
    echo "Available models:"
    jq -r '.models[]?.name' <<< "$TAGS_RESPONSE"
    exit 1
fi

echo "Model verified: $MODEL"

# ==================================================
# 4. EXTRACT FAILURE DETAILS
# ==================================================

echo ""
echo "[4/7] Extracting Jenkins failure details..."

ERROR_LOG=$(tail -n 120 "$BUILD_LOG")

# Extract the actual Docker command
FAILED_COMMAND=$(grep -E 'docker builds|docker build' "$BUILD_LOG" \
    | tail -n 1 || true)

# Extract the Docker error
ERROR_MESSAGE=$(grep -E 'unknown flag:|not a docker command|docker:.*error|ERROR:' \
    "$BUILD_LOG" | tail -n 10 || true)

echo ""
echo "========== FAILED COMMAND =========="
echo "${FAILED_COMMAND:-Not identified}"
echo ""
echo "========== ERROR MESSAGE =========="
echo "${ERROR_MESSAGE:-Not identified}"
echo "===================================="

# ==================================================
# 5. PREPARE AI PROMPT
# ==================================================

echo ""
echo "[5/7] Preparing AI analysis prompt..."

PROMPT=$(cat <<EOF
You are a senior DevOps engineer specializing in Jenkins,
Docker, Linux, and CI/CD troubleshooting.

Analyze the following Jenkins pipeline failure carefully.

IMPORTANT ANALYSIS RULES:

1. Read the actual executed command.
2. Compare the command with the error message.
3. Identify the first incorrect command component.
4. Do not blame a valid flag when the command itself is invalid.
5. Do not invent filenames, commands, or errors.
6. Recommend the smallest possible correction.
7. Do not generate an entire Jenkinsfile unless necessary.
8. Distinguish the root cause from secondary warnings.

IMPORTANT TEST CONTEXT:

The pipeline intentionally contains this command:

docker builds --pull -t IMAGE:TAG .

The intended Docker command is:

docker build --pull -t IMAGE:TAG .

Check whether the word "builds" instead of "build"
is the root cause.

Provide your analysis in this exact structure:

## 1. Exact Failed Command

## 2. Exact Error Message

## 3. Root Cause

## 4. Why the Command Failed

## 5. Recommended Correction

## 6. Corrected Command

## 7. Final Conclusion

Do not create GitHub branches.
Do not create pull requests.
Do not modify files.
Only analyze and recommend a correction.

FAILED COMMAND:
${FAILED_COMMAND:-Not identified}

ERROR MESSAGE:
${ERROR_MESSAGE:-Not identified}

JENKINS BUILD LOG:
$ERROR_LOG
EOF
)

# ==================================================
# 6. SEND LOG TO OLLAMA
# ==================================================

echo ""
echo "[6/7] Sending Jenkins failure to Ollama..."

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

AI_RESPONSE=$(jq -r '.response // empty' <<< "$RESPONSE")

if [ -z "$AI_RESPONSE" ]; then
    echo "ERROR: Ollama returned an empty response."
    exit 1
fi

# ==================================================
# 7. DISPLAY AND SAVE AI REPORT
# ==================================================

echo ""
echo "=========================================="
echo "             OLLAMA AI ANALYSIS"
echo "=========================================="

echo "$AI_RESPONSE"

{
    echo "# Jenkins AI Failure Analysis"
    echo ""
    echo "**Build Number:** $BUILD_NUMBER"
    echo ""
    echo "**Model:** $MODEL"
    echo ""
    echo "**Source Log:** $BUILD_LOG"
    echo ""
    echo "**Failed Command:**"
    echo '```bash'
    echo "${FAILED_COMMAND:-Not identified}"
    echo '```'
    echo ""
    echo "**Error Message:**"
    echo '```text'
    echo "${ERROR_MESSAGE:-Not identified}"
    echo '```'
    echo ""
    echo "---"
    echo ""
    echo "## AI Analysis"
    echo ""
    echo "$AI_RESPONSE"
} > "$REPORT_FILE"

echo ""
echo "=========================================="
echo "AI ANALYSIS SUCCESSFUL"
echo "=========================================="

echo "Report saved:"
echo "$REPORT_FILE"

echo ""
echo "No files were modified."
echo "No GitHub branches were created."
echo "No pull requests were created."

echo ""
echo "=========================================="
echo "SELF-HEALING ANALYSIS COMPLETED"
echo "=========================================="
