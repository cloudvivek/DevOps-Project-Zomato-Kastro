
#!/bin/bash

set -Eeuo pipefail

# ==========================================================
# JENKINS AI SELF-HEALING AGENT
# Ollama + Qwen2.5 Coder 3B + GitHub Pull Request
# ==========================================================

# ----------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------

BUILD_NUMBER="${BUILD_NUMBER:-manual}"
GIT_BRANCH="${GIT_BRANCH:-master}"

MODEL="${OLLAMA_MODEL:-qwen2.5-coder:3b}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/generate}"

BUILD_LOG="${1:-${WORKSPACE:-$PWD}/build_output.log}"

BRANCH="fix/auto-${BUILD_NUMBER}"

TEMP_FILE=""

# ----------------------------------------------------------
# LOGGING
# ----------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

cleanup() {
    if [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]]; then
        rm -f "$TEMP_FILE"
    fi
}

trap cleanup EXIT

log "=================================================="
log "          JENKINS AI SELF-HEALING AGENT"
log "=================================================="

log "Build Number : $BUILD_NUMBER"
log "Model        : $MODEL"
log "Base Branch  : $GIT_BRANCH"
log "Fix Branch   : $BRANCH"
log "Build Log    : $BUILD_LOG"

# ----------------------------------------------------------
# 1. VERIFY REQUIREMENTS
# ----------------------------------------------------------

log "Checking required commands..."

for CMD in curl jq git gh python3; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        log "ERROR: Required command missing: $CMD"
        exit 1
    fi
done

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    log "ERROR: GITHUB_TOKEN is missing."
    exit 1
fi

if [[ ! -s "$BUILD_LOG" ]]; then
    log "ERROR: Build log missing or empty."
    exit 1
fi

if [[ ! -d .git ]]; then
    log "ERROR: Git repository not found."
    exit 1
fi

if ! curl -fsS --connect-timeout 10 \
    "${OLLAMA_URL%/api/generate}/api/tags" >/dev/null 2>&1; then
    log "ERROR: Ollama API is not reachable."
    exit 1
fi

log "All prerequisites verified."

# ----------------------------------------------------------
# 2. CAPTURE JENKINS BUILD ERROR
# ----------------------------------------------------------

log "Capturing Jenkins build failure..."

ERROR_LOG=$(tail -n 150 "$BUILD_LOG")

echo
echo "========== JENKINS BUILD ERROR =========="
echo "$ERROR_LOG"
echo "========================================="

# ----------------------------------------------------------
# 3. IDENTIFY BROKEN FILE
# ----------------------------------------------------------

BROKEN_FILE=""
BUG_DESC=""

# Jenkinsfile: Docker command errors
if grep -Eqi 'docker[[:space:]]+rum|unknown flag: --rm' \
    <<< "$ERROR_LOG"; then

    BROKEN_FILE="Jenkinsfile"

    BUG_DESC="The Jenkinsfile contains an incorrect Docker command. Inspect the Docker command and correct the typo without modifying unrelated stages."

# Jenkinsfile: Pipeline syntax errors
elif grep -Eqi \
    'WorkflowScript:|MultipleCompilationErrorsException|No such DSL method|Expected a step|Invalid.*Declarative Pipeline' \
    <<< "$ERROR_LOG"; then

    BROKEN_FILE="Jenkinsfile"

    BUG_DESC="The Jenkins Declarative Pipeline contains a syntax or DSL error. Identify and correct the exact pipeline issue."

# Dockerfile errors
elif grep -Eqi \
    'Dockerfile.*(error|failed)|failed to solve.*Dockerfile' \
    <<< "$ERROR_LOG"; then

    BROKEN_FILE="Dockerfile"

    BUG_DESC="The Dockerfile contains an invalid instruction or build configuration. Fix the actual Docker build error."

# Java errors
elif grep -Eqi 'error: .*|cannot find symbol|illegal start' \
    <<< "$ERROR_LOG" &&
    grep -qE '\.java' <<< "$ERROR_LOG"; then

    BROKEN_FILE=$(grep -oE '[a-zA-Z0-9_./-]+\.java' \
        <<< "$ERROR_LOG" | head -n1)

    BUG_DESC="The Java source contains a compilation error. Fix the specific reported issue."

# Shell script errors
elif grep -Eqi \
    'command not found|syntax error near unexpected token' \
    <<< "$ERROR_LOG"; then

    SHELL_FILE=$(grep -oE '(/[a-zA-Z0-9_./-]+|[a-zA-Z0-9_./-]+)\.sh' \
        <<< "$ERROR_LOG" | head -n1 || true)

    if [[ -n "$SHELL_FILE" ]]; then
        BROKEN_FILE="${SHELL_FILE##*/}"
    fi

    BUG_DESC="The shell script contains an invalid command or syntax. Fix the actual error."

