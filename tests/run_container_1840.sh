#!/bin/bash
# Since: March, 2021
# Author: gvenzl
# Name: run_container_1840.sh
# Description: Run container test scripts for Oracle DB XE 18.4.0
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

source ./functions.sh

#######################
###### 18c TEST #######
#######################

#######################
##### Image tests #####
#######################
runContainerTest "18.4.0 FULL image" "1840-full" "gvenzl/oracle-xe:18.4.0-full"
runContainerTest "18 FULL image" "18-full" "gvenzl/oracle-xe:18-full"
runContainerTest "FULL image" "full" "gvenzl/oracle-xe:full"

runContainerTest "18.4.0 REGULAR image" "1840" "gvenzl/oracle-xe:18.4.0"
runContainerTest "18 REGULAR image" "18" "gvenzl/oracle-xe:18"
runContainerTest "REGULAR image" "latest" "gvenzl/oracle-xe"

#runContainerTest "18.4.0 SLIM image" "1840-slim" "gvenzl/oracle-xe:18.4.0-slim"
