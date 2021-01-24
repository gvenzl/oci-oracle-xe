#!/bin/bash
#
# Since: January, 2021
# Author: gvenzl
# Name: run.sh
# Description: Run the Oracle Database
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

# Stop container when SIGINT or SIGTERM is received
########### stop database helper function ############
function stop_database() {
   echo "CONTAINER: shutdown request received."
   echo "CONTAINER: shutting down database!"
   sqlplus -s / as sysdba <<EOF
      shutdown immediate;
      exit;
EOF
   lsnrctl stop
   echo "CONTAINER: stopping container."
}

# Setup environment variables
function setup_env_vars() {

  declare -g DATABASE_ALREADY_EXISTS

  if [ -d "${ORACLE_BASE}/oradata/dbconfig/${ORACLE_SID}" ]; then
    DATABASE_ALREADY_EXISTS="true";
  else
    # Password is mandatory for first container start
    if [ -z "${ORACLE_PASSWORD:-}" ]; then
      echo "Oracle Database password has to be specified at first database startup."
      echo "Please specify a database password via the \$ORACLE_PASSWORD environment variable, for example, via '-e ORACLE_PASSWORD=password'."
      exit 1;
    fi;
  fi;
}

# Create dbconfig directory structure
function create_dbconfig() {

  mkdir -p "${ORACLE_BASE}/oradata/dbconfig/${ORACLE_SID}"

  mv "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}" "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_HOME}"/network/admin/listener.ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_HOME}"/network/admin/tnsnames.ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_HOME}"/network/admin/sqlnet.ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  
  sym_link_dbconfig
}

# Remove the existing config files inside the image
function remove_config_files()  {
  
  if [ -f "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora ]; then
    rm "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora
  fi;

  if [ -f "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}" ]; then
    rm "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}"
  fi;

  if [ -f "${ORACLE_HOME}"/network/admin/listener.ora ]; then
    rm "${ORACLE_HOME}"/network/admin/listener.ora
  fi;

  if [ -f "${ORACLE_HOME}"/network/admin/tnsnames.ora ]; then
    rm "${ORACLE_HOME}"/network/admin/tnsnames.ora
  fi;

  if [ -f "${ORACLE_HOME}"/network/admin/sqlnet.ora ]; then
    rm "${ORACLE_HOME}"/network/admin/sqlnet.ora
  fi;
}

# Create symbolic links to dbconfig files
function sym_link_dbconfig() {

  if [ ! -L "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/spfile"${ORACLE_SID}".ora "${ORACLE_HOME}"/dbs/spfile"${ORACLE_SID}".ora
  fi;
  
  if [ ! -L "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}" ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/orapw"${ORACLE_SID}" "${ORACLE_HOME}"/dbs/orapw"${ORACLE_SID}"
  fi;
  
  if [ ! -L "${ORACLE_HOME}"/network/admin/listener.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/listener.ora "${ORACLE_HOME}"/network/admin/listener.ora
  fi;

  if [ ! -L "${ORACLE_HOME}"/network/admin/tnsnames.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/tnsnames.ora "${ORACLE_HOME}"/network/admin/tnsnames.ora
  fi;

  if [ ! -L "${ORACLE_HOME}"/network/admin/sqlnet.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/sqlnet.ora "${ORACLE_HOME}"/network/admin/sqlnet.ora
  fi;

}

###########################
###########################
######### M A I N #########
###########################
###########################

# Set SIGINT & SIGTERM handlers
trap stop_database SIGINT SIGTERM

echo "CONTAINER: starting up..."

setup_env_vars

# If database does not yet exist, create directory structure
if [ -z "${DATABASE_ALREADY_EXISTS:-}" ]; then
  echo "CONTAINER: first database startup, initializing..."
  create_dbconfig
# Otherwise check that symlinks are in place
else
  echo "CONTAINER: database already initialized."
  remove_config_files
  sym_link_dbconfig
fi;

# Startup listener and database
echo "CONTAINER: starting up Oracle Database..."
lsnrctl start && \
sqlplus -s / as sysdba << EOF
  startup;
  exit;
EOF

# Set Oracle password if it is passed on (mandatory for first database startup)
if [ -n "${ORACLE_PASSWORD:-}" ]; then
  echo "CONTAINER: Resetting SYS and SYSTEM passwords."
  sqlplus -s / as sysdba << EOF
     ALTER USER SYS    IDENTIFIED BY "${ORACLE_PASSWORD}";
     ALTER USER SYSTEM IDENTIFIED BY "${ORACLE_PASSWORD}";
     exit;
EOF
fi;

echo ""
echo "#########################"
echo "DATABASE IS READY TO USE!"
echo "#########################"
echo ""
echo "##################################################################"
echo "CONTAINER: The following output is now from the alert_${ORACLE_SID}.log file:"
echo "##################################################################"

tail -f "${ORACLE_BASE}"/diag/rdbms/*/"${ORACLE_SID}"/trace/alert_"${ORACLE_SID}".log &
childPID=$!
wait ${childPID}
