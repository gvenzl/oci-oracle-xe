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
podman push gvenzl/oracle-xe:latest

# Upload 18c images
podman push gvenzl/oracle-xe:18.4.0-full
podman push gvenzl/oracle-xe:18-full
podman push gvenzl/oracle-xe:full

podman push gvenzl/oracle-xe:18.4.0
podman push gvenzl/oracle-xe:18

# Upload 11g images
podman push gvenzl/oracle-xe:11.2.0.2-full
podman push gvenzl/oracle-xe:11-full
podman push gvenzl/oracle-xe:11.2.0.2
podman push gvenzl/oracle-xe:11
podman push gvenzl/oracle-xe:11.2.0.2-slim
podman push gvenzl/oracle-xe:11-slim
