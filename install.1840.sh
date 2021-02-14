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
(echo "${ORACLE_PASSWORD}"; echo "${ORACLE_PASSWORD}";) | /etc/init.d/oracle-xe-18c configure 

echo "BUILDER: post config database steps"

# Perform further Database setup operations
su -p oracle -c "sqlplus -s / as sysdba" << EOF
   -- Enable remote HTTP access
   EXEC DBMS_XDB.SETLISTENERLOCALACCESS(FALSE);

   -- Disable common_user_prefix (needed for OS authenticated user)
   ALTER SYSTEM SET COMMON_USER_PREFIX='' SCOPE=SPFILE;

   -- Disable controlfile splitbrain check
   -- Like with every underscore parameter, DO NOT SET THIS PARAMETER EVER UNLESS YOU KNOW WHAT THE HECK YOU ARE DOING!
   ALTER SYSTEM SET "_CONTROLFILE_SPLIT_BRAIN_CHECK"=FALSE;

   SHUTDOWN IMMEDIATE;
   STARTUP;

   CREATE USER OPS\$ORACLE IDENTIFIED EXTERNALLY;
   GRANT CONNECT, SELECT_CATALOG_ROLE TO OPS\$ORACLE;

   exit;
EOF

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

####################
### bash_profile ###
####################

echo "BUILDER: creating .bash_profile"

# Create .bash_profile for oracle user
echo \
"export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_HOME=\${ORACLE_BASE}/product/11.2.0/xe
export ORACLE_SID=XE
export PATH=\${PATH}:\${ORACLE_HOME}/bin:\${ORACLE_BASE}
" >> "${ORACLE_BASE}"/.bash_profile
chown oracle:dba "${ORACLE_BASE}"/.bash_profile

########################
### Install run file ###
########################

echo "BUILDER: install operational files"

# Move operational files to ${ORACLE_BASE}
mv /install/*.sh "${ORACLE_BASE}"/
mv /install/resetPassword "${ORACLE_BASE}"/

chown oracle:dba "${ORACLE_BASE}"/*.sh \
                 "${ORACLE_BASE}"/resetPassword

chmod u+x "${ORACLE_BASE}"/*.sh \
          "${ORACLE_BASE}"/resetPassword

#########################
####### Cleanup #########
#########################

echo "BUILDER: cleanup"

# Remove install directory
rm -r /install

# Cleanup XE files not needed for being in a container but were installed by the rpm
/sbin/chkconfig --del oracle-xe-18c
rm /etc/init.d/oracle-xe-18c
rm -r /var/log/oracle-database-xe-18c
rm -r /tmp/*

# Remove SYS audit directories and files created during install
rm -r "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/adump/*

# Remove Data Pump log file
rm "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/dpdump/dp.log

# Remove Oracle DB install logs
rm    "${ORACLE_BASE}"/cfgtoollogs/dbca/XE/*
rm    "${ORACLE_BASE}"/cfgtoollogs/netca/*
rm -r "${ORACLE_BASE}"/cfgtoollogs/sqlpatch/*
rm    "${ORACLE_BASE}"/oraInventory/logs/*
rm    "${ORACLE_HOME}"/cfgtoollogs/oui/*

# Remove diag files
rm "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/lck/*
rm "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/metadata/*
rm "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/trace/"${ORACLE_SID}"_*
rm "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/trace/drc"${ORACLE_SID}".log
rm "${ORACLE_BASE}"/diag/tnslsnr/localhost/listener/lck/*
rm "${ORACLE_BASE}"/diag/tnslsnr/localhost/listener/metadata/*

# Remove installation dependencies
# Use rpm instead of microdnf to allow removing packages regardless of dependencies specified by the Oracle XE RPM
rpm -e --nodeps dbus-libs libtirpc diffutils libnsl2 dbus-tools dbus-common dbus-daemon \
                libpcap iptables-libs libseccomp libfdisk xz lm_sensors-libs libutempter \
                kmod-libs gzip cracklib libpwquality pam util-linux findutils acl \
                device-mapper device-mapper-libs cryptsetup-libs elfutils-default-yama-scope \
                elfutils-libs systemd-pam systemd dbus smartmontools ksh sysstat procps-ng \
                binutils file make bc net-tools hostname

rm /etc/sysctl.conf.rpmsave

# Remove dnf cache
microdnf clean all
