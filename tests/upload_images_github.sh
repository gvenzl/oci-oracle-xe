#!/bin/bash
# Since: August, 2022
# Author: gvenzl
# Name: upload_images_github.sh
# Description: Upload images to the GitHub registry
#
# Copyright 2022 Gerald Venzl
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
echo "Login to GitHub Container Registry:"
podman login ghcr.io

# Start from old to new, as packages will be sorted by last update/upload time descending

# Upload images

# Upload 11g FULL images
echo "Upload 11.2.0.2-full-faststart"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-full-faststart   ghcr.io/gvenzl/oracle-xe:11.2.0.2-full-faststart
echo "Upload 11-full-faststart"
podman push localhost/gvenzl/oracle-xe:11-full-faststart         ghcr.io/gvenzl/oracle-xe:11-full-faststart
echo "Upload 11.2.0.2-full"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-full             ghcr.io/gvenzl/oracle-xe:11.2.0.2-full
echo "Upload 11-full"
podman push localhost/gvenzl/oracle-xe:11-full                   ghcr.io/gvenzl/oracle-xe:11-full


# Upload 11g images
echo "Upload 11.2.0.2-faststart"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-faststart        ghcr.io/gvenzl/oracle-xe:11.2.0.2-faststart
echo "Upload 11-faststart"
podman push localhost/gvenzl/oracle-xe:11-faststart              ghcr.io/gvenzl/oracle-xe:11-faststart
echo "Upload 11.2.0.2"
podman push localhost/gvenzl/oracle-xe:11.2.0.2                  ghcr.io/gvenzl/oracle-xe:11.2.0.2
echo "Upload 11"
podman push localhost/gvenzl/oracle-xe:11                        ghcr.io/gvenzl/oracle-xe:11


# Upload 11g SLIM
echo "Upload 11.2.0.2-slim-faststart"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-slim-faststart   ghcr.io/gvenzl/oracle-xe:11.2.0.2-slim-faststart
echo "Upload 11-slim-faststart"
podman push localhost/gvenzl/oracle-xe:11-slim-faststart         ghcr.io/gvenzl/oracle-xe:11-slim-faststart
echo "Upload 11.2.0.2-slim"
podman push localhost/gvenzl/oracle-xe:11.2.0.2-slim             ghcr.io/gvenzl/oracle-xe:11.2.0.2-slim
echo "Upload 11-slim"
podman push localhost/gvenzl/oracle-xe:11-slim                   ghcr.io/gvenzl/oracle-xe:11-slim




# Upload 18c FULL images
echo "Upload 18.4.0-full-faststart"
podman push localhost/gvenzl/oracle-xe:18.4.0-full-faststart     ghcr.io/gvenzl/oracle-xe:18.4.0-full-faststart
echo "Upload 18-full-faststart"
podman push localhost/gvenzl/oracle-xe:18-full-faststart         ghcr.io/gvenzl/oracle-xe:18-full-faststart
echo "Upload 18.4.0-full"
podman push localhost/gvenzl/oracle-xe:18.4.0-full               ghcr.io/gvenzl/oracle-xe:18.4.0-full
echo "Upload 18-full"
podman push localhost/gvenzl/oracle-xe:18-full                   ghcr.io/gvenzl/oracle-xe:18-full


# Upload 18c images
echo "Upload 18.4.0-faststart"
podman push localhost/gvenzl/oracle-xe:18.4.0-faststart          ghcr.io/gvenzl/oracle-xe:18.4.0-faststart
echo "Upload 18-faststart"
podman push localhost/gvenzl/oracle-xe:18-faststart              ghcr.io/gvenzl/oracle-xe:18-faststart
echo "Upload 18.4.0"
podman push localhost/gvenzl/oracle-xe:18.4.0                    ghcr.io/gvenzl/oracle-xe:18.4.0
echo "Upload 18"
podman push localhost/gvenzl/oracle-xe:18                        ghcr.io/gvenzl/oracle-xe:18


