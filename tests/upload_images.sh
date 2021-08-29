#!/bin/bash
# Since: April, 2021
# Author: gvenzl
# Name: upload_images.sh
# Description: Upload images to registry
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

# Ensure all tags are in place
./all_tag_images.sh

# Upload images
echo "Login to Docker Hub:"
podman login

# Upload latest
echo "Upload latest"
podman push localhost/gvenzl/oracle-xe:latest          docker.io/gvenzl/oracle-xe:latest

# Upload 18c images
echo "Upload 18.4.0-full"
podman push localhost/gvenzl/oracle-xe:18.4.0-full     docker.io/gvenzl/oracle-xe:18.4.0-full
echo "Upload 18-full"
podman push localhost/gvenzl/oracle-xe:18-full         docker.io/gvenzl/oracle-xe:18-full
echo "Upload full"
podman push localhost/gvenzl/oracle-xe:full            docker.io/gvenzl/oracle-xe:full

echo "Upload 18.4.0"
podman push localhost/gvenzl/oracle-xe:18.4.0          docker.io/gvenzl/oracle-xe:18.4.0
echo "Upload 18"
podman push localhost/gvenzl/oracle-xe:18              docker.io/gvenzl/oracle-xe:18

echo "Upload 18.4.0-slim"
podman push localhost/gvenzl/oracle-xe:18.4.0-slim     docker.io/gvenzl/oracle-xe:18.4.0-slim
echo "Upload 18-slim"
podman push localhost/gvenzl/oracle-xe:18-slim         docker.io/gvenzl/oracle-xe:18-slim
echo "Upload slim"
podman push localhost/gvenzl/oracle-xe:slim            docker.io/gvenzl/oracle-xe:slim

# Upload 11g images
echo "Upload 11.2.0.2-full"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-full   docker.io/gvenzl/oracle-xe:11.2.0.2-full
echo "Upload 11-full"
podman push localhost/gvenzl/oracle-xe:11-full         docker.io/gvenzl/oracle-xe:11-full
echo "Upload 11.2.0.2"
podman push localhost/gvenzl/oracle-xe:11.2.0.2        docker.io/gvenzl/oracle-xe:11.2.0.2
echo "Upload 11"
podman push localhost/gvenzl/oracle-xe:11              docker.io/gvenzl/oracle-xe:11
echo "Upload 11.2.0.2-slim"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-slim   docker.io/gvenzl/oracle-xe:11.2.0.2-slim
echo "Upload 11-slim"
podman push localhost/gvenzl/oracle-xe:11-slim         docker.io/gvenzl/oracle-xe:11-slim
