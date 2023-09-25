#!/bin/bash
#
# Since: January, 2021
# Author: gvenzl
# Name: container-entrypoint.sh
# Description: The entrypoint script for the container.
#              Parameter 1: "--nowait" exits the script instead of tailing the alert.log
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

NOWAIT="${1:-}"

# Stop container when SIGINT or SIGTERM is received
########### stop database helper function ############
function stop_database() {
  echo "CONTAINER: shutdown request received."
  echo "CONTAINER: shutting down database!"

  lsnrctl stop
  sqlplus -s / as sysdba <<EOF
     -- Exit on any errors
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     shutdown immediate;
     exit;
EOF
   echo "CONTAINER: stopping container."
}

# Retrieve value from ENV[_FILE] variable
# usage: file_env VARIABLE NAME [DEFAULT VALUE]
#    ie: file_env 'ORACLE_PASSWORD' 'example'
# (will allow for "$ORACLE_PASSWORD_FILE" to fill in the value of
#  "$ORACLE_PASSWORD" from a file, especially for container secrets feature)
file_env() {

  # Get name of variable
  local variable="${1}"
  # Get name of variable_FILE
  local file_variable="${variable}_FILE"

  # If both variable and file_variable are specified, throw error and abort
  if [ -n "${!variable:-}" ] && [ -n "${!file_variable:-}" ]; then
    echo "Both \$${variable} and \$${file_variable} are specified but are mutually exclusive."
    echo "Please specify only one of these variables."
    exit 1;
  fi;

  # Set value to default value, if any
  local value="${2:-}"

  # Read value of variable, if any
  if [ -n "${!variable:-}" ]; then
    value="${!variable}"
  # Read value of variable_FILE, if any
  elif [ -n "${!file_variable:-}" ]; then
    value="$(< "${!file_variable}")"
  fi

  export "${variable}"="${value}"
}

# Setup environment variables
function setup_env_vars() {

  declare -g DATABASE_ALREADY_EXISTS

  ORACLE_VERSION=$(sqlplus -version | grep "Release" | awk '{ print $3 }')
  declare -g ORACLE_VERSION

  if [ -d "${ORACLE_BASE}/oradata/dbconfig/${ORACLE_SID}" ]; then
    DATABASE_ALREADY_EXISTS="true";
  else

    # Variable is only supported for >=18c
    if [[ "${ORACLE_VERSION}" = "11.2"* ]]; then
      unset "ORACLE_DATABASE"
    else
      # Allow for ORACLE_DATABASE or ORACLE_DATABASE_FILE
      file_env "ORACLE_DATABASE"
    fi;

    # Allow for ORACLE_PASSWORD or ORACLE_PASSWORD_FILE
    file_env "ORACLE_PASSWORD"

    # Password is mandatory for first container start
    if [ -z "${ORACLE_PASSWORD:-}" ] && [ -z "${ORACLE_RANDOM_PASSWORD:-}" ]; then
      echo "Oracle Database SYS and SYSTEM passwords have to be specified at first database startup."
      echo "Please specify a password either via the \$ORACLE_PASSWORD variable, e.g. '-e ORACLE_PASSWORD=<password>'"
      echo "or set the \$ORACLE_RANDOM_PASSWORD environment variable to any value, e.g. '-e ORACLE_RANDOM_PASSWORD=yes'."
      exit 1;
    # ORACLE_PASSWORD and ORACLE_RANDOM_PASSWORD are mutually exclusive
    elif [ -n "${ORACLE_PASSWORD:-}" ] && [ -n "${ORACLE_RANDOM_PASSWORD:-}" ]; then
      echo "Both \$ORACLE_RANDOM_PASSWORD and \$ORACLE_PASSWORD[_FILE] are specified but are mutually exclusive."
      echo "Please specify only one of these variables."
      exit 1;
    fi;

    # Allow for APP_USER_PASSWORD or APP_USER_PASSWORD_FILE
    file_env "APP_USER_PASSWORD"

    # Check whether both variables have been specified.
    if [ -n "${APP_USER:-}" ] && [ -z "${APP_USER_PASSWORD}" ]; then
      echo "\$APP_USER has been specified without \$APP_USER_PASSWORD[_FILE]."
      echo "Both variables are required, please specify \$APP_USER and \$APP_USER_PASSWORD[_FILE]."
      exit 1;
    elif [ -n "${APP_USER_PASSWORD:-}" ] && [ -z "${APP_USER:-}" ]; then
      echo "\$APP_USER_PASSWORD[_FILE] has been specified without \$APP_USER."
      echo "Both variables are required, please specify \$APP_USER and \$APP_USER_PASSWORD[_FILE]."
      exit 1;
    fi;
  fi;
}

