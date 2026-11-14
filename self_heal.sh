#!/bin/bash
set -e

BUILD_LOG="build_output.log"
BRANCH="fix/auto-${BUILD_NUMBER}"
OLLAMA_URL="http://localhost:11434/api/generate"
MODEL="qwen2.5-coder:3b"

echo "🩺 Self-heal triggered for build ${BUILD_NUMBER}"

ERROR_LOG=$(tail -n 60 "${BUILD_LOG}" 2>/dev/null || echo "No log captured")

echo "=== Captured error log ==="
echo "$ERROR_LOG"
echo "==========================="

# ── 1. Identify the broken file ─────────────────────────────────────────
BROKEN_FILE=$(echo "$ERROR_LOG" | grep -oE '[a-zA-Z0-9_./-]+\.java' | head -n1 | sed 's#^\./##')

if [[ -z "$BROKEN_FILE" || ! -f "$BROKEN_FILE" ]]; then
    BROKEN_FILE=$(echo "$ERROR_LOG" | grep -oE '\.?/?[a-zA-Z0-9_-]+\.sh' | head -n1 | sed 's#^\./##')
fi

if [[ -z "$BROKEN_FILE" || ! -f "$BROKEN_FILE" ]]; then
    echo "⚠️ Could not identify a specific broken file from the log. Trying build.sh as default."
    BROKEN_FILE="build.sh"
fi

if [[ ! -f "$BROKEN_FILE" ]]; then
    echo "❌ '${BROKEN_FILE}' does not exist in the repo. Cannot proceed with a fix."
    exit 0
fi

echo "🔎 Identified broken file: ${BROKEN_FILE}"
CURRENT_CONTENT=$(cat "$BROKEN_FILE")

# ── 2. Extract a pointed description of the bug, by error category ─────
BUG_DESC=""

BROKEN_CMD=$(echo "$ERROR_LOG" | grep -oE '[a-zA-Z0-9_.-]+: command not found' | head -n1 | sed 's/: command not found//')
if [[ -n "$BROKEN_CMD" ]]; then
    BUG_DESC="The command '${BROKEN_CMD}' does not exist. It is a typo of a real command. Figure out the closest real command name and fix the typo."
fi

if [[ -z "$BUG_DESC" ]]; then
    BROKEN_FLAG=$(echo "$ERROR_LOG" | grep -oiE "(invalid flag|unrecognized option): *[-a-zA-Z]+" | head -n1)
    if [[ -n "$BROKEN_FLAG" ]]; then
        BUG_DESC="There is a bad command-line flag: '${BROKEN_FLAG}'. It is a typo of a real, valid flag for that command. Fix the typo."
    fi
fi

if [[ -z "$BUG_DESC" ]]; then
    MISSING_PATH=$(echo "$ERROR_LOG" | grep -oE "[a-zA-Z0-9_./-]+: No such file or directory" | head -n1 | sed 's/: No such file or directory//')
    if [[ -n "$MISSING_PATH" ]]; then
        BUG_DESC="The path '${MISSING_PATH}' does not exist. It is likely a typo'd file/folder name used somewhere in this script. Fix the typo so it points to a path that is actually created or used correctly elsewhere in the script."
    fi
fi

if [[ -z "$BUG_DESC" ]]; then
    PERM_FILE=$(echo "$ERROR_LOG" | grep -oE "[a-zA-Z0-9_./-]+: Permission denied" | head -n1 | sed 's/: Permission denied//')
    if [[ -n "$PERM_FILE" ]]; then
        BUG_DESC="The file '${PERM_FILE}' is not executable. Add a line before it runs to make it executable (chmod +x), or fix how it's invoked (e.g. call it as 'bash ${PERM_FILE}' instead of './${PERM_FILE}')."
    fi
fi

if [[ -z "$BUG_DESC" ]]; then
    JAVA_ERR_LINE=$(echo "$ERROR_LOG" | grep -oE "[a-zA-Z0-9_./-]+\.java:[0-9]+: error: .+" | head -n1)
    if [[ -n "$JAVA_ERR_LINE" ]]; then
        BUG_DESC="There is a Java syntax error: ${JAVA_ERR_LINE}. Fix this specific syntax error."
    fi
fi

if [[ -z "$BUG_DESC" ]]; then
    LAST_LINE=$(echo "$ERROR_LOG" | grep -v '^\s*$' | tail -n1)
    BUG_DESC="The script failed with this error: ${LAST_LINE}. Diagnose the specific line causing it and fix it."
