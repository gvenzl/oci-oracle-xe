#!/bin/bash
# Since: January, 2021
# Author: gvenzl
# Name: run_container_11202.sh
# Description: Run container test scripts for Oracle DB XE 11.2.0.2
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
####### 11g TEST ######
#######################

runContainerTest "11.2.0.2 FULL image" "11202-full" "gvenzl/oracle-xe:11.2.0.2-full"
runContainerTest "11 FULL image" "11-full" "gvenzl/oracle-xe:11-full"

runContainerTest "11.2.0.2 REGULAR image" "11202" "gvenzl/oracle-xe:11.2.0.2"
runContainerTest "11 REGULAR image" "11" "gvenzl/oracle-xe:11"

runContainerTest "11.2.0.2 SLIM image" "11202-slim" "gvenzl/oracle-xe:11.2.0.2-slim"
runContainerTest "11 SLIM image" "11-slim" "gvenzl/oracle-xe:11-slim"
