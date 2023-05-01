#!/bin/bash
# Since: January, 2021
# Author: gvenzl
# Name: buildContainerImage.sh
# Description: Build a Container image
#
# Copyright 2021 Gerald Venzl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Exit on errors
# Great explanation on https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -Eeuo pipefail

VERSION="21.3.0"
FLAVOR="REGULAR"
IMAGE_NAME="gvenzl/oracle-xe"
SKIP_CHECKSUM="false"
FASTSTART="false"
BASE_IMAGE=""

function usage() {
    cat << EOF

Usage: buildContainerImage.sh [-f | -r | -s] [-x] [-v version] [-i] [-o] [container build option]
Builds a container image for Oracle Database XE.

Parameters:
   -f: creates a 'full' image
   -r: creates a regular image (default)
   -s: creates a 'slim' image
   -x: creates a 'faststart' image
   -v: version of Oracle Database XE to build
       Choose one of: 21.3.0, 18.4.0, 11.2.0.2
   -i: ignores checksum test
   -o: passes on container build option

* select only one flavor: -f, -r, or -s

Apache License, Version 2.0

Copyright (c) 2021 Gerald Venzl

EOF

}

while getopts "hfnsv:io:x" optname; do
  case "${optname}" in
    "h")
      usage
      exit 0;
      ;;
    "v")
      VERSION="${OPTARG}"
      ;;
    "f")
      FLAVOR="FULL"
      ;;
    "r")
      FLAVOR="REGULAR"
      ;;
    "s")
      FLAVOR="SLIM"
      ;;
    "i")
      SKIP_CHECKSUM="true"
      ;;
    "o")
      eval "BUILD_OPTS=(${OPTARG})"
      ;;
    "x")
      FASTSTART="true"
      ;;
    "?")
      usage;
      exit 1;
      ;;
    *)
    # Should not occur
      echo "Unknown error while processing options inside buildContainerImage.sh"
      ;;
  esac;
done;

# Checking SHASUM
if [ "${SKIP_CHECKSUM}" == "false" ]; then

  echo "BUILDER: verifying checksum of rpm file - please wait..."

  SHASUM_RET=$(shasum -a 256 oracle*xe*"${VERSION%%.*}"*.rpm)

  if [[ ( "${VERSION}" == "11.2.0.2"  &&  "${SHASUM_RET%% *}" != "6629c8f014402fbc9db844421a6a0d2c71580838f4ac0e8df6659b62bb905268" ) ||
        ( "${VERSION}" == "18.4.0"    &&  "${SHASUM_RET%% *}" != "4df0318d72a0b97f5468b36919a23ec07533f5897b324843108e0376566d50c8" ) ||
        ( "${VERSION}" == "21.3.0"    &&  "${SHASUM_RET%% *}" != "f8357b432de33478549a76557e8c5220ec243710ed86115c65b0c2bc00a848db" ) ]]; then
    echo "BUILDER: WARNING! SHA sum of RPM does not match with what's expected!"
    echo "BUILDER: WARNING! Verify that the .rpm file is not corrupt!"
  fi;

  echo "BUILDER: checksum verification done"
else
  echo "BUILDER: checksum verification ignored"
fi;

# Set Dockerfile name
DOCKER_FILE="Dockerfile.${VERSION//./}"

# Give image base tag
IMAGE_NAME="${IMAGE_NAME}:${VERSION}"

# Add image flavor to the tag (regular has no tag)
if [ "${FLAVOR}" != "REGULAR" ]; then
  IMAGE_NAME="${IMAGE_NAME}-${FLAVOR,,}"
fi;

# Add faststart tag to image and set Dockerfile
if [ "${FASTSTART}" == "true" ]; then
  BASE_IMAGE="${IMAGE_NAME}"
  IMAGE_NAME="${IMAGE_NAME}-faststart"
  DOCKER_FILE="Dockerfile.faststart"
fi;

echo "BUILDER: building image $IMAGE_NAME"

BUILD_START_TMS=$(date '+%s')

buildah bud -f "$DOCKER_FILE" -t "${IMAGE_NAME}" --build-arg BUILD_MODE="${FLAVOR}" --build-arg BASE_IMAGE="${BASE_IMAGE}"

BUILD_END_TMS=$(date '+%s')
BUILD_DURATION=$(( BUILD_END_TMS - BUILD_START_TMS ))

echo "Build of container image ${IMAGE_NAME} completed in ${BUILD_DURATION} seconds."
