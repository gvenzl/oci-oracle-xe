#!/bin/bash
# Since: January, 2021
# Author: gvenzl
# Name: install.11202.sh
# Description: Install script for Oracle DB XE 11.2.0.2
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

# Set data file sizes
if [ "${BUILD_MODE}" == "FULL" ]; then
   REDO_SIZE=50
fi;

echo "BUILDER: installing additional packages"

# Required for install procedures
microdnf -y install bc procps-ng util-linux net-tools

# Install required system packages
microdnf -y install libaio libnsl

# Install GCC and other packages for full installation
if [ "${BUILD_MODE}" == "FULL" ]; then
   microdnf -y install glibc make binutils gcc
fi;

# Fake 2 GB swap configuration
free() { echo "Swap: 0 0 2048"; }
export -f free

################################
###### Install Database ########
################################

echo "BUILDER: installing database binaries"

# Install Oracle DB binaries
rpm -iv /install/oracle-xe-11.2.0-1.0.x86_64.rpm

# Remove fake 2 GB swap configuration
unset -f cat free

# Remove memory_target parameter (not supported by default in containers)
sed -i "/memory_target/d" "${ORACLE_HOME}"/config/scripts/init.ora
sed -i "/memory_target/d" "${ORACLE_HOME}"/config/scripts/init"${ORACLE_SID}"Temp.ora

# Add SGA_TARGET and PGA_AGGREGATE_TARGET to pfile
sed -i "$ a sga_target=768m" "${ORACLE_HOME}"/config/scripts/init.ora
sed -i "$ a sga_target=768m" "${ORACLE_HOME}"/config/scripts/init"${ORACLE_SID}"Temp.ora
sed -i "$ a pga_aggregate_target=256m" "${ORACLE_HOME}"/config/scripts/init.ora
sed -i "$ a pga_aggregate_target=256m" "${ORACLE_HOME}"/config/scripts/init"${ORACLE_SID}"Temp.ora

# Set random password
ORACLE_PASSWORD=$(date +%s | base64 | head -c 8)
sed -i "s/###ORACLE_PASSWORD###/${ORACLE_PASSWORD}/g" /install/xe.11202.rsp

echo "BUILDER: configuring database"

# Configure  database
/etc/init.d/oracle-xe configure responseFile=/install/xe.11202.rsp

echo "BUILDER: post config database steps"

# Perform further Database setup operations
su -p oracle -c "sqlplus -s / as sysdba" << EOF
   -- Enable remote HTTP access
   EXEC DBMS_XDB.SETLISTENERLOCALACCESS(FALSE);

   -- Remove original redo logs from fast_recovery_area and create new ones
   ALTER DATABASE ADD LOGFILE GROUP 3 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo03.log') SIZE ${REDO_SIZE}m;
   ALTER DATABASE ADD LOGFILE GROUP 4 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo04.log') SIZE ${REDO_SIZE}m;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM CHECKPOINT;
   ALTER DATABASE DROP LOGFILE GROUP 1;
   ALTER DATABASE DROP LOGFILE GROUP 2;
   ALTER DATABASE ADD LOGFILE GROUP 1 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo01.log') SIZE ${REDO_SIZE}m;
   ALTER DATABASE ADD LOGFILE GROUP 2 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo02.log') SIZE ${REDO_SIZE}m;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM CHECKPOINT;
   ALTER DATABASE DROP LOGFILE GROUP 3;
   ALTER DATABASE DROP LOGFILE GROUP 4;

   -- Set fast recovery area inside oradata folder
   HOST mkdir "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/fast_recovery_area
   ALTER SYSTEM SET DB_RECOVERY_FILE_DEST = '${ORACLE_BASE}/oradata/${ORACLE_SID}/fast_recovery_area';
   HOST rm -r "${ORACLE_BASE}"/fast_recovery_area

   -- Setup healthcheck user
   CREATE USER OPS\$ORACLE IDENTIFIED EXTERNALLY;
   GRANT CONNECT, SELECT_CATALOG_ROLE TO OPS\$ORACLE;

   exit;
EOF

# Non-managed (OMF) redo logs aren't deleted automatically (REDO GROUP 3 and 4 above)
# Need to be deleted manually

rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo03.log
rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo04.log

###################################
######## FULL INSTALL DONE ########
###################################

echo "BUILDER: graceful database shutdown"

# Shutdown database gracefully (listener is not yet running)
su -p oracle -c "sqlplus -s / as sysdba" << EOF
   -- Shutdown database gracefully
   shutdown immediate;
   exit;
EOF

############################
### Create network files ###
############################

echo "BUILDER: creating network files"

# listener.ora
echo \
"SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (SID_NAME = PLSExtProc)
      (ORACLE_HOME = ${ORACLE_HOME})
      (PROGRAM = extproc)
    )
  )

LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC_FOR_${ORACLE_SID}))
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    )
  )

DEFAULT_SERVICE_LISTENER = (${ORACLE_SID})" > "${ORACLE_HOME}"/network/admin/listener.ora

# tnsnames.ora
echo \
"${ORACLE_SID} =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${ORACLE_SID})
    )
  )

EXTPROC_CONNECTION_DATA =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC_FOR_${ORACLE_SID}))
    )
    (CONNECT_DATA =
      (SID = PLSExtProc)
      (PRESENTATION = RO)
    )
  )
" > "${ORACLE_HOME}/network/admin/tnsnames.ora"

# sqlnet.ora
echo "NAME.DIRECTORY_PATH= (EZCONNECT, TNSNAMES)" > "${ORACLE_HOME}"/network/admin/sqlnet.ora

chown -R oracle:dba "${ORACLE_HOME}"/network/admin

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
" >> "${ORACLE_BASE}/.bash_profile"
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
rm -r /etc/kde/xdg/menus/OracleXE
rm -r /usr/share/applications/oraclexe*
rm -r /usr/share/desktop-menu-files/oraclexe*
rm -r /usr/share/gnome/vfolders/oraclexe*
rm -r /usr/share/pixmaps/oraclexe*
/sbin/chkconfig --del oracle-xe
rm /etc/init.d/oracle-xe

# Remove SYS audit files created during install
rm "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/adump/*.aud

# Remove Data Pump log file
rm "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/dpdump/dp.log

# Remove diag files
rm "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/lck/*
rm "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/metadata/*
rm "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/trace/"${ORACLE_SID}"_*
rm "${ORACLE_BASE}"/diag/tnslsnr/localhost/listener/lck/*
rm "${ORACLE_BASE}"/diag/tnslsnr/localhost/listener/metadata/*
rm -r "${ORACLE_BASE}"/oradiag_oracle/*

# Remove Oracle DB install logs
rm "${ORACLE_HOME}"/config/log/*

# Remove build packages
# Unfortunately microdnf does not automatically uninstall dependencies that have been
# installed with a package, so if you were to uninstall just util-linux, for example,
# it does not automatically also remove gzip and cracklib again.
microdnf -y remove bc libtirpc libnsl2 libfdisk libutempter gzip cracklib libpwquality \
                   pam util-linux dbus-libs dbus-tools pam libpwquality dbus-common \
                   dbus-daemon libpcap iptables-libs libseccomp kmod-libs acl \
                   device-mapper device-mapper-libs cryptsetup-libs \
                   elfutils-default-yama-scope elfutils-libs systemd-pam systemd dbus \
                   procps-ng net-tools util-linux

# Remove dnf cache
microdnf clean all
