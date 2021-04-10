#!/bin/bash
# Since: January, 2021
# Author: gvenzl
# Name: functions.sh
# Description: Helper functions for test scripts
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

# Function: checkDB
# Checks whether the Oracle DB is up and running.
#
# Parameters:
# CONTAINER_NAME: The name of the podman container

function checkDB {

  CONTAINER_NAME="${1}"
  
  tries=0
  max_tries=12
  sleep_time_secs=10
  
  # Wait until container is ready
  while [ ${tries} -lt ${max_tries} ]; do
    # Sleep until DB is up and running
    sleep ${sleep_time_secs};
    
    # Is the database ready for use?
    podman logs ${CONTAINER_NAME} | grep 'DATABASE IS READY TO USE' >/dev/null;
    if [ "$?" == "0" ]; then
      return 0;
    fi;

    ((tries++))

  done;

  return 1;
}

# Function: run_container_test
# Runs a container (podman run) test
#
# Parameters:
# TEST_NAME: The test name
# CONTAINER_NAME: The container name
# IMAGE: The image to start the container from

function runContainerTest {
  TEST_NAME="${1}"
  CONTAINER_NAME="${2}"
  IMAGE="${3}"

  echo "TEST ${TEST_NAME}: Started"
  echo ""
  
  # Run and start container
  podman run -d --name "${CONTAINER_NAME}" -e ORACLE_PASSWORD=LetsTest1 "${IMAGE}"
  
  # Check whether Oracle DB came up successfully
  checkDB "${CONTAINER_NAME}"
  TEST_OK=$?
  
  if [ "${TEST_OK}" != "0" ]; then
    # Print logs of failed test
    podman logs "${CONTAINER_NAME}";

    echo "";
    echo "TEST ${TEST_NAME}: FAILED!";
    echo "";

    podman rm -f "${CONTAINER_NAME}"

    exit 1;
  else
    echo "TEST ${TEST_NAME}: OK";
    echo "";

    podman rm -f "${CONTAINER_NAME}"

    return 0;
  fi;

}