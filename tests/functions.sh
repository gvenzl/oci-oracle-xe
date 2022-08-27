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

    if podman logs ${CONTAINER_NAME} | grep 'DATABASE IS READY TO USE' >/dev/null; then
      return 0;
    fi;

    ((tries++))

  done;

  return 1;
}

# Function: tear_down_container
# Tears down a container
#
# Parameters:
# CONTAINER_NAME: The container name

function tear_down_container {

  echo "Tearing down container";
  echo "";
  podman kill "${1}" >/dev/null
  podman rm -f "${1}" >/dev/null
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
  APP_USER_CMD=""
  APP_USER_PASSWORD_CMD=""
  ORA_PWD_CMD="${ORA_PWD_CMD:--e ORACLE_PASSWORD=LetsTest1}"
  ORACLE_DATABASE_CMD=""

  if [ -n "${APP_USER:-}" ]; then
    APP_USER_CMD="-e APP_USER=${APP_USER}"
  fi;

  if [ -n "${APP_USER_PASSWORD:-}" ]; then
    APP_USER_PASSWORD_CMD="-e APP_USER_PASSWORD=${APP_USER_PASSWORD}"
  fi;

  if [ -n "${ORACLE_DATABASE:-}" ]; then
    ORACLE_DATABASE_CMD="-e ORACLE_DATABASE=${ORACLE_DATABASE}"
  fi;

  echo "TEST ${TEST_NAME}: Started"
  echo ""

  TEST_START_TMS=$(date '+%s')

  # Run and start container
  podman run -d --name ${CONTAINER_NAME} ${ORA_PWD_CMD} ${APP_USER_CMD} ${APP_USER_PASSWORD_CMD} ${ORACLE_DATABASE_CMD} ${IMAGE} >/dev/null

  # Check whether Oracle DB came up successfully
  if checkDB "${CONTAINER_NAME}"; then
    # Only tear down container if $NO_TEAR_DOWN has NOT been specified
    if [ -z "${NO_TEAR_DOWN:-}" ]; then

      TEST_END_TMS=$(date '+%s')
      TEST_DURATION=$(( TEST_END_TMS - TEST_START_TMS ))

      echo "TEST ${TEST_NAME}: OK (${TEST_DURATION} sec)";
      echo "";
      tear_down_container "${CONTAINER_NAME}"
    fi;

    return 0;

  # Test failed
  else
    # Print logs of failed test
    podman logs "${CONTAINER_NAME}";

    echo "";
    echo "TEST ${TEST_NAME}: FAILED!";
    echo "";
    tear_down_container "${CONTAINER_NAME}"

    exit 1;

  fi;
}
