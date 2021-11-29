#!/bin/bash
# Since: April, 2021
# Author: gvenzl
# Name: upload_images_artifactory.sh
# Description: Upload images to Artifactory
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

# Upload images
echo "Login to Artifactory:"
podman login gvenzl.jfrog.io

# Upload latest
echo "Upload latest"
podman push gvenzl/oracle-xe:latest          gvenzl.jfrog.io/docker/oracle-xe:latest

# Upload 21c images
echo "Upload 21.3.0-full"
podman push gvenzl/oracle-xe:21.3.0-full     gvenzl.jfrog.io/docker/oracle-xe:21.3.0-full
echo "Upload 21-full"
podman push gvenzl/oracle-xe:21-full         gvenzl.jfrog.io/docker/oracle-xe:21-full
echo "Upload full"
podman push gvenzl/oracle-xe:full            gvenzl.jfrog.io/docker/oracle-xe:full

echo "Upload 21.3.0"
podman push gvenzl/oracle-xe:21.3.0          gvenzl.jfrog.io/docker/oracle-xe:21.3.0
echo "Upload 21"
podman push gvenzl/oracle-xe:21              gvenzl.jfrog.io/docker/oracle-xe:21

echo "Upload 21.3.0-slim"
podman push gvenzl/oracle-xe:21.3.0-slim     gvenzl.jfrog.io/docker/oracle-xe:21.3.0-slim
echo "Upload 21-slim"
podman push gvenzl/oracle-xe:21-slim         gvenzl.jfrog.io/docker/oracle-xe:21-slim
echo "Upload slim"
podman push gvenzl/oracle-xe:slim            gvenzl.jfrog.io/docker/oracle-xe:slim


# Upload 18c images
echo "Upload 18.4.0-full"
podman push gvenzl/oracle-xe:18.4.0-full     gvenzl.jfrog.io/docker/oracle-xe:18.4.0-full
echo "Upload 18-full"
podman push gvenzl/oracle-xe:18-full         gvenzl.jfrog.io/docker/oracle-xe:18-full

echo "Upload 18.4.0"
podman push gvenzl/oracle-xe:18.4.0          gvenzl.jfrog.io/docker/oracle-xe:18.4.0
echo "Upload 18"
podman push gvenzl/oracle-xe:18              gvenzl.jfrog.io/docker/oracle-xe:18

echo "Upload 18.4.0-slim"
podman push gvenzl/oracle-xe:18.4.0-slim     gvenzl.jfrog.io/docker/oracle-xe:18.4.0-slim
echo "Upload 18-slim"
podman push gvenzl/oracle-xe:18-slim         gvenzl.jfrog.io/docker/oracle-xe:18-slim

# Upload 11g images
echo "Upload 11.2.0.2-full"
podman push gvenzl/oracle-xe:11.2.0.2-full   gvenzl.jfrog.io/docker/oracle-xe:11.2.0.2-full
echo "Upload 11-full"
podman push gvenzl/oracle-xe:11-full         gvenzl.jfrog.io/docker/oracle-xe:11-full
echo "Upload 11.2.0.2"
podman push gvenzl/oracle-xe:11.2.0.2        gvenzl.jfrog.io/docker/oracle-xe:11.2.0.2
echo "Upload 11"
podman push gvenzl/oracle-xe:11              gvenzl.jfrog.io/docker/oracle-xe:11
echo "Upload 11.2.0.2-slim"
podman push gvenzl/oracle-xe:11.2.0.2-slim   gvenzl.jfrog.io/docker/oracle-xe:11.2.0.2-slim
echo "Upload 11-slim"
podman push gvenzl/oracle-xe:11-slim         gvenzl.jfrog.io/docker/oracle-xe:11-slim