# Create dbconfig directory structure
function create_dbconfig() {

  if [ -f "${ORACLE_BASE}"/"${ORACLE_SID}".7z ]; then
     echo "CONTAINER: uncompressing database data files, please wait..."
     EXTRACT_START_TMS=$(date '+%s')
     7zzs x "${ORACLE_BASE}"/"${ORACLE_SID}".7z -o"${ORACLE_BASE}"/oradata/ > /dev/null
     EXTRACT_END_TMS=$(date '+%s')
     EXTRACT_DURATION=$(( EXTRACT_END_TMS - EXTRACT_START_TMS ))
     echo "CONTAINER: done uncompressing database data files, duration: ${EXTRACT_DURATION} seconds."
     rm "${ORACLE_BASE}"/"${ORACLE_SID}".7z
  fi;

  mkdir -p "${ORACLE_BASE}/oradata/dbconfig/${ORACLE_SID}"

  mv "${ORACLE_BASE_CONFIG}"/dbs/spfile"${ORACLE_SID}".ora "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_BASE_CONFIG}"/dbs/orapw"${ORACLE_SID}"      "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_BASE_HOME}"/network/admin/listener.ora      "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_BASE_HOME}"/network/admin/tnsnames.ora      "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  mv "${ORACLE_BASE_HOME}"/network/admin/sqlnet.ora        "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/
  
  sym_link_dbconfig
}

# Remove the existing config files inside the image
function remove_config_files()  {
  
  if [ -f "${ORACLE_BASE_CONFIG}"/dbs/spfile"${ORACLE_SID}".ora ]; then
    rm "${ORACLE_BASE_CONFIG}"/dbs/spfile"${ORACLE_SID}".ora
  fi;

  if [ -f "${ORACLE_BASE_CONFIG}"/dbs/orapw"${ORACLE_SID}" ]; then
    rm "${ORACLE_BASE_CONFIG}"/dbs/orapw"${ORACLE_SID}"
  fi;

  if [ -f "${ORACLE_BASE_HOME}"/network/admin/listener.ora ]; then
    rm "${ORACLE_BASE_HOME}"/network/admin/listener.ora
  fi;

  if [ -f "${ORACLE_BASE_HOME}"/network/admin/tnsnames.ora ]; then
    rm "${ORACLE_BASE_HOME}"/network/admin/tnsnames.ora
  fi;

  if [ -f "${ORACLE_BASE_HOME}"/network/admin/sqlnet.ora ]; then
    rm "${ORACLE_BASE_HOME}"/network/admin/sqlnet.ora
  fi;
}

