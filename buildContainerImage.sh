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

VERSION="11.2.0.2"
FLAVOR="NORMAL"
IMAGE_NAME="gvenzl/oracle-xe"

function usage() {
    cat << EOF

Usage: buildContainerImage.sh [-f | -n | -s] [-v version] [-o] [container build option]
Builds a container image for Oracle Database XE.

Parameters:
   -f: creates a 'full' image
   -n: creates a normal image (default)
   -s: creates a 'slim' image
   -v: version of Oracle Database XE to build
       Choose one of: 11.2.0.2, 18.4.0
   -o: passes on container build option

* select only one flavor: -f, -n, or -s

Apache License, Version 2.0

Copyright (c) 2021 Gerald Venzl

EOF

}

while getopts "hfnsv:o:" optname; do
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
    "n")
      FLAVOR="NORMAL"
      ;;
    "s")
      FLAVOR="SLIM"
      ;;
    "o")
      eval "BUILD_OPTS=(${OPTARG})"
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

SHASUM_RET=$(shasum -a 256 oracle-xe*.rpm)
if [ "${VERSION}" == "11.2.0.2" ] && [ "${SHASUM_RET%% *}" != "6629c8f014402fbc9db844421a6a0d2c71580838f4ac0e8df6659b62bb905268" ]; then
  echo "BUILDER: WARNING! SHA sum of RPM does not match with what's expected!"
  echo "BUILDER: WARNING! Verify that the .rpm file is not corrupt!"
fi;

IMAGE_NAME="${IMAGE_NAME}:${VERSION}"

if [ "${FLAVOR}" != "NORMAL" ]; then
  IMAGE_NAME="${IMAGE_NAME}-${FLAVOR,,}"
fi;

echo "BUILDER: building image $IMAGE_NAME"

buildah bud -f Dockerfile."${VERSION//./}" -t "${IMAGE_NAME}" --build-arg BUILD_MODE="${FLAVOR}"