fi

echo "🐞 Bug description sent to LLM: ${BUG_DESC}"

# ── 3. Build the prompt ─────────────────────────────────────────────────
PROMPT=$(cat <<EOF
Fix the bug in this script.

--- SCRIPT (${BROKEN_FILE}) ---
${CURRENT_CONTENT}

--- BUG ---
${BUG_DESC}

--- TASK ---
Output the complete corrected script with the bug fixed. Output ONLY raw
script content — no explanations, no markdown fences, no commentary before
or after the code. Your entire response must be valid, directly-runnable
script content starting with the first line (e.g. the shebang) and nothing
else.
EOF
)

echo "📡 Calling local LLM (${MODEL})..."
RESPONSE=$(curl -s "${OLLAMA_URL}" -d @<(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{
    model: $model,
    prompt: $prompt,
    stream: false
}'))

FIXED_CONTENT=$(echo "$RESPONSE" | jq -r '.response')

echo "=== DEBUG: Raw LLM response ==="
echo "$FIXED_CONTENT"
echo "=== END DEBUG ==="

if [[ -z "$FIXED_CONTENT" || "$FIXED_CONTENT" == "null" || "$FIXED_CONTENT" == *"NO_FIX_AVAILABLE"* ]]; then
    echo "⚠️ No fix could be generated. Exiting cleanly."
    exit 0
fi

# Extract only what's between the first pair of code fences, if the model
# used them. If no fences are found, fall back to the raw response —
# the syntax validation gate below is what actually protects us in that case.
CLEANED_CONTENT=$(echo "$FIXED_CONTENT" | awk '
    /^```/ { fence++; next }
    fence == 1 { print }
')
if [[ -z "$CLEANED_CONTENT" ]]; then
    CLEANED_CONTENT="$FIXED_CONTENT"
fi
FIXED_CONTENT="$CLEANED_CONTENT"

if [[ $(echo "$FIXED_CONTENT" | wc -l) -lt 2 ]]; then
    echo "⚠️ Generated fix looks too short/invalid. Skipping to avoid corrupting the file."
    exit 0
fi

# ── Syntax validation gate ──────────────────────────────────────────────
# Regardless of how the model formatted its response, never trust it blindly.
# Only accept the result if it's actually valid, parseable script syntax.
# This is what actually protects against prose/commentary getting written
# into the file, not the fence-stripping above (which only helps when the
# model behaves and uses fences in the first place).
if [[ "$BROKEN_FILE" == *.sh ]]; then
    if ! bash -n <(echo "$FIXED_CONTENT") 2>/dev/null; then
        echo "⚠️ Generated fix is not valid bash syntax. Rejecting to avoid corrupting the file."
        echo "--- Rejected content (for reference) ---"
        echo "$FIXED_CONTENT"
        exit 0
    fi
    echo "✅ Syntax check passed: generated fix is valid bash."
fi
# (No equivalent lightweight syntax-only check is wired up for .java files
#  yet — javac requires a classpath/context to check properly. Treat any
#  .java auto-fix PR with extra scrutiny for now.)

# ── 4. Apply the fix: overwrite the file, commit, push, open PR ────────
git checkout -b "${BRANCH}"
echo "$FIXED_CONTENT" > "$BROKEN_FILE"

echo "📄 New content written to ${BROKEN_FILE}:"
cat "$BROKEN_FILE"

git config user.email "self-heal-bot@local"
git config user.name "Self Heal Bot"
git add "$BROKEN_FILE"
git commit -m "🤖 Auto-fix attempt for build #${BUILD_NUMBER} (${BROKEN_FILE})"

ORIGIN_URL=$(git config --get remote.origin.url)
CLEAN_URL=$(echo "$ORIGIN_URL" | sed -E 's#(https://)?(git@)?github.com[:/]#github.com/#' | sed 's#\.git$##')
PUSH_URL="https://x-access-token:${GITHUB_TOKEN}@${CLEAN_URL}.git"

git push "$PUSH_URL" "${BRANCH}"

gh pr create \
  --title "🤖 Auto-fix: build #${BUILD_NUMBER} failure (${BROKEN_FILE})" \
  --body "Automated fix proposed by local self-healing pipeline for build #${BUILD_NUMBER}. Model: ${MODEL}. File changed: ${BROKEN_FILE}. Bug detected: ${BUG_DESC} Please review carefully — this was generated automatically and may be wrong." \
  --base main \
  --head "${BRANCH}"

echo "✅ PR created for branch ${BRANCH}."
