#!/bin/bash
# Since: February, 2021
# Author: gvenzl
# Name: install.1840.sh
# Description: Install script for Oracle DB XE 18.4.0
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

echo "BUILDER: started"

# Build mode ("SLIM", "NORMAL", "FULL")
BUILD_MODE=${1:-"NORMAL"}

echo "BUILDER: BUILD_MODE=${BUILD_MODE}"

if [ "${BUILD_MODE}" == "FULL" ]; then
   REDO_SIZE=50
fi;

echo "BUILDER: Installing dependencies"

# Installation dependencies
microdnf -y install bc binutils file elfutils-libelf ksh sysstat procps-ng smartmontools make net-tools hostname

# Runtime dependencies
microdnf -y install libnsl glibc libaio libgcc libstdc++ 

################################
###### Install Database ########
################################

echo "BUILDER: installing database binaries"

# Install Oracle XE
rpm -iv --nodeps /install/oracle-database-xe-18c-1.0-1.x86_64.rpm

# Set 'oracle' user home directory to ${ORACE_BASE}
usermod -d ${ORACLE_BASE} oracle

# Add listener port and skip validations to conf file
sed -i "s/LISTENER_PORT=/LISTENER_PORT=1521/g" /etc/sysconfig/oracle-xe-18c.conf
sed -i "s/SKIP_VALIDATIONS=false/SKIP_VALIDATIONS=true/g" /etc/sysconfig/oracle-xe-18c.conf

echo "BUILDER: configuring database"

# Set random password
ORACLE_PASSWORD=$(date +%s | base64 | head -c 8)
/etc/init.d/oracle-xe-18c configure <<EOF
${ORACLE_PASSWORD}
${ORACLE_PASSWORD}
EOF

echo "BUILDER: post config database steps"

# TODO

###################################
######## FULL INSTALL DONE ########
###################################

# TODO

echo "BUILDER: graceful database shutdown"

# Shutdown database gracefully (listener is not yet running)
su -p oracle -c "sqlplus -s / as sysdba" << EOF
   -- Shutdown database gracefully
   shutdown immediate;
   exit;
EOF

#########################
####### Cleanup #########
#########################

echo "BUILDER: cleanup"

# Remove install directory
rm -r /install

# Remove dnf cache
microdnf clean all