# Upload 18c SLIM images
echo "Upload 18.4.0-slim-faststart"
podman push localhost/gvenzl/oracle-xe:18.4.0-slim-faststart     ghcr.io/gvenzl/oracle-xe:18.4.0-slim-faststart
echo "Upload 18-slim-faststart"
podman push localhost/gvenzl/oracle-xe:18-slim-faststart         ghcr.io/gvenzl/oracle-xe:18-slim-faststart
echo "Upload 18.4.0-slim"
podman push localhost/gvenzl/oracle-xe:18.4.0-slim               ghcr.io/gvenzl/oracle-xe:18.4.0-slim
echo "Upload 18-slim"
podman push localhost/gvenzl/oracle-xe:18-slim                   ghcr.io/gvenzl/oracle-xe:18-slim




# Upload 21c FULL images
echo "Upload 21.3.0-full-faststart"
podman push localhost/gvenzl/oracle-xe:21.3.0-full-faststart     ghcr.io/gvenzl/oracle-xe:21.3.0-full-faststart
echo "Upload 21-full-faststart"
podman push localhost/gvenzl/oracle-xe:21-full-faststart         ghcr.io/gvenzl/oracle-xe:21-full-faststart
echo "Upload 21.3.0-full"
podman push localhost/gvenzl/oracle-xe:21.3.0-full               ghcr.io/gvenzl/oracle-xe:21.3.0-full
echo "Upload 21-full"
podman push localhost/gvenzl/oracle-xe:21-full                   ghcr.io/gvenzl/oracle-xe:21-full


#Upload 21c images
echo "Upload 21.3.0-faststart"
podman push localhost/gvenzl/oracle-xe:21.3.0-faststart          ghcr.io/gvenzl/oracle-xe:21.3.0-faststart
echo "Upload 21-faststart"
podman push localhost/gvenzl/oracle-xe:21-faststart              ghcr.io/gvenzl/oracle-xe:21-faststart
echo "Upload 21.3.0"
podman push localhost/gvenzl/oracle-xe:21.3.0                    ghcr.io/gvenzl/oracle-xe:21.3.0
echo "Upload 21"
podman push localhost/gvenzl/oracle-xe:21                        ghcr.io/gvenzl/oracle-xe:21


# Upload 21c SLIM images
echo "Upload 21.3.0-slim-faststart"
podman push localhost/gvenzl/oracle-xe:21.3.0-slim-faststart     ghcr.io/gvenzl/oracle-xe:21.3.0-slim-faststart
echo "Upload 21-slim-faststart"
podman push localhost/gvenzl/oracle-xe:21-slim-faststart         ghcr.io/gvenzl/oracle-xe:21-slim-faststart
echo "Upload 21c SLIM"
podman push localhost/gvenzl/oracle-xe:21.3.0-slim               ghcr.io/gvenzl/oracle-xe:21.3.0-slim
echo "Upload 21-slim"
podman push localhost/gvenzl/oracle-xe:21-slim                   ghcr.io/gvenzl/oracle-xe:21-slim




# Upload FULL images
echo "Upload full-faststart"
podman push localhost/gvenzl/oracle-xe:full-faststart            ghcr.io/gvenzl/oracle-xe:full-faststart
echo "Upload full"
podman push localhost/gvenzl/oracle-xe:full                      ghcr.io/gvenzl/oracle-xe:full





# Upload SLIM images
echo "Upload slim-faststart"
podman push localhost/gvenzl/oracle-xe:slim-faststart            ghcr.io/gvenzl/oracle-xe:slim-faststart
echo "Upload slim"
podman push localhost/gvenzl/oracle-xe:slim                      ghcr.io/gvenzl/oracle-xe:slim




# Upload latest
echo "Upload latest-faststart"
podman push localhost/gvenzl/oracle-xe:latest-faststart          ghcr.io/gvenzl/oracle-xe:latest-faststart
echo "Upload latest"
podman push localhost/gvenzl/oracle-xe:latest                    ghcr.io/gvenzl/oracle-xe:latest
