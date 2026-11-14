
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

        // AI Self-Healing
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

# Initialize build log
: > "$WORKSPACE/$BUILD_LOG"

# Capture all output in console and build log
exec > >(tee -a "$WORKSPACE/$BUILD_LOG") 2>&1

echo "=========================================="
echo "          CHECKOUT STAGE"
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
echo "       NODE.JS INSTALL AND BUILD"
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

        if node -e "process.exit(require('./package.json').scripts?.build ? 0 : 1)"; then
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
echo "          DOCKER IMAGE BUILD"
echo "=========================================="

test -f Dockerfile

echo "Building Docker image..."

docker builds \
    --pull \
    -t "$DOCKER_IMAGE:$BUILD_NUMBER" \
    -t "$DOCKER_IMAGE:latest" \
    .

echo ""
echo "Docker images created:"

docker images "$DOCKER_IMAGE"

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

            withCredentials([
                string(
                    credentialsId: 'github-token',
                    variable: 'GITHUB_TOKEN'
                )
            ]) {

                sh '''#!/bin/bash
set -u

echo "=========================================="
echo "       AI SELF-HEALING EXECUTION"
echo "=========================================="

LOG_FILE="$WORKSPACE/$BUILD_LOG"

echo "Build number: $BUILD_NUMBER"
echo "Build log: $LOG_FILE"

if [ -s "$LOG_FILE" ]; then

    echo ""
    echo "Build log found."
    echo "Last 100 lines of build output:"

    tail -n 100 "$LOG_FILE"

    echo ""
    echo "Invoking AI self-healing agent..."

    export BUILD_NUMBER
    export GIT_BRANCH
    export OLLAMA_MODEL
    export OLLAMA_URL

    bash ./self_heal.sh "$LOG_FILE" || {
        echo "WARNING: AI self-healing encountered an issue."
    }

else

    echo "ERROR: Build log is missing or empty."
    echo "AI agent cannot analyze this failure."

fi

echo ""
echo "AI self-healing execution finished."
'''
            }
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
