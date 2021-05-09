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
###### 11g TESTS ######
#######################

runContainerTest "11.2.0.2 FULL image" "11202-full" "gvenzl/oracle-xe:11.2.0.2-full"
runContainerTest "11 FULL image" "11-full" "gvenzl/oracle-xe:11-full"

runContainerTest "11.2.0.2 REGULAR image" "11202" "gvenzl/oracle-xe:11.2.0.2"
runContainerTest "11 REGULAR image" "11" "gvenzl/oracle-xe:11"

runContainerTest "11.2.0.2 SLIM image" "11202-slim" "gvenzl/oracle-xe:11.2.0.2-slim"
runContainerTest "11 SLIM image" "11-slim" "gvenzl/oracle-xe:11-slim"

#################################
##### Oracle password tests #####
#################################

# Provide different password
ORA_PWD_CMD="-e ORACLE_PASSWORD=MyTestPassword"
# Tell test method not to tear down container
NO_TEAR_DOWN="true"
# Let's keep the container name in a var to keep it simple
CONTAINER_NAME="11-ora-pwd"
# Let's keep the test name in a var to keep it simple too
TEST_NAME="11 ORACLE_PASSWORD"
# This is what we want to have back from the SQL statement
EXPECTED_RESULT="OK"

# Spin up container
runContainerTest "${TEST_NAME}" "${CONTAINER_NAME}" "gvenzl/oracle-xe:11"

# Test password, if it works we will get "OK" back from the SQL statement
result=$(podman exec -i ${CONTAINER_NAME} sqlplus -s system/MyTestPassword <<EOF
   set heading off;
   set echo off;
   set pagesize 0;
   SELECT '${EXPECTED_RESULT}' FROM dual;
   exit;
EOF
)

# Tear down the container, no longer needed
tear_down_container "${CONTAINER_NAME}"

# See whether we got "OK" back from our test
if [ "${result}" == "${EXPECTED_RESULT}" ]; then
  echo "TEST ${TEST_NAME}: OK";
  echo "";
else
  echo "TEST ${TEST_NAME}: FAILED!";
  exit 1;
fi;

# Clean up environment variables, all tests should remain self-contained
unset CONTAINER_NAME
unset NO_TEAR_DOWN
unset ORA_PWD_CMD
unset TEST_NAME

########################################
##### Oracle random password tests #####
########################################

# We want a random password for this test
ORA_PWD_CMD="-e ORACLE_RANDOM_PASSWORD=sure"
# Tell test method not to tear down container
NO_TEAR_DOWN="true"
# Let's keep the container name in a var to keep it simple
CONTAINER_NAME="11-rand-ora-pwd"
# Let's keep the test name in a var to keep it simple too
TEST_NAME="11 ORACLE_RANDOM_PASSWORD"
# This is what we want to have back from the SQL statement
EXPECTED_RESULT="OK"

# Spin up container
runContainerTest "${TEST_NAME}" "${CONTAINER_NAME}" "gvenzl/oracle-xe:11"

# Let's get the password
rand_pwd=$(podman logs ${CONTAINER_NAME} | grep "ORACLE PASSWORD FOR SYS AND SYSTEM:" | awk '{ print $7 }')

# Test the random password, if it works we will get "OK" back from the SQL statement
result=$(podman exec -i ${CONTAINER_NAME} sqlplus -s system/"${rand_pwd}" <<EOF
   set heading off;
   set echo off;
   set pagesize 0;
   SELECT '${EXPECTED_RESULT}' FROM dual;
   exit;
EOF
)

# Tear down the container, no longer needed
tear_down_container "${CONTAINER_NAME}"

# See whether we got "OK" back from our test
if [ "${result}" == "${EXPECTED_RESULT}" ]; then
  echo "TEST ${TEST_NAME}: OK";
  echo "";
else
  echo "TEST ${TEST_NAME}: FAILED!";
  exit 1;
fi;

# Clean up environment variables, all tests should remain self-contained
unset CONTAINER_NAME
unset NO_TEAR_DOWN
unset ORA_PWD_CMD
unset TEST_NAME
