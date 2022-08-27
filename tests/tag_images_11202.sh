#!/bin/bash
# Since: April, 2021
# Author: gvenzl
# Name: tag_images_11202.sh
# Description: Tag all 11g images
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

# Tag 11g images
podman tag gvenzl/oracle-xe:11.2.0.2-full gvenzl/oracle-xe:11-full
podman tag gvenzl/oracle-xe:11.2.0.2-full-faststart gvenzl/oracle-xe:11-full-faststart
podman tag gvenzl/oracle-xe:11.2.0.2 gvenzl/oracle-xe:11
podman tag gvenzl/oracle-xe:11.2.0.2-faststart gvenzl/oracle-xe:11-faststart
podman tag gvenzl/oracle-xe:11.2.0.2-slim gvenzl/oracle-xe:11-slim
podman tag gvenzl/oracle-xe:11.2.0.2-slim-faststart gvenzl/oracle-xe:11-slim-faststart
