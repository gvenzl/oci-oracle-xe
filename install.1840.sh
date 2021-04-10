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

# Build mode ("SLIM", "REGULAR", "FULL")
BUILD_MODE=${1:-"REGULAR"}

echo "BUILDER: BUILD_MODE=${BUILD_MODE}"

# Set data file sizes
CDB_SYSAUX_SIZE=480
PDB_SYSAUX_SIZE=342
CDB_SYSTEM_SIZE=840
PDB_SYSTEM_SIZE=255
TEMP_SIZE=2
CDB_UNDO_SIZE=70
PDB_UNDO_SIZE=48
if [ "${BUILD_MODE}" == "FULL" ]; then
  REDO_SIZE=50
elif [ "${BUILD_MODE}" == "REGULAR" ]; then
  REDO_SIZE=20
  USERS_SIZE=10
fi;

echo "BUILDER: Installing dependencies"

# Install installation dependencies
microdnf -y install bc binutils file elfutils-libelf ksh sysstat procps-ng smartmontools make net-tools hostname

# Install runtime dependencies
microdnf -y install libnsl glibc libaio libgcc libstdc++

# Install fortran runtime for libora_netlib.so (so that the Intel Math Kernel libraries are no longer needed)
if [ "${BUILD_MODE}" == "REGULAR" ] || [ "${BUILD_MODE}" == "SLIM" ]; then
  microdnf -y install compat-libgfortran-48
fi;

# Install container runtime specific packages
# (used by the entrypoint script, not the database itself)
microdnf -y install unzip gzip

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
ORACLE_PASSWORD=$(date '+%s' | sha256sum | base64 | head -c 8)
(echo "${ORACLE_PASSWORD}"; echo "${ORACLE_PASSWORD}";) | /etc/init.d/oracle-xe-18c configure 

echo "BUILDER: post config database steps"

# Perform further Database setup operations
su -p oracle -c "sqlplus -s / as sysdba" << EOF
   -- Enable remote HTTP access
   EXEC DBMS_XDB.SETLISTENERLOCALACCESS(FALSE);

   -- Disable common_user_prefix (needed for OS authenticated user)
   ALTER SYSTEM SET COMMON_USER_PREFIX='' SCOPE=SPFILE;

   -- Remove original redo logs from fast_recovery_area and create new ones
   ALTER DATABASE ADD LOGFILE GROUP 4 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo04.log') SIZE ${REDO_SIZE}m;
   ALTER DATABASE ADD LOGFILE GROUP 5 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo05.log') SIZE ${REDO_SIZE}m;
   ALTER DATABASE ADD LOGFILE GROUP 6 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo06.log') SIZE ${REDO_SIZE}m;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM CHECKPOINT;
   ALTER DATABASE DROP LOGFILE GROUP 1;
   ALTER DATABASE DROP LOGFILE GROUP 2;
   ALTER DATABASE DROP LOGFILE GROUP 3;
   HOST rm ${ORACLE_BASE}/oradata/${ORACLE_SID}/redo03.log
   ALTER DATABASE ADD LOGFILE GROUP 1 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo01.log') SIZE ${REDO_SIZE}m REUSE;
   ALTER DATABASE ADD LOGFILE GROUP 2 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo02.log') SIZE ${REDO_SIZE}m REUSE;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM CHECKPOINT;
   ALTER DATABASE DROP LOGFILE GROUP 4;
   HOST rm ${ORACLE_BASE}/oradata/${ORACLE_SID}/redo04.log
   ALTER DATABASE DROP LOGFILE GROUP 5;
   HOST rm ${ORACLE_BASE}/oradata/${ORACLE_SID}/redo05.log
   ALTER DATABASE DROP LOGFILE GROUP 6;
   HOST rm ${ORACLE_BASE}/oradata/${ORACLE_SID}/redo06.log

   -- Disable controlfile splitbrain check
   -- Like with every underscore parameter, DO NOT SET THIS PARAMETER EVER UNLESS YOU KNOW WHAT THE HECK YOU ARE DOING!
   ALTER SYSTEM SET "_CONTROLFILE_SPLIT_BRAIN_CHECK"=FALSE;

   -- Remove local_listener entry (using default 1521)
   ALTER SYSTEM SET LOCAL_LISTENER='';
   
   --TODO; SET UNDO_RETENTION
   
   -- Reboot of DB
   SHUTDOWN IMMEDIATE;
   STARTUP;

   -- Setup healthcheck user
   CREATE USER OPS\$ORACLE IDENTIFIED EXTERNALLY;
   GRANT CONNECT, SELECT_CATALOG_ROLE TO OPS\$ORACLE;

   exit;