# Create symbolic links to dbconfig files
function sym_link_dbconfig() {

  if [ ! -L "${ORACLE_BASE_CONFIG}"/dbs/spfile"${ORACLE_SID}".ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/spfile"${ORACLE_SID}".ora "${ORACLE_BASE_CONFIG}"/dbs/spfile"${ORACLE_SID}".ora
  fi;
  
  if [ ! -L "${ORACLE_BASE_CONFIG}"/dbs/orapw"${ORACLE_SID}" ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/orapw"${ORACLE_SID}" "${ORACLE_BASE_CONFIG}"/dbs/orapw"${ORACLE_SID}"
  fi;
  
  if [ ! -L "${ORACLE_BASE_HOME}"/network/admin/listener.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/listener.ora "${ORACLE_BASE_HOME}"/network/admin/listener.ora
  fi;

  if [ ! -L "${ORACLE_BASE_HOME}"/network/admin/tnsnames.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/tnsnames.ora "${ORACLE_BASE_HOME}"/network/admin/tnsnames.ora
  fi;

  if [ ! -L "${ORACLE_BASE_HOME}"/network/admin/sqlnet.ora ]; then
    ln -s "${ORACLE_BASE}"/oradata/dbconfig/"${ORACLE_SID}"/sqlnet.ora "${ORACLE_BASE_HOME}"/network/admin/sqlnet.ora
  fi;

}

# Run custom scripts provided by the user
# usage: run_custom_scripts PATH
#    ie: run_custom_scripts /container-entrypoint-initdb.d
# This runs *.sh, *.sql, *.sql.zip, *.sql.gz files
function run_custom_scripts {

  SCRIPTS_ROOT="${1}";

  # Check whether parameter has been passed on
  if [ -z "${SCRIPTS_ROOT}" ]; then
    echo "No SCRIPTS_ROOT passed on, no scripts will be run.";
    return;
  fi;

  # Execute custom provided files (only if directory exists and has files in it)
  if [ -d "${SCRIPTS_ROOT}" ] && [ -n "$(ls -A "${SCRIPTS_ROOT}")" ]; then

    echo -e "\nCONTAINER: Executing user defined scripts..."

    run_custom_scripts_recursive ${SCRIPTS_ROOT}

    echo -e "CONTAINER: DONE: Executing user defined scripts.\n"

  fi;
}

# This recursive function traverses through sub directories by calling itself with them
# usage: run_custom_scripts_recursive PATH
#    ie: run_custom_scripts_recursive /container-entrypoint-initdb.d/001_subdir
# This runs *.sh, *.sql, *.sql.zip, *.sql.gz files and traveres in sub directories
function run_custom_scripts_recursive {
  local f
  for f in "${1}"/*; do
    case "${f}" in
      *.sh)
        if [ -x "${f}" ]; then
                    echo -e "\nCONTAINER: running ${f} ...";     "${f}";     echo "CONTAINER: DONE: running ${f}"
        else
                    echo -e "\nCONTAINER: sourcing ${f} ...";    . "${f}"    echo "CONTAINER: DONE: sourcing ${f}"
        fi;
        ;;

      *.sql)        echo -e "\nCONTAINER: running ${f} ..."; echo "exit" | sqlplus -s / as sysdba @"${f}"; echo "CONTAINER: DONE: running ${f}"
        ;;

      *.sql.zip)    echo -e "\nCONTAINER: running ${f} ..."; echo "exit" | unzip -p "${f}" | sqlplus -s / as sysdba; echo "CONTAINER: DONE: running ${f}"
        ;;

      *.sql.gz)     echo -e "\nCONTAINER: running ${f} ..."; echo "exit" | zcat "${f}" | sqlplus -s / as sysdba; echo "CONTAINER: DONE: running ${f}"
        ;;

      *)
        if [ -d "${f}" ]; then
                    echo -e "\nCONTAINER: descending into ${f} ...";    run_custom_scripts_recursive "${f}";    echo "CONTAINER: DONE: descending into ${f}"
        else
                    echo -e "\nCONTAINER: ignoring ${f}"
        fi;
        ;;
    esac
    echo "";
  done
}

# Create pluggable database
function create_database {

  echo "CONTAINER: Creating pluggable database."

  RANDOM_PDBADIN_PASSWORD=$(date +%s | sha256sum | base64 | head -c 8)

  PDB_CREATE_START_TMS=$(date '+%s')

  sqlplus -s / as sysdba <<EOF
     -- Exit on any errors
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     CREATE PLUGGABLE DATABASE ${ORACLE_DATABASE} \
      ADMIN USER PDBADMIN IDENTIFIED BY "${RANDOM_PDBADIN_PASSWORD}" \
       FILE_NAME_CONVERT=('pdbseed','${ORACLE_DATABASE}') \
        DEFAULT TABLESPACE USERS \
         DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/${ORACLE_DATABASE}/users01.dbf' \
          SIZE 1m AUTOEXTEND ON NEXT 10m MAXSIZE UNLIMITED;

     -- Open PDB and save state
     ALTER PLUGGABLE DATABASE ${ORACLE_DATABASE} OPEN READ WRITE;
     ALTER PLUGGABLE DATABASE ${ORACLE_DATABASE} SAVE STATE;

     -- Register new database with listener
     ALTER SYSTEM REGISTER;
     exit;
EOF

  PDB_CREATE_END_TMS=$(date '+%s')
  PDB_CREATE_DURATION=$(( PDB_CREATE_END_TMS - PDB_CREATE_START_TMS ))
  echo "CONTAINER: DONE: Creating pluggable database, duration: ${PDB_CREATE_DURATION} seconds."

  unset RANDOM_PDBADIN_PASSWORD
}

# Check minimum memory requirements
function check_minimum_memory {

  # cgroups v2
  if [ -f /sys/fs/cgroup/memory.max ]; then
    container_memory=$(< /sys/fs/cgroup/memory.max)
  # cgroups v1
  elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    container_memory=$(< /sys/fs/cgroup/memory/memory.limit_in_bytes)
  else
    echo "CONTAINER: INFO: Cannot determine memory, assuming default of 2 GB."
    container_memory=2147483648
  fi;

  # Check whether memory is not set to "max", i.e. unlimited and
  # prevent integer overflow by checking whether container has
  # less than double digit GB of RAM.
  if [[ ${container_memory} != "max" && ${#container_memory} -lt 11 ]]; then
    # Check memory per version
    # 11.2 >= 1 GB
    # 18c+ >= 2 GB
    if [[ ( "$ORACLE_VERSION" != "11.2."* && ${container_memory} -lt 1073741824 ) ||
          ( ${container_memory} -lt 2147483648 ) ]]; then
      echo "The container has not enough memory available to run Oracle Database XE."
      echo "There are currently only $((container_memory/1024/1024)) MiB available inside the container."
      echo "Please increase the amount of memory for the container."
      exit 1;
    fi;
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

# Setup all required environment variables
setup_env_vars

# Check for minimum memory requirements
check_minimum_memory

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
   -- Exit on any errors
   WHENEVER SQLERROR EXIT SQL.SQLCODE

   startup;
   exit;
EOF
echo ""

# Check whether instance database did come up successfully
if healthcheck.sh "${ORACLE_SID}"; then

  # First database startup / initialization
  if [ -z "${DATABASE_ALREADY_EXISTS:-}" ]; then

    # Set Oracle password if it's the first DB startup
    echo "CONTAINER: Resetting SYS and SYSTEM passwords."

    # If password is specified
    if [ -n "${ORACLE_PASSWORD:-}" ]; then
      resetPassword "${ORACLE_PASSWORD}"

    # Generate random password
    elif [ -n "${ORACLE_RANDOM_PASSWORD:-}" ]; then
      RANDOM_PASSWORD=$(date +%s | sha256sum | base64 | head -c 8)
      resetPassword "${RANDOM_PASSWORD}"
      echo "############################################"
      echo "ORACLE PASSWORD FOR SYS AND SYSTEM: ${RANDOM_PASSWORD}"
      echo "############################################"

    # Should not happen unless script logic changes
    else
      echo "SCRIPT ERROR: Unspecified password!"
      echo "Please report a bug at https://github.com/gvenzl/oci-oracle-xe/issues with your environment details."
      exit 1;
    fi;

    # Check whether user PDB should be created
    # setup_env_vars has already validated >=18c requirement
    if [ -n "${ORACLE_DATABASE:-}" ]; then
      create_database
      if ! healthcheck.sh "${ORACLE_DATABASE}"; then
         echo "CONTAINER: application database not ready for service, aborting!"
         echo "Please report a bug at https://github.com/gvenzl/oci-oracle-xe/issues with your environment details."
         exit 1;
      fi;
    fi;

    # Check whether app user should be created
    # setup_env_vars has already validated environment variables
    if [ -n "${APP_USER:-}" ]; then
      # Create app user for default database
      ./createAppUser "${APP_USER}" "${APP_USER_PASSWORD}"
        # If ORACLE_DATABASE is specified, also create user in app PDB (only applicable >=18c)
      if [ -n "${ORACLE_DATABASE:-}" ]; then
        ./createAppUser "${APP_USER}" "${APP_USER_PASSWORD}" "${ORACLE_DATABASE}"
      fi;
    fi;

    # Running custom database initialization scripts
    run_custom_scripts /container-entrypoint-initdb.d
    # For backwards compatibility
    run_custom_scripts /docker-entrypoint-initdb.d

  # Database already initialized
  else

    # Password was passed on for container start but DB is already initialized, ignoring.
    if [ -n "${ORACLE_PASSWORD:-}" ]; then
      echo "CONTAINER: WARNING: \$ORACLE_PASSWORD has been specified but the database is already initialized. The password will be ignored."
      echo "CONTAINER: WARNING: If you want to reset the password, please run the resetPassword command, e.g. 'docker|podman exec <container name|id> resetPassword <your password>'."
    fi;
  fi;

  # Run custom database startup scripts
  run_custom_scripts /container-entrypoint-startdb.d
  # For backwards compatibility
  run_custom_scripts /docker-entrypoint-startdb.d

  echo ""
  echo "#########################"
  echo "DATABASE IS READY TO USE!"
  echo "#########################"

  # Provide a user warning that these images are old
  echo ""
  echo "################################################"
  echo "NOTICE: YOU ARE USING AN OLD IMAGE VERSION!"
  echo "PLEASE CONSIDER UPGRADING TO gvenzl/oracle-free!"
  echo "################################################"

else
  echo "############################################"
  echo "DATABASE STARTUP FAILED!"
  echo "CHECK LOG OUTPUT ABOVE FOR MORE INFORMATION!"
  echo "############################################"
  exit 1;
fi;

if ! [ "${NOWAIT}" == "--nowait" ]; then

  echo ""
  echo "##################################################################"
  echo "CONTAINER: The following output is now from the alert_${ORACLE_SID}.log file:"
  echo "##################################################################"

  tail -f "${ORACLE_BASE}"/diag/rdbms/*/"${ORACLE_SID}"/trace/alert_"${ORACLE_SID}".log &
  childPID=$!
  wait ${childPID}
fi;