# Node.js errors
elif grep -Eqi \
    'npm ERR!|npm error|SyntaxError|Module not found|Cannot find module' \
    <<< "$ERROR_LOG"; then

    JS_FILE=$(grep -oE \
        '(src|backend|frontend)/[a-zA-Z0-9_./-]+\.(js|jsx|ts|tsx)' \
        <<< "$ERROR_LOG" | head -n1 || true)

    if [[ -n "$JS_FILE" ]]; then
        BROKEN_FILE="$JS_FILE"
    elif grep -Eqi 'package-lock|npm ci|lock file' <<< "$ERROR_LOG"; then
        BROKEN_FILE="package-lock.json"
    else
        BROKEN_FILE="package.json"
    fi

    BUG_DESC="The Node.js project has a dependency or source-code error. Analyze the npm output and fix the relevant issue."

fi

# ----------------------------------------------------------
# 4. VERIFY TARGET FILE
# ----------------------------------------------------------

if [[ -z "$BROKEN_FILE" ]]; then

    log "Could not identify the broken file."
    log "No automatic file modification will be attempted."

    exit 0
fi

log "Identified broken file: $BROKEN_FILE"

case "$BROKEN_FILE" in
    Jenkinsfile|Dockerfile|*.sh|*.java|*.js|*.jsx|*.ts|*.tsx|package.json|package-lock.json)
        ;;
    *)
        log "Unsupported file type. Skipping."
        exit 0
        ;;
esac

if [[ ! -f "$BROKEN_FILE" ]]; then
    log "Target file does not exist: $BROKEN_FILE"
    exit 0
fi

if ! git ls-files --error-unmatch "$BROKEN_FILE" >/dev/null 2>&1; then
    log "Target file is not tracked by Git."
    exit 0
fi

if [[ -z "$BUG_DESC" ]]; then
    BUG_DESC="Analyze the actual Jenkins failure and fix the root cause in the target file."
fi

CURRENT_CONTENT=$(cat "$BROKEN_FILE")

# ----------------------------------------------------------
# 5. CREATE AI PROMPT
# ----------------------------------------------------------

log "Preparing AI repair prompt..."

PROMPT=$(cat <<EOF
You are an expert DevOps engineer and CI/CD self-healing agent.

Your job is to repair the actual Jenkins build failure.

TARGET FILE:
$BROKEN_FILE

BUG DESCRIPTION:
$BUG_DESC

ACTUAL JENKINS ERROR:
$ERROR_LOG

CURRENT FILE CONTENT:
================ START ================
$CURRENT_CONTENT
================ END ==================

REQUIREMENTS:

1. Identify the exact root cause.
2. Correct the actual error.
3. Preserve all existing functionality.
4. Do not remove existing pipeline stages.
5. Preserve all credentials references.
6. Preserve environment variables and URLs.
7. Do not introduce unrelated changes.
8. Do not invent credentials or configuration.
9. For Jenkinsfile, return a valid Declarative Pipeline.
10. For shell scripts, return valid Bash code.
11. Return the complete corrected file.
12. If the issue cannot be safely fixed, return NO_FIX_AVAILABLE.

OUTPUT FORMAT:

Return ONLY the complete corrected source code.

No explanations.
No Markdown fences.
No additional commentary.
No partial code.

The output must be directly usable as a complete replacement for $BROKEN_FILE.
EOF
)

# ----------------------------------------------------------
# 6. CALL OLLAMA
# ----------------------------------------------------------

log "Sending failure analysis to Ollama..."
log "Model: $MODEL"

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

RESPONSE=$(curl \
    --fail \
    --silent \
    --show-error \
    --connect-timeout 15 \
    --max-time 900 \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$OLLAMA_URL")

FIXED_CONTENT=$(jq -r '.response // empty' <<< "$RESPONSE")

if [[ -z "$FIXED_CONTENT" ]]; then
    log "ERROR: Empty AI response."
    exit 1
fi

if grep -q 'NO_FIX_AVAILABLE' <<< "$FIXED_CONTENT"; then
    log "AI could not generate a safe fix."
    exit 0
fi

log "AI response received."

# ----------------------------------------------------------
# 7. CLEAN AI RESPONSE
# ----------------------------------------------------------

if grep -q '^```' <<< "$FIXED_CONTENT"; then

    CLEANED_CONTENT=$(printf '%s\n' "$FIXED_CONTENT" | awk '
        /^```/ {
            if (!inside) {
                inside=1
                next
            }
            exit
        }
        inside {
            print
        }
    ')

    if [[ -n "$CLEANED_CONTENT" ]]; then
        FIXED_CONTENT="$CLEANED_CONTENT"
    fi
fi

# ----------------------------------------------------------
# 8. SAVE GENERATED CONTENT
# ----------------------------------------------------------

TEMP_FILE=$(mktemp)

printf '%s\n' "$FIXED_CONTENT" > "$TEMP_FILE"

if [[ $(wc -l < "$TEMP_FILE") -lt 2 ]]; then
    log "Generated content is too short. Rejecting."
    exit 0
fi

if grep -Eqi \
    '^(Here is|Here are|Explanation:|The corrected|```)' \
    "$TEMP_FILE"; then

    log "AI returned explanatory text. Rejecting."
    exit 0
fi

# ----------------------------------------------------------
# 9. VALIDATE GENERATED CODE
# ----------------------------------------------------------

log "Validating generated code..."

case "$BROKEN_FILE" in

    *.sh)

        if ! bash -n "$TEMP_FILE"; then
            log "Invalid Bash syntax. Rejecting fix."
            exit 0
        fi

        log "Bash syntax validation passed."
        ;;

    Jenkinsfile)

        if ! grep -Eq '^[[:space:]]*pipeline[[:space:]]*\{' "$TEMP_FILE"; then
            log "Invalid Jenkinsfile: pipeline block missing."
            exit 0
        fi

        if ! grep -Eq '^[[:space:]]*stages[[:space:]]*\{' "$TEMP_FILE"; then
            log "Invalid Jenkinsfile: stages block missing."
            exit 0
        fi

        if ! grep -Eq '^[[:space:]]*post[[:space:]]*\{' "$TEMP_FILE"; then
            log "WARNING: Jenkinsfile post block is missing."
            exit 0
        fi

        log "Basic Jenkinsfile validation passed."
        ;;

    *.json)

        if ! jq empty "$TEMP_FILE"; then
            log "Invalid JSON. Rejecting fix."
            exit 0
        fi

        log "JSON validation passed."
        ;;

    Dockerfile)

        if ! grep -Eq '^[[:space:]]*FROM[[:space:]]+' "$TEMP_FILE"; then
            log "Dockerfile FROM instruction missing."
            exit 0
        fi

        log "Basic Dockerfile validation passed."
        ;;

    *.js|*.jsx|*.ts|*.tsx)

        log "Source validation will be performed by the next application build."
        ;;

    *.java)

        log "Java validation will be performed by the next compilation."
        ;;

    package.json|package-lock.json)

        log "Package configuration validation passed."
        ;;

