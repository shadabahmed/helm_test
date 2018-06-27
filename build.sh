#!/bin/bash
set -u
SCRIPT_DIR="./"
SCRIPT_NAME=$(basename $0)
BUILD_DIR="${SCRIPT_DIR}/build"
BUILD="false"
PUSH="false"
PACK_HELM="false"
PUSH_HELM="false"

errorExit () {
    echo -e "\nERROR: $1"; echo
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Script for building the ACME web application, Docker image and Helm chart

Usage: ./${SCRIPT_NAME} <options>

--build             : [optional] Build the Docker image
--push              : [optional] Push the Docker image
--pack_helm         : [optional] Pack helm chart
--push_helm         : [optional] Push the the helm chart
-h | --help         : Show this usage

END_USAGE

    exit 1
}

# Docker login
dockerLogin () {
    echo -e "\nDocker login"

    if [ ! -z "${DOCKER_REG}" ]; then
        # Make sure credentials are set
        if [ -z "${DOCKER_USR}" ] || [ -z "${DOCKER_PSW}" ]; then
            errorExit "Docker credentials not set (DOCKER_USR and DOCKER_PSW)"
        fi
        echo ${DOCKER_PSW} | docker login -u ${DOCKER_USR} --password-stdin ${DOCKER_REG} || errorExit "Docker login to ${DOCKER_REG} failed"
    else
        echo "Docker registry not set. Skipping"
    fi
}

# Build Docker images
buildDockerImage () {
    echo -e "\nBuilding ${DOCKER_REPO}:${DOCKER_TAG}"

    # Prepare build directory
    echo -e "\nPreparing files"
    mkdir -p ${BUILD_DIR}/site
    cp -v  ${SCRIPT_DIR}/docker/Dockerfile ${BUILD_DIR}
    cp -rv ${SCRIPT_DIR}/src/* ${BUILD_DIR}/site/

    # Embed the app version
    echo -e "\nWriting version ${DOCKER_TAG} to files"
    sed -i.org "s/__APP_VERSION__/${DOCKER_TAG}/g" ${BUILD_DIR}/site/*.html
    rm -f ${BUILD_DIR}/site/*.org

    echo -e "\nBuilding Docker image"
    docker build -t ${DOCKER_REG}/${DOCKER_USR}/${DOCKER_REPO}:${DOCKER_TAG} ${BUILD_DIR} || errorExit "Building ${DOCKER_REPO}:${DOCKER_TAG} failed"
}

# Push Docker images
pushDockerImage () {
    echo -e "\nPushing ${DOCKER_REPO}:${DOCKER_TAG}"

    docker push ${DOCKER_REG}/${DOCKER_USR}/${DOCKER_REPO}:${DOCKER_TAG} || errorExit "Pushing ${DOCKER_REPO}:${DOCKER_TAG} failed"
}

# Packing the helm chart
packHelmChart() {
    echo -e "\nPacking Helm chart"
    rm -rf ${BUILD_DIR}/helm
    [ -d ${BUILD_DIR}/helm ] && rm -rf ${BUILD_DIR}/helm
    mkdir -p ${BUILD_DIR}/helm

    helm package -d ${BUILD_DIR}/helm ${SCRIPT_DIR}/helm/helm_test || errorExit "Packing helm chart ${SCRIPT_DIR}/helm/helm_test failed"
}

# Pushing the Helm chart
# Note - this uses the Artifactory API. You can replace it with any other solution you use.
pushHelmChart() {
    echo -e "\nPushing Helm chart"
    local chart_name=$(ls -1 ${BUILD_DIR}/helm/*.tgz 2> /dev/null)
    echo "Helm chart: ${chart_name}"
    [ ! -z "${chart_name}" ] || errorExit "Did not find the helm chart to deploy"
    cd ${BUILD_DIR}/helm/
    tar -xvzf *.tgz
    cd helm_test
    git init .
    git add .
    git commit -m "Updated at $(date +'%Y-%m-%d %H:%M:%S')"
    git remote add origin ${HELM_GIT_REPO}
    git push origin +master
    echo
}

# Process command line options. See usage above for supported options
processOptions () {
    if [ $# -eq 0 ]; then
        usage
    fi

    while [[ $# > 0 ]]; do
        case "$1" in
            --build)
                BUILD="true"; shift
            ;;
            --push)
                PUSH="true"; shift
            ;;
            --pack_helm)
                PACK_HELM="true"; shift
            ;;
            --push_helm)
                PUSH_HELM="true"; shift
            ;;
            -h | --help)
                usage
            ;;
            *)
                usage
            ;;
        esac
    done
}

main () {
    echo -e "\nRunning"

    echo "DOCKER_REG:   ${DOCKER_REG}"
    echo "DOCKER_USR:   ${DOCKER_USR}"
    echo "DOCKER_REPO:  ${DOCKER_REPO}"
    echo "DOCKER_TAG:   ${DOCKER_TAG}"
    echo "HELM_GIT_REPO:    ${HELM_GIT_REPO}"

    # Build and push docker images if needed
    if [ "${BUILD}" == "true" ]; then
        buildDockerImage
    fi
    if [ "${PUSH}" == "true" ]; then
        # Attempt docker login
        dockerLogin
        pushDockerImage
    fi

    # Pack and push helm chart if needed
    if [ "${PACK_HELM}" == "true" ]; then
        packHelmChart
    fi
    if [ "${PUSH_HELM}" == "true" ]; then
        pushHelmChart
    fi
}

############## Main

processOptions $*
main
