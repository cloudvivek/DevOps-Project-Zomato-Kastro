
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
        GIT_URL      = 'https://github.com/cloudvivek/DevOps-Project-Zomato-Kastro.git'
        GIT_BRANCH   = 'master'

        // Docker Hub
        DOCKER_IMAGE = 'teqvivek123/zomato-kastro'

        // Build error log
        BUILD_LOG    = 'build_output.log'
    }

    stages {

        // 1. CHECKOUT
        stage('Checkout') {
            steps {
                sh '''
                    #!/bin/bash
                    set -Eeuo pipefail

                    # Start a fresh build log
                    : > "$WORKSPACE/$BUILD_LOG"

                    # Capture output in Jenkins console and log file
                    exec > >(tee -a "$WORKSPACE/$BUILD_LOG") 2>&1

                    echo "======================================"
                    echo "GitHub Checkout Successful"
                    echo "======================================"

                    git log -1 --oneline

                    echo "Repository: $GIT_URL"
                    echo "Branch: $GIT_BRANCH"

                    echo "Checking required files..."

                    test -f package.json
                    test -f Dockerfile
                    test -f self_heal.sh

                    echo "All required files are available."
                '''
            }
        }

        // 2. NODE.JS INSTALL & BUILD
        stage('Node.js Install and Build') {
            steps {
                sh '''
                    #!/bin/bash
                    set -Eeuo pipefail

                    exec > >(tee -a "$WORKSPACE/$BUILD_LOG") 2>&1

                    echo "======================================"
                    echo "Node.js Project Build"
                    echo "======================================"

                    test -f package.json

                    echo "Starting Node.js Docker container..."

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

                            echo "NPM version:"
                            npm --version

                            echo "Installing dependencies..."
                            npm ci

                            if node -e "process.exit(require('./package.json').scripts?.build ? 0 : 1)"; then
                                echo "Build script found."
                                npm run build
                            else
                                echo "No build script found. Skipping build."
                            fi
                        '

                    echo "Node.js build completed successfully."
                '''
            }
        }

        // 3. BUILD DOCKER IMAGE
        stage('Build Docker Image') {
            steps {
                sh '''
                    #!/bin/bash
                    set -Eeuo pipefail

                    exec > >(tee -a "$WORKSPACE/$BUILD_LOG") 2>&1

                    echo "======================================"
                    echo "Docker Image Build"
                    echo "======================================"

                    test -f Dockerfile

                    docker bui \
                        --pull \
                        -t "$DOCKER_IMAGE:$BUILD_NUMBER" \
                        -t "$DOCKER_IMAGE:latest" \
                        .

                    echo "Docker image built successfully."

                    docker images "$DOCKER_IMAGE"
                '''
            }
        }
    }

    // SELF-HEALING POST ACTIONS
    post {

        failure {
            echo '🤖 Pipeline failed — invoking self-healing agent...'

            sh '''
                #!/bin/bash

                echo "======================================"
                echo "SELF-HEALING EXECUTION"
                echo "======================================"

                LOG_FILE="$WORKSPACE/$BUILD_LOG"

                if [ -s "$LOG_FILE" ]; then
                    echo "Build log found: $LOG_FILE"
                    echo "Last 100 lines of build output:"
                    tail -n 100 "$LOG_FILE"

                    echo "Invoking AI self-healing agent..."

                    bash ./self_heal.sh "$LOG_FILE" || {
                        echo "Self-healing agent encountered an issue."
                    }
                else
                    echo "ERROR: Build log is missing or empty."
                    echo "Cannot provide error details to AI agent."
                fi
            '''
        }

        always {
            echo '🧹 Pipeline execution completed.'
        }
    }
}