esac

# ----------------------------------------------------------
# 10. VERIFY GITHUB REPOSITORY
# ----------------------------------------------------------

REPOSITORY=$(gh repo view \
    --json nameWithOwner \
    --jq '.nameWithOwner')

if [[ -z "$REPOSITORY" ]]; then
    log "Could not identify GitHub repository."
    exit 1
fi

log "GitHub repository: $REPOSITORY"

# ----------------------------------------------------------
# 11. CREATE FIX BRANCH
# ----------------------------------------------------------

log "Creating AI fix branch..."

git config user.email "self-heal-bot@local"
git config user.name "Self Heal Bot"

git switch -c "$BRANCH"

# ----------------------------------------------------------
# 12. APPLY FIX
# ----------------------------------------------------------

cp "$TEMP_FILE" "$BROKEN_FILE"

if ! git diff --check; then

    log "Git whitespace validation failed."

    git restore -- "$BROKEN_FILE"

    exit 0
fi

if git diff --quiet -- "$BROKEN_FILE"; then
    log "AI did not generate any changes."
    exit 0
fi

log "AI changes applied."

echo
echo "========== PROPOSED CHANGES =========="

git diff -- "$BROKEN_FILE"

echo "======================================"

# ----------------------------------------------------------
# 13. COMMIT FIX
# ----------------------------------------------------------

git add -- "$BROKEN_FILE"

git commit \
    -m "AI Auto-Fix: Build #${BUILD_NUMBER} - ${BROKEN_FILE}"

log "AI fix committed."

# ----------------------------------------------------------
# 14. PUSH FIX BRANCH
# ----------------------------------------------------------

export GH_TOKEN="$GITHUB_TOKEN"

gh auth setup-git

log "Pushing fix branch to GitHub..."

git push origin "$BRANCH"

# ----------------------------------------------------------
# 15. CREATE PULL REQUEST
# ----------------------------------------------------------

log "Creating GitHub Pull Request..."

PR_BODY=$(cat <<EOF
## AI Self-Healing Pull Request

**Build Number:** #${BUILD_NUMBER}

**AI Model:** ${MODEL}

**Target File:** ${BROKEN_FILE}

**Base Branch:** ${GIT_BRANCH}

### Detected Issue

${BUG_DESC}

### Jenkins Error

\`\`\`
${ERROR_LOG}
\`\`\`

### Changes

- Analyzed Jenkins failure.
- Generated a proposed correction using local Ollama.
- Applied basic source validation.
- Isolated the change to the identified file.

### Review

This change was generated automatically.

Please review the proposed correction and run a new Jenkins build before merging.
EOF
)

gh pr create \
    --repo "$REPOSITORY" \
    --base "$GIT_BRANCH" \
    --head "$BRANCH" \
    --title "AI Auto-Fix: Build #${BUILD_NUMBER} - ${BROKEN_FILE}" \
    --body "$PR_BODY"

# ----------------------------------------------------------
# 16. COMPLETED
# ----------------------------------------------------------

log "=================================================="
log "          SELF-HEALING COMPLETED"
log "=================================================="

log "Repository : $REPOSITORY"
log "Target     : $BROKEN_FILE"
log "Branch     : $BRANCH"
log "Base       : $GIT_BRANCH"
log "AI Model   : $MODEL"

log "Pull Request created successfully."
