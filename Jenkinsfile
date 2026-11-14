
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()

        buildDiscarder(logRotator(
            numToKeepStr: '10',
            artifactNumToKeepStr: '5'
        ))
    }

    environment {
        // GitHub
        GIT_URL = 'https://github.com/cloudvivek/DevOps-Project-Zomato-Kastro.git'
        GIT_BRANCH = 'master'

        // Docker Hub
        DOCKER_IMAGE = 'teqvivek123/zomato-kastro'

        // Build log
        BUILD_LOG = 'build_output.log'

        // Local Ollama
        OLLAMA_MODEL = 'qwen2.5-coder:3b'
        OLLAMA_URL = 'http://localhost:11434/api/generate'
    }

    stages {

        // ==================================================
        // 1. CHECKOUT
        // ==================================================

        stage('Checkout') {
            steps {
                sh '''#!/bin/bash
set -Eeuo pipefail

# Initialize log for this build
: > "$WORKSPACE/$BUILD_LOG"

# Capture output in console and log
exec > >(tee -a "$WORKSPACE/$BUILD_LOG") 2>&1

echo "=========================================="
echo "              CHECKOUT STAGE"
echo "=========================================="

echo "Repository: $GIT_URL"
echo "Branch: $GIT_BRANCH"

echo ""
echo "Latest Git commit:"
git log -1 --oneline

echo ""
echo "Checking required project files..."

test -f package.json
test -f Dockerfile
test -f self_heal.sh

echo "package.json       : FOUND"
echo "Dockerfile         : FOUND"
echo "self_heal.sh       : FOUND"

echo ""
echo "Checkout verification completed."
'''
            }
        }

        // ==================================================
        // 2. NODE.JS INSTALL AND BUILD
        // ==================================================

        stage('Node.js Install and Build') {
            steps {
                sh '''#!/bin/bash
set -Eeuo pipefail

exec > >(tee -a "$WORKSPACE/$BUILD_LOG") 2>&1

echo "=========================================="
echo "         NODE.JS INSTALL AND BUILD"
echo "=========================================="

test -f package.json

echo "Starting Node.js container..."

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e NPM_CONFIG_CACHE=/tmp/.npm \
    -v "$WORKSPACE:/app" \
    -w /app \
    node:20-alpine \
    sh -lc '
        set -eu

        echo "Node version:"
        node --version

        echo ""
        echo "NPM version:"
        npm --version

        echo ""
        echo "Installing dependencies..."

        if [ -f package-lock.json ]; then
            npm ci
        else
            npm install
        fi

        echo ""
        echo "Checking build script..."

        BUILD_SCRIPT=$(npm pkg get scripts.build)

        if [ "$BUILD_SCRIPT" != "undefined" ] && [ "$BUILD_SCRIPT" != "{}" ]; then
            echo "Build script found."
            npm run build
        else
            echo "No build script found. Skipping build."
        fi
    '

echo ""
echo "Node.js build completed successfully."
'''
            }
        }

        // ==================================================
        // 3. BUILD DOCKER IMAGE
        // ==================================================

        stage('Build Docker Image') {
            steps {
                sh '''#!/bin/bash
set -Eeuo pipefail

exec > >(tee -a "$WORKSPACE/$BUILD_LOG") 2>&1

echo "=========================================="
echo "           DOCKER IMAGE BUILD"
echo "=========================================="

test -f Dockerfile

echo ""
echo "=========================================="
echo "          INTENTIONAL FAILURE TEST"
echo "=========================================="

echo "Image: $DOCKER_IMAGE"
echo "Build: $BUILD_NUMBER"

echo ""
echo "Executing Docker command:"

echo "docker builds --pull -t $DOCKER_IMAGE:$BUILD_NUMBER -t $DOCKER_IMAGE:latest ."

echo ""
echo "Starting Docker image build..."

# INTENTIONAL ERROR FOR AI SIMULATION
# Correct command would be: docker build
docker builds \
    --pull \
    -t "$DOCKER_IMAGE:$BUILD_NUMBER" \
    -t "$DOCKER_IMAGE:latest" \
    .

echo ""
echo "Docker image build completed successfully."
'''
            }
        }
    }

    // ======================================================
    // POST BUILD ACTIONS
    // ======================================================

    post {

        failure {
            echo 'AI Self-Healing Agent triggered.'

            sh '''#!/bin/bash
set -u

echo "=========================================="
echo "       AI SELF-HEALING EXECUTION"
echo "=========================================="

LOG_FILE="$WORKSPACE/$BUILD_LOG"

echo "Build number : $BUILD_NUMBER"
echo "Build log    : $LOG_FILE"
echo "AI model     : $OLLAMA_MODEL"
echo "Ollama URL   : $OLLAMA_URL"

if [ ! -s "$LOG_FILE" ]; then
    echo "ERROR: Build log is missing or empty."
    exit 1
fi

echo ""
echo "Build log successfully captured."

echo ""
echo "Failure details:"
grep -E 'Executing Docker command:|docker builds|unknown flag|not a docker command' \
    "$LOG_FILE" | tail -n 20 || true

echo ""
echo "Invoking Ollama AI analyzer..."

AI_STATUS=0

bash "$WORKSPACE/self_heal.sh" "$LOG_FILE" || AI_STATUS=$?

if [ "$AI_STATUS" -ne 0 ]; then
    echo "WARNING: AI analysis failed with exit code $AI_STATUS."
else
    echo "AI analysis completed."
fi

echo ""
echo "Archiving AI analysis report..."

echo "=========================================="
echo "AI SELF-HEALING EXECUTION FINISHED"
echo "=========================================="
'''

            archiveArtifacts(
                artifacts: 'ai-reports/*.md',
                allowEmptyArchive: true
            )
        }

        always {
            echo 'Pipeline execution completed.'

            archiveArtifacts(
                artifacts: 'build_output.log',
                allowEmptyArchive: true
            )
        }
    }
}
