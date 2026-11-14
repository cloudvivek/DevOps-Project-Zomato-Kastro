
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
    }

    stages {

        // 1. CHECKOUT
        stage('Checkout') {
            steps {
                deleteDir()

                git branch: "${GIT_BRANCH}",
                    url: "${GIT_URL}"

                sh '''
                    echo "======================================"
                    echo "GitHub Checkout Successful"
                    echo "======================================"

                    git log -1 --oneline
                    echo "Repository: $GIT_URL"
                    echo "Branch: $GIT_BRANCH"
                '''
            }
        }

        // 2. NODE.JS INSTALL & BUILD
        stage('Node.js Install and Build') {
            steps {
                sh '''
                    set -eu

                    echo "===== Node.js Project Build ====="

                    test -f package.json

                    docker run --rm \
                        -v "$WORKSPACE:/app" \
                        -w /app \
                        node:20-alpine \
                        sh -lc '
                            set -eu

                            echo "Node version:"
                            node --version

                            echo "NPM version:"
                            npm --version

                            npm ci

                            if node -e "process.exit(require('./package.json').scripts?.build ? 0 : 1)"; then
                                echo "Build script found. Running npm run build."
                                npm run build
                            else
                                echo "No build script defined. Skipping npm run build."
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
                    set -eu

                    echo "===== Docker Image Build ====="

                    test -f Dockerfile

                    docker buil \
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
            echo '🤖 Pipeline failed — invoking self-healing stage...'

            sh 'bash ./self_heal.sh || echo "Self-heal script encountered an issue, see logs above."'
        }

        always {
            echo '🧹 Pipeline execution completed.'
        }
    }
}
