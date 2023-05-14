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

# Log into Docker Hub before anything else so that one does not have to
# wait for the backup to be finished)
echo "Login to Docker Hub:"
podman login docker.io

# Ensure all tags are in place
./all_tag_images.sh

# Backup images
read -r -p "Do you want to backup the old images? [Y/n]: " response
# Default --> "Y"
response=${response:-Y}
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  ./backup_old_images.sh
fi;

# Upload images


# Upload 11g FULL images
echo "Upload 11.2.0.2-full-faststart"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-full-faststart   docker.io/gvenzl/oracle-xe:11.2.0.2-full-faststart
echo "Upload 11-full-faststart"
podman push localhost/gvenzl/oracle-xe:11-full-faststart         docker.io/gvenzl/oracle-xe:11-full-faststart
echo "Upload 11.2.0.2-full"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-full             docker.io/gvenzl/oracle-xe:11.2.0.2-full
echo "Upload 11-full"
podman push localhost/gvenzl/oracle-xe:11-full                   docker.io/gvenzl/oracle-xe:11-full


# Upload 11g images
echo "Upload 11.2.0.2-faststart"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-faststart        docker.io/gvenzl/oracle-xe:11.2.0.2-faststart
echo "Upload 11-faststart"
podman push localhost/gvenzl/oracle-xe:11-faststart              docker.io/gvenzl/oracle-xe:11-faststart
echo "Upload 11.2.0.2"
podman push localhost/gvenzl/oracle-xe:11.2.0.2                  docker.io/gvenzl/oracle-xe:11.2.0.2
echo "Upload 11"
podman push localhost/gvenzl/oracle-xe:11                        docker.io/gvenzl/oracle-xe:11


# Upload 11g SLIM images
echo "Upload 11.2.0.2-slim-faststart"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-slim-faststart   docker.io/gvenzl/oracle-xe:11.2.0.2-slim-faststart
echo "Upload 11-slim-faststart"
podman push localhost/gvenzl/oracle-xe:11-slim-faststart         docker.io/gvenzl/oracle-xe:11-slim-faststart
echo "Upload 11.2.0.2-slim"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-slim             docker.io/gvenzl/oracle-xe:11.2.0.2-slim
echo "Upload 11-slim"
podman push localhost/gvenzl/oracle-xe:11-slim                   docker.io/gvenzl/oracle-xe:11-slim




# Upload 18c FULL images
echo "Upload 18.4.0-full-faststart"
podman push localhost/gvenzl/oracle-xe:18.4.0-full-faststart     docker.io/gvenzl/oracle-xe:18.4.0-full-faststart
echo "Upload 18-full-faststart"
podman push localhost/gvenzl/oracle-xe:18-full-faststart         docker.io/gvenzl/oracle-xe:18-full-faststart
echo "Upload 18.4.0-full"
podman push localhost/gvenzl/oracle-xe:18.4.0-full               docker.io/gvenzl/oracle-xe:18.4.0-full
echo "Upload 18-full"
podman push localhost/gvenzl/oracle-xe:18-full                   docker.io/gvenzl/oracle-xe:18-full


# Upload 18c images
echo "Upload 18.4.0-faststart"
podman push localhost/gvenzl/oracle-xe:18.4.0-faststart          docker.io/gvenzl/oracle-xe:18.4.0-faststart
echo "Upload 18-faststart"
podman push localhost/gvenzl/oracle-xe:18-faststart              docker.io/gvenzl/oracle-xe:18-faststart
echo "Upload 18.4.0"
podman push localhost/gvenzl/oracle-xe:18.4.0                    docker.io/gvenzl/oracle-xe:18.4.0
echo "Upload 18"
podman push localhost/gvenzl/oracle-xe:18                        docker.io/gvenzl/oracle-xe:18


# Upload 18c SLIM
echo "Upload 18.4.0-slim-faststart"
podman push localhost/gvenzl/oracle-xe:18.4.0-slim-faststart     docker.io/gvenzl/oracle-xe:18.4.0-slim-faststart
echo "Upload 18-slim-faststart"
podman push localhost/gvenzl/oracle-xe:18-slim-faststart         docker.io/gvenzl/oracle-xe:18-slim-faststart
echo "Upload 18.4.0-slim"
podman push localhost/gvenzl/oracle-xe:18.4.0-slim               docker.io/gvenzl/oracle-xe:18.4.0-slim
echo "Upload 18-slim"
podman push localhost/gvenzl/oracle-xe:18-slim                   docker.io/gvenzl/oracle-xe:18-slim




# Upload 21c FULL images
echo "Upload 21.3.0-full-faststart"
podman push localhost/gvenzl/oracle-xe:21.3.0-full-faststart     docker.io/gvenzl/oracle-xe:21.3.0-full-faststart
echo "Upload 21-full-faststart"
podman push localhost/gvenzl/oracle-xe:21-full-faststart         docker.io/gvenzl/oracle-xe:21-full-faststart
echo "Upload 21.3.0-full"
podman push localhost/gvenzl/oracle-xe:21.3.0-full               docker.io/gvenzl/oracle-xe:21.3.0-full
echo "Upload 21-full"
podman push localhost/gvenzl/oracle-xe:21-full                   docker.io/gvenzl/oracle-xe:21-full


# Upload 21c images
echo "Upload 21.3.0-faststart"
podman push localhost/gvenzl/oracle-xe:21.3.0-faststart          docker.io/gvenzl/oracle-xe:21.3.0-faststart
echo "Upload 21-faststart"
podman push localhost/gvenzl/oracle-xe:21-faststart              docker.io/gvenzl/oracle-xe:21-faststart
echo "Upload 21.3.0"
podman push localhost/gvenzl/oracle-xe:21.3.0                    docker.io/gvenzl/oracle-xe:21.3.0
echo "Upload 21"
podman push localhost/gvenzl/oracle-xe:21                        docker.io/gvenzl/oracle-xe:21


# Upload 21c SLIM images
echo "Upload 21.3.0-slim-faststart"
podman push localhost/gvenzl/oracle-xe:21.3.0-slim-faststart     docker.io/gvenzl/oracle-xe:21.3.0-slim-faststart
echo "Upload 21-slim-faststart"
podman push localhost/gvenzl/oracle-xe:21-slim-faststart         docker.io/gvenzl/oracle-xe:21-slim-faststart
echo "Upload 21.3.0-slim"
podman push localhost/gvenzl/oracle-xe:21.3.0-slim               docker.io/gvenzl/oracle-xe:21.3.0-slim
echo "Upload 21-slim"
podman push localhost/gvenzl/oracle-xe:21-slim                   docker.io/gvenzl/oracle-xe:21-slim




# Upload FULL images
echo "Upload full-faststart"
podman push localhost/gvenzl/oracle-xe:full-faststart            docker.io/gvenzl/oracle-xe:full-faststart
echo "Upload full"
podman push localhost/gvenzl/oracle-xe:full                      docker.io/gvenzl/oracle-xe:full




# Upload SLIM image
echo "Upload slim-faststart"
podman push localhost/gvenzl/oracle-xe:slim-faststart            docker.io/gvenzl/oracle-xe:slim-faststart
echo "Upload slim"
podman push localhost/gvenzl/oracle-xe:slim                      docker.io/gvenzl/oracle-xe:slim




# Upload latest
echo "Upload latest-faststart"
podman push localhost/gvenzl/oracle-xe:latest-faststart          docker.io/gvenzl/oracle-xe:latest-faststart
echo "Upload latest"
podman push localhost/gvenzl/oracle-xe:latest                    docker.io/gvenzl/oracle-xe:latest