EOF

###################################
######## FULL INSTALL DONE ########
###################################

# If not building the FULL image, remove and shrink additional components
if [ "${BUILD_MODE}" == "REGULAR" ] || [ "${BUILD_MODE}" == "SLIM" ]; then
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Deactivate Intel's Math Kernel Libraries
     ALTER SYSTEM SET "_dmm_blas_library"='libora_netlib.so' SCOPE=SPFILE;

     ---------
     -- CDB --
     ---------
     -- Open PDB\$SEED in READ/WRITE mode
     ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
     ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ WRITE;

     -- Disable password profile checks (can only be done container by container)
     ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED PASSWORD_LIFE_TIME UNLIMITED;

     ALTER SESSION SET CONTAINER=PDB\$SEED;
     ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED PASSWORD_LIFE_TIME UNLIMITED;

     ALTER SESSION SET CONTAINER=XEPDB1;
     ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED PASSWORD_LIFE_TIME UNLIMITED;

     -- Go back to CDB level
     ALTER SESSION SET CONTAINER=CDB\$ROOT;

     -- Reset PDB\$SEED to READ ONLY mode
     ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
     ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ ONLY;

     -----------
     -- XEPDB --
     -----------
     ALTER SESSION SET CONTAINER=XEPDB1;

     -- Remove HR schema
     DROP user HR cascade;

     -------------------------------------
     -- Bounce DB to free up UNDO, etc. --
     -------------------------------------
     -- Go back to CDB level

     ALTER SESSION SET CONTAINER=CDB\$ROOT;
     shutdown immediate;
     startup;

     exit;
