
pipeline {
    agent any

    triggers {
        pollSCM('H/2 * * * *')
    }

    options {
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        IMAGE_NAME = 'afif729/university-lms-portal'
        DEPLOYMENT = 'lms-portal'
        CONTAINER = 'lms-portal'
        SERVICE = 'lms-portal-service'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                script {
                    env.IMAGE_TAG = "build-${env.BUILD_NUMBER}"
                }

                bat '''
                    docker build --pull -t %IMAGE_NAME%:%IMAGE_TAG% .
                '''
            }
        }

        stage('Test Image') {
            steps {
                bat '''
                docker rm -f lms-ci-test 2>NUL
                docker run -d --name lms-ci-test -p 18080:80 %IMAGE_NAME%:%IMAGE_TAG%
                '''

            script {
                try {
                    powershell(
                        executable: 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
                        script: '''
                            $healthy = $false

                            for ($i = 0; $i -lt 15; $i++) {
                                try {
                                    $response = Invoke-WebRequest `
                                        -Uri "http://localhost:18080/healthz" `
                                        -UseBasicParsing `
                                        -TimeoutSec 3

                                    if ($response.StatusCode -eq 200 -and
                                        $response.Content.Trim() -eq "healthy") {
                                        $healthy = $true
                                        break
                                    }
                                }
                                catch {
                                    Start-Sleep -Seconds 2
                                }
                            }

                            if (-not $healthy) {
                                docker logs lms-ci-test
                                throw "Docker image health test failed"
                            }

                            Write-Host "Docker image health test passed."
                        '''
                    )
                } catch (err) {
                    error('Docker image health test failed')
                }
            }
        }

            post {
                always {
                    bat 'docker rm -f lms-ci-test 2>NUL'
                }
            }
        }

        stage('Publish to Docker Hub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    bat '''
                        @echo off
                        echo %DOCKER_PASSWORD% | docker login -u %DOCKER_USER% --password-stdin
                        if errorlevel 1 exit /b 1
                        docker push %IMAGE_NAME%:%IMAGE_TAG%
                        if errorlevel 1 exit /b 1
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([
                    file(
                        credentialsId: 'kubeconfig-file',
                        variable: 'KUBECONFIG_FILE'
                    )
                ]) {
                    powershell '''
                        $ErrorActionPreference = "Stop"
                        $env:KUBECONFIG = $env:KUBECONFIG_FILE

                        # Render the manifest with this exact image version.
                        $manifest = Get-Content deployment.yaml -Raw
                        $manifest = $manifest.Replace(
                            "YOUR_DOCKERHUB_USERNAME",
                            $env:IMAGE_NAME.Split("/")[0]
                        )
                        $manifest = $manifest.Replace(
                            ":initial",
                            ":" + $env:IMAGE_TAG
                        )

                        Set-Content -Path deployment-ci.yaml `
                            -Value $manifest -Encoding ascii

                        kubectl apply -f deployment-ci.yaml
                        if ($LASTEXITCODE -ne 0) { exit 1 }

                        kubectl apply -f service.yaml
                        if ($LASTEXITCODE -ne 0) { exit 1 }
                    '''
                }
            }
        }

        stage('Verify Rollout and Auto-Rollback') {
            steps {
                withCredentials([
                    file(
                        credentialsId: 'kubeconfig-file',
                        variable: 'KUBECONFIG_FILE'
                    )
                ]) {
                    script {
                        int rolloutStatus = powershell(
                            returnStatus: true,
                            script: '''
                                $env:KUBECONFIG = $env:KUBECONFIG_FILE
                                kubectl rollout status deployment/lms-portal --timeout=90s
                                exit $LASTEXITCODE
                            '''
                        )

                        if (rolloutStatus != 0) {
                            echo 'Rollout failed. Attempting automatic rollback.'

                            int rollbackStatus = powershell(
                                returnStatus: true,
                                script: '''
                                    $env:KUBECONFIG = $env:KUBECONFIG_FILE
                                    kubectl rollout undo deployment/lms-portal
                                    if ($LASTEXITCODE -ne 0) { exit 1 }

                                    kubectl rollout status deployment/lms-portal --timeout=120s
                                    exit $LASTEXITCODE
                                '''
                            )

                            if (rollbackStatus != 0) {
                                error('Automatic rollback failed. Manual intervention required.')
                            }

                            error('New release failed; previous stable release restored.')
                        }

                        echo 'Deployment rollout successful.'
                    }
                }
            }
        }
    }

    post {
        always {
            bat 'docker rm -f lms-ci-test 2>NUL'
            echo 'CI/CD pipeline finished.'
        }
    }
}
