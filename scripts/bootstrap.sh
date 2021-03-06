#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# if version not passed in, default to latest released version
VERSION=1.4.3
# if ca version not passed in, default to latest released version
CA_VERSION=1.4.3
# current version of thirdparty images (couchdb, kafka and zookeeper) released
THIRDPARTY_IMAGE_VERSION=0.4.15
ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')")
MARCH=$(uname -m)

printHelp() {
    echo "Usage: bootstrap.sh [version [ca_version [thirdparty_version]]] [options]"
    echo
    echo "options:"
    echo "-h : this help"
    echo "-b : bypass download of platform-specific binaries"
    echo
    echo "e.g. bootstrap.sh 1.4.3 -b"
    echo "would download docker images and binaries for version 1.4.3"
}

# Incrementally downloads the .tar.gz file locally first, only decompressing it
# after the download is complete. This is slower than binaryDownload() but
# allows the download to be resumed.
binaryIncrementalDownload() {
    local BINARY_FILE=$1
    local URL=$2
    curl -f -s -C - "${URL}" -o "${BINARY_FILE}" || rc=$?
    # Due to limitations in the current Nexus repo:
    # curl returns 33 when there's a resume attempt with no more bytes to download
    # curl returns 2 after finishing a resumed download
    # with -f curl returns 22 on a 404
    if [ "$rc" = 22 ]; then
        # looks like the requested file doesn't actually exist so stop here
        return 22
    fi
    if [ -z "$rc" ] || [ $rc -eq 33 ] || [ $rc -eq 2 ]; then
        # The checksum validates that RC 33 or 2 are not real failures
        echo "==> File downloaded. Verifying the md5sum..."
        localMd5sum=$(md5sum "${BINARY_FILE}" | awk '{print $1}')
        remoteMd5sum=$(curl -s "${URL}".md5)
        if [ "$localMd5sum" == "$remoteMd5sum" ]; then
            echo "==> Extracting ${BINARY_FILE}..."
            tar xzf ./"${BINARY_FILE}" --overwrite
            echo "==> Done."
            rm -f "${BINARY_FILE}" "${BINARY_FILE}".md5
        else
            echo "Download failed: the local md5sum is different from the remote md5sum. Please try again."
            rm -f "${BINARY_FILE}" "${BINARY_FILE}".md5
            exit 1
        fi
    else
        echo "Failure downloading binaries (curl RC=$rc). Please try again and the download will resume from where it stopped."
        exit 1
    fi
}

# This will attempt to download the .tar.gz all at once, but will trigger the
# binaryIncrementalDownload() function upon a failure, allowing for resume
# if there are network failures.
download() {
    local BINARY_FILE=$1
    local URL=$2
    echo "===> Downloading: " "${URL}"
    curl -L --retry 5 --retry-delay 3 "${URL}" | tar xz || rc=$?
    if [ -n "$rc" ]; then
        echo "==> There was an error downloading the binary file."
        return 22
    else
        echo "==> Done."
    fi
}

pullBinaries() {
    echo "===> Downloading version ${FABRIC_TAG} platform specific fabric binaries"
    download "${BINARY_FILE}" "https://github.com/hyperledger/fabric/releases/download/v${VERSION}/${BINARY_FILE}"
    if [ $? -eq 22 ]; then
        echo
        echo "------> ${FABRIC_TAG} platform specific fabric binary is not available to download <----"
        echo
        exit
    fi

    echo "===> Downloading version ${CA_TAG} platform specific fabric-ca-client binary"
    download "${CA_BINARY_FILE}" "https://github.com/hyperledger/fabric-ca/releases/download/v${CA_VERSION}/${CA_BINARY_FILE}"
    if [ $? -eq 22 ]; then
        echo
        echo "------> ${CA_TAG} fabric-ca-client binary is not available to download  (Available from 1.1.0-rc1) <----"
        echo
        exit
    fi
}

BINARIES=true

# Parse commandline args pull out
# version and/or ca-version strings first
if [ -n "$1" ] && [ "${1:0:1}" != "-" ]; then
    VERSION=$1;shift
    if [ -n "$1" ]  && [ "${1:0:1}" != "-" ]; then
        CA_VERSION=$1;shift
        if [ -n  "$1" ] && [ "${1:0:1}" != "-" ]; then
            THIRDPARTY_IMAGE_VERSION=$1;shift
        fi
    fi
fi

# prior to 1.2.0 architecture was determined by uname -m
if [[ $VERSION =~ ^1\.[0-1]\.* ]]; then
    export FABRIC_TAG=${MARCH}-${VERSION}
    export CA_TAG=${MARCH}-${CA_VERSION}
    export THIRDPARTY_TAG=${MARCH}-${THIRDPARTY_IMAGE_VERSION}
else
    # starting with 1.2.0, multi-arch images will be default
    : "${CA_TAG:="$CA_VERSION"}"
    : "${FABRIC_TAG:="$VERSION"}"
    : "${THIRDPARTY_TAG:="$THIRDPARTY_IMAGE_VERSION"}"
fi

BINARY_FILE=hyperledger-fabric-${ARCH}-${VERSION}.tar.gz
CA_BINARY_FILE=hyperledger-fabric-ca-${ARCH}-${CA_VERSION}.tar.gz

# then parse opts
while getopts "h?dsb" opt; do
    case "$opt" in
        h|\?)
            printHelp
            exit 0
            ;;
        b)  BINARIES=false
            ;;
    esac
done

if [ "$BINARIES" == "true" ]; then
    echo
    echo "Installing Hyperledger Fabric binaries"
    echo
    pullBinaries
fi