EOF

  # Shrink datafiles
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Open PDB\$SEED in READ/WRITE mode
     ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
     ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ WRITE;

     ----------------------------
     -- Shrink SYSAUX tablespaces
     ----------------------------

     -- Create new temporary SYSAUX tablespace
     --CREATE TABLESPACE SYSAUX_TEMP DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/sysaux_temp.dbf'
     --SIZE 250M AUTOEXTEND ON NEXT 1M MAXSIZE UNLIMITED;

     -- Move tables to temporary SYSAUX tablespace
     --#TODO
     --BEGIN
     --   FOR cur IN (SELECT  owner || '.' || table_name AS name FROM all_tables WHERE tablespace_name = 'SYSAUX') LOOP
     --      EXECUTE IMMEDIATE 'ALTER TABLE ' || cur.name || ' MOVE TABLESPACE SYSAUX_TEMP';
     --   END LOOP;
     --END;
     --/

     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/sysaux01.dbf' RESIZE ${CDB_SYSAUX_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/sysaux01.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=PDB\$SEED;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/sysaux01.dbf' RESIZE ${PDB_SYSAUX_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/sysaux01.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=XEPDB1;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/sysaux01.dbf' RESIZE ${PDB_SYSAUX_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/sysaux01.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=CDB\$ROOT;

     ----------------------------
     -- Shrink SYSTEM tablespaces
     ----------------------------

     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/system01.dbf' RESIZE ${CDB_SYSTEM_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/system01.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=PDB\$SEED;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/system01.dbf' RESIZE ${PDB_SYSTEM_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/system01.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=XEPDB1;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/system01.dbf' RESIZE ${PDB_SYSTEM_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/system01.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=CDB\$ROOT;

     --------------------------
     -- Shrink TEMP tablespaces
     --------------------------

     ALTER DATABASE TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/temp01.dbf' RESIZE ${TEMP_SIZE}M;
     ALTER DATABASE TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/temp01.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=PDB\$SEED;
     -- Find and drop old TEMP file
     DECLARE
        v_tmp_file_name   VARCHAR2(200);
     BEGIN
        SELECT name INTO v_tmp_file_name FROM v\$tempfile WHERE name LIKE '%/temp012%';
        -- TODO: shrink temp file to 2MB for PDB\$SEED
        EXECUTE IMMEDIATE
           'ALTER DATABASE TEMPFILE ''' || v_tmp_file_name || ''' RESIZE 32M';
        EXECUTE IMMEDIATE
           'ALTER DATABASE TEMPFILE ''' || v_tmp_file_name || ''' AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED';
        --TODO: rename ugly TEMP file and resize

     END;
     /

     ALTER SESSION SET CONTAINER=XEPDB1;
     ALTER DATABASE TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/temp01.dbf' RESIZE ${TEMP_SIZE}M;
     ALTER DATABASE TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/temp01.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=CDB\$ROOT;

     ----------------------------
     -- Shrink USERS tablespaces
     ----------------------------

     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/users01.dbf' RESIZE ${USERS_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/users01.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=XEPDB1;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/users01.dbf' RESIZE ${USERS_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/users01.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=CDB\$ROOT;

     ----------------------------
     -- Shrink UNDO tablespaces
     ----------------------------

     -- TODO: Try to further decrease UNDO sizes
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/undotbs01.dbf' RESIZE ${CDB_UNDO_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/undotbs01.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=PDB\$SEED;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/undotbs01.dbf' RESIZE ${PDB_UNDO_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/undotbs01.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=XEPDB1;
     -- PDB UNDO cannot go smaller (not sure yet why, TODO)
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/undotbs01.dbf' RESIZE ${CDB_UNDO_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/undotbs01.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER SESSION SET CONTAINER=CDB\$ROOT;

     ------------------------------
     -- Complete actions and finish
     ------------------------------
     ALTER SESSION SET CONTAINER=CDB\$ROOT;

     -- Reset PDB\$SEED to READ ONLY mode
     ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
     ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ ONLY;

     exit;
EOF


fi;

###################################
########### DB SHUTDOWN ###########
###################################

echo "BUILDER: graceful database shutdown"

# Shutdown database gracefully (listener is not yet running)
su -p oracle -c "sqlplus -s / as sysdba" << EOF
   -- Shutdown database gracefully
   shutdown immediate;
   exit;
EOF

###############################
### Compress Database files ###
###############################

echo "BUILDER: compressing database data files"
cd "${ORACLE_BASE}"/oradata
zip -r "${ORACLE_SID}".zip "${ORACLE_SID}"
rm  -r "${ORACLE_SID}"
cd - 1> /dev/null

############################
### Create network files ###
############################

echo "BUILDER: creating network files"

# listener.ora
echo \
"LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC_FOR_${ORACLE_SID}))
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    )
  )

DEFAULT_SERVICE_LISTENER = ${ORACLE_SID}" > "${ORACLE_HOME}"/network/admin/listener.ora

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

${ORACLE_SID}PDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${ORACLE_SID}PDB1)
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
" > "${ORACLE_HOME}"/network/admin/tnsnames.ora

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
export ORACLE_HOME=\${ORACLE_BASE}/product/18c/dbhomeXE
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
rm /etc/sysconfig/oracle-xe-18c.conf
rm -r /var/log/oracle-database-xe-18c
rm -r /tmp/*

# Remove SYS audit directories and files created during install
rm -r "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/adump/*
rm -r "${ORACLE_BASE}"/audit/"${ORACLE_SID}"/*

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

# Remove additional files for NOMRAL and SLIM builds
if [ "${BUILD_MODE}" == "REGULAR" ] || [ "${BUILD_MODE}" == "SLIM" ]; then

  # Remove OPatch and QOpatch
  rm -r "${ORACLE_HOME}"/OPatch
  rm -r "${ORACLE_HOME}"/QOpatch

  # Remove assistants
  rm -r "${ORACLE_HOME}"/assistants

  # Remove Oracle Database Migration Assistant for Unicode (dmu)
  rm -r "${ORACLE_HOME}"/dmu

  # Remove JDBC drivers
  rm -r "${ORACLE_HOME}"/jdbc
  rm -r "${ORACLE_HOME}"/jlib
  rm -r "${ORACLE_HOME}"/ucp

  # Remove Intel's Math kernel libraries
  rm "${ORACLE_HOME}"/lib/libmkl_*

  # Remove zip artifacts in $ORACLE_HOME/lib
  rm "${ORACLE_HOME}"/lib/*.zip

  # Remove not needed packages
  # Use rpm instad of microdnf to allow removing packages regardless of their dependencies
  rpm -e --nodeps glibc-devel glibc-headers kernel-headers libpkgconf libxcrypt-devel \
                  pkgconf pkgconf-m4 pkgconf-pkg-config

fi;

# Remove installation dependencies
# Use rpm instead of microdnf to allow removing packages regardless of dependencies specified by the Oracle XE RPM
rpm -e --nodeps dbus-libs libtirpc diffutils libnsl2 dbus-tools dbus-common dbus-daemon \
                libpcap iptables-libs libseccomp libfdisk xz lm_sensors-libs libutempter \
                kmod-libs cracklib libpwquality pam util-linux findutils acl \
                device-mapper device-mapper-libs cryptsetup-libs elfutils-default-yama-scope \
                elfutils-libs systemd-pam systemd dbus smartmontools ksh sysstat procps-ng \
                binutils file make bc net-tools hostname

rm /etc/sysctl.conf.rpmsave

# Remove dnf cache
microdnf clean all
