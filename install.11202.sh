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

# Build mode ("SLIM", "REGULAR", "FULL")
BUILD_MODE=${1:-"REGULAR"}

echo "BUILDER: BUILD_MODE=${BUILD_MODE}"

# Set data file sizes
SYSTEM_SIZE=353
SYSAUX_SIZE=610
if [ "${BUILD_MODE}" == "REGULAR" ]; then
  REDO_SIZE=20
  USERS_SIZE=10
elif [ "${BUILD_MODE}" == "SLIM" ]; then
  REDO_SIZE=10
  USERS_SIZE=2
fi;

echo "BUILDER: Installing OS dependencies"

# Install installation dependencies
microdnf -y install bc procps-ng util-linux net-tools findutils

# Install runtime dependencies
microdnf -y install libaio libnsl xz

# Install container runtime specific packages
# (used by the entrypoint script, not the database itself)
# TODO: replace with 7zip
microdnf -y install unzip gzip

# Install 7zip
mkdir /tmp/7z
cd /tmp/7z
curl -s -L -O https://www.7-zip.org/a/7z2201-linux-x64.tar.xz
tar xf 7z*xz
mv 7zzs /usr/bin/
mv License.txt /usr/share/
cd - 1> /dev/null
rm -rf /tmp/7z

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

# Change installation directory to /opt/oracle
# Move $ORACLE_BASE under the new $ORACLE_BASE parent directory (i.e. /opt/ for /opt/oracle)
#mv /u01/app/oracle "${ORACLE_BASE%%/oracle}"
#chown -R oracle:dba /u01
# Symlink /u01/app/oracle --> /opt/oracle
# This is so that the hard coded shared libraries paths in the binaries (sqlplus, etc.) can be resolved (check 'ldd sqlplus')
#ln -s "${ORACLE_BASE}" /u01/app/
# Replace absolute path with $ORACLE_BASE variable for /etc/init.d/oracle-xe (used to configure DB later on)
#sed -i "s|/u01/app/oracle|\${ORACLE_BASE}|g" /etc/init.d/oracle-xe
# SQL*Plus and other files (.ora, etc) don't do variable expansion, replace absolute path /u01/app/oracle with value of $ORACLE_BASE
#for file in $(grep -rIl "/u01/app/oracle" "${ORACLE_HOME}"); do
#  sed -i "s|/u01/app/oracle|${ORACLE_BASE}|g" "${file}"
#done;
# Oracle DB directories need to be recreated:
#DATA_PUMP_DIR	/u01/app/oracle/admin/XE/dpdump/
#XMLDIR	/u01/app/oracle/product/11.2.0/xe/rdbms/xml

# Remove memory_target parameter (not supported by default in containers)
sed -i "/memory_target/d" "${ORACLE_HOME}"/config/scripts/init.ora
sed -i "/memory_target/d" "${ORACLE_HOME}"/config/scripts/init"${ORACLE_SID}"Temp.ora

# Add SGA_TARGET and PGA_AGGREGATE_TARGET to pfile
sed -i "$ a sga_target=768m" "${ORACLE_HOME}"/config/scripts/init.ora
sed -i "$ a sga_target=768m" "${ORACLE_HOME}"/config/scripts/init"${ORACLE_SID}"Temp.ora
sed -i "$ a pga_aggregate_target=256m" "${ORACLE_HOME}"/config/scripts/init.ora
sed -i "$ a pga_aggregate_target=256m" "${ORACLE_HOME}"/config/scripts/init"${ORACLE_SID}"Temp.ora

# Add CPU_COUNT to pfile
sed -i "$ a cpu_count=1" "${ORACLE_HOME}"/config/scripts/init.ora
sed -i "$ a cpu_count=1" "${ORACLE_HOME}"/config/scripts/init"${ORACLE_SID}"Temp.ora

# Set random password
ORACLE_PASSWORD=$(date '+%s' | sha256sum | base64 | head -c 8)
sed -i "s/###ORACLE_PASSWORD###/${ORACLE_PASSWORD}/g" /install/xe.11202.rsp

echo "BUILDER: configuring database"

# Configure  database
/etc/init.d/oracle-xe configure responseFile=/install/xe.11202.rsp

echo "BUILDER: post config database steps"

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

FREE =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = FREE)
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
echo "NAMES.DIRECTORY_PATH = (EZCONNECT, TNSNAMES)" > "${ORACLE_HOME}"/network/admin/sqlnet.ora

chown -R oracle:dba "${ORACLE_HOME}"/network/admin

####################
### bash_profile ###
####################

# Create .bash_profile for oracle user
echo "BUILDER: creating .bash_profile"
echo \
"export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_BASE_CONFIG=${ORACLE_BASE_CONFIG}
export ORACLE_BASE_HOME=${ORACLE_BASE_HOME}
export ORACLE_HOME=${ORACLE_HOME}
export ORACLE_SID=XE
export PATH=\${PATH}:\${ORACLE_HOME}/bin:\${ORACLE_BASE}

# Use UTF-8 by default
export NLS_LANG=.AL32UTF8
" >> "${ORACLE_BASE}"/.bash_profile
chown oracle:dba "${ORACLE_BASE}"/.bash_profile

# Create entrypoint folders (#108)
#
# Certain tools like GitLab CI do not allow for volumes, instead a user has to copy
# files into the folders. However, as these folders are under / and the container user
# is `oracle`, they can no longer create these folders.
# Instead we provide them here already so that these folks can start putting files into
# them directly, if they have to.

mkdir /container-entrypoint-initdb.d
mkdir /container-entrypoint-startdb.d
chown oracle:dba /container-entrypoint*

# Perform further Database setup operations
echo "BUILDER: changing database configuration and parameters for all images"
su -p oracle -c "sqlplus -s / as sysdba" << EOF

   -- Exit on any errors
   WHENEVER SQLERROR EXIT SQL.SQLCODE

   -- Enable remote HTTP access
   EXEC DBMS_XDB.SETLISTENERLOCALACCESS(FALSE);

   -- Setup healthcheck user
   CREATE USER OPS\$ORACLE IDENTIFIED EXTERNALLY;
   GRANT CONNECT, SELECT_CATALOG_ROLE TO OPS\$ORACLE;

   -- Remove original redo logs from fast_recovery_area and create new ones
   ALTER DATABASE ADD LOGFILE GROUP 3 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo03.log') SIZE 50m;
   ALTER DATABASE ADD LOGFILE GROUP 4 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo04.log') SIZE 50m;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM CHECKPOINT;
   ALTER DATABASE DROP LOGFILE GROUP 1;
   ALTER DATABASE DROP LOGFILE GROUP 2;
   ALTER DATABASE ADD LOGFILE GROUP 1 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo01.log') SIZE 50m;
   ALTER DATABASE ADD LOGFILE GROUP 2 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo02.log') SIZE 50m;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM SWITCH LOGFILE;
   ALTER SYSTEM CHECKPOINT;
   ALTER DATABASE DROP LOGFILE GROUP 3;
   ALTER DATABASE DROP LOGFILE GROUP 4;

   -- Remove fast recovery area
   ALTER SYSTEM SET DB_RECOVERY_FILE_DEST='';
   ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE=1;
   HOST rm -r "${ORACLE_BASE}"/fast_recovery_area

   -- Non-managed (OMF) redo logs aren't deleted automatically (REDO GROUP 3 and 4 above)
   -- Need to be deleted manually
   HOST rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo03.log
   HOST rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo04.log

   -- Enable new service name FREE for upwards compatibility with FREE.
   ALTER SYSTEM SET SERVICE_NAMES=XE,FREE;

   exit;
EOF

###################################
######## FULL INSTALL DONE ########
###################################

# If not building the FULL image, remove and shrink additional components
if [ "${BUILD_MODE}" == "REGULAR" ] || [ "${BUILD_MODE}" == "SLIM" ]; then

  echo "BUILDER: further optimizations for REGULAR and SLIM image"

  echo "BUILDER: changing database configuration and parameters for REGULAR and SLIM images"
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Exit on any errors
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     -- Disable shared servers (enables faster shutdown)
     ALTER SYSTEM SET SHARED_SERVERS=0;

     -- Disable password profile checks
     ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED PASSWORD_LIFE_TIME UNLIMITED;

     ---------------------------
     ------- Remove APEX -------
     ---------------------------
     @${ORACLE_HOME}/apex/apxremov.sql
     DROP PUBLIC SYNONYM HTMLDB_SYSTEM;
     DROP PACKAGE HTMLDB_SYSTEM;

     ---------------------------
     ---- Remove HR schema -----
     ---------------------------
     DROP USER HR cascade;

     exit;
EOF

  # Uninstall components
  if [ "${BUILD_MODE}" == "SLIM" ]; then
    su -p oracle -c "sqlplus -s / as sysdba" << EOF

       -- Do not exit on error because of expected error in catmet2.sql
       -- WHENEVER SQLERROR EXIT SQL.SQLCODE

       SHUTDOWN IMMEDIATE;
       STARTUP UPGRADE;

       ---------------------------
       ------- Remove XDB --------
       ---------------------------

       -- Remove XS components manually
       drop index xdb.sc_xidx;
       drop index xdb.prin_xidx;
       drop public synonym XS\$CACHE_DELETE;
       drop public synonym XS\$CACHE_ACTIONS;
       drop public synonym DBA_NETWORK_ACLS;
       drop public synonym DBA_NETWORK_ACL_PRIVILEGES;
       drop public synonym DBA_WALLET_ACLS;
       drop public synonym DBA_XDS_OBJECTS;
       drop public synonym ALL_XDS_OBJECTS;
       drop public synonym USER_XDS_OBJECTS;
       drop public synonym DBA_XDS_INSTANCE_SETS;
       drop public synonym ALL_XDS_INSTANCE_SETS;
       drop public synonym USER_XDS_INSTANCE_SETS;
       drop public synonym DBA_XDS_ATTRIBUTE_SECS;
       drop public synonym ALL_XDS_ATTRIBUTE_SECS;
       drop public synonym USER_XDS_ATTRIBUTE_SECS;
       drop public synonym DOCUMENT_LINKS2;
       drop public synonym ALL_XSC_SECURITY_CLASS;
       drop public synonym ALL_XSC_SECURITY_CLASS_STATUS;
       drop public synonym ALL_XSC_SECURITY_CLASS_DEP;
       drop public synonym ALL_XSC_PRIVILEGE;
       drop public synonym ALL_XSC_AGGREGATE_PRIVILEGE;
       drop public synonym XS_SESSION_ROLES;
       drop public synonym V\$XS_SESSION;
       drop public synonym V\$XS_SESSION_ROLE;
       drop public synonym V\$XS_SESSION_ATTRIBUTE;
       drop public synonym USER_NETWORK_ACL_PRIVILEGES;
       drop public synonym dbms_network_acl_utility;
       drop public synonym dbms_network_acl_admin;
       drop public synonym DBMS_XS_MTCACHE;
       drop public synonym DBMS_XS_UTIL;
       drop view DBA_NETWORK_ACLS;
       drop view DBA_NETWORK_ACL_PRIVILEGES;
       drop view DBA_WALLET_ACLS;
       drop view DBA_XDS_OBJECTS;
       drop view ALL_XDS_OBJECTS;
       drop view USER_XDS_OBJECTS;
       drop view DBA_XDS_INSTANCE_SETS;
       drop view ALL_XDS_INSTANCE_SETS;
       drop view USER_XDS_INSTANCE_SETS;
       drop view DBA_XDS_ATTRIBUTE_SECS;
       drop view ALL_XDS_ATTRIBUTE_SECS;
       drop view USER_XDS_ATTRIBUTE_SECS;
       drop view XDB.DOCUMENT_LINKS2;
       drop view ALL_XSC_SECURITY_CLASS;
       drop view ALL_XSC_SECURITY_CLASS_STATUS;
       drop view ALL_XSC_SECURITY_CLASS_DEP;
       drop view ALL_XSC_PRIVILEGE;
       drop view ALL_XSC_AGGREGATE_PRIVILEGE;
       drop view V\$XS_SESSION;
       drop view V\$XS_SESSION_ROLE;
       drop view V\$XS_SESSION_ATTRIBUTE;
       drop view USER_NETWORK_ACL_PRIVILEGES;
       drop table XDB.XS\$CACHE_ACTIONS;
       drop table XDB.XS\$CACHE_DELETE;
       drop table NET\$_ACL;
       drop table WALLET\$_ACL;
       drop package XS\$CATVIEW_UTIL;
       drop package DBMS_XS_PRINCIPALS;
       drop package DBMS_XS_PRINCIPALS_INT;
       drop package DBMS_XS_ROLESET_EVENTS_INT;
       drop package DBMS_XS_PRINCIPAL_EVENTS_INT;
       drop package DBMS_XS_DATA_SECURITY_EVENTS;
       drop package DBMS_XS_SECCLASS_EVENTS;
       drop package DBMS_XS_MTCACHE;
       drop package DBMS_XS_MTCACHE_FFI;
       drop package XS_UTIL;
       drop package dbms_network_acl_admin;
       drop package dbms_network_acl_utility;
       drop user XS\$NULL cascade;

       -- XDB removal script
       @${ORACLE_HOME}/rdbms/admin/catnoqm.sql

       -- Update Data Pump and related objects and KU$_ views
       @${ORACLE_HOME}/rdbms/admin/catxdbdv.sql
       @${ORACLE_HOME}/rdbms/admin/dbmsmeta.sql
       @${ORACLE_HOME}/rdbms/admin/dbmsmeti.sql
       @${ORACLE_HOME}/rdbms/admin/dbmsmetu.sql
       @${ORACLE_HOME}/rdbms/admin/dbmsmetb.sql
       @${ORACLE_HOME}/rdbms/admin/dbmsmetd.sql
       @${ORACLE_HOME}/rdbms/admin/dbmsmet2.sql
       @${ORACLE_HOME}/rdbms/admin/catmeta.sql
       @${ORACLE_HOME}/rdbms/admin/prvtmeta.plb
       @${ORACLE_HOME}/rdbms/admin/prvtmeti.plb
       @${ORACLE_HOME}/rdbms/admin/prvtmetu.plb
       @${ORACLE_HOME}/rdbms/admin/prvtmetb.plb
       @${ORACLE_HOME}/rdbms/admin/prvtmetd.plb
       @${ORACLE_HOME}/rdbms/admin/prvtmet2.plb
       @${ORACLE_HOME}/rdbms/admin/catmet2.sql

       ---------------------------
       ------- Remove Text -------
       ---------------------------
       @${ORACLE_HOME}/ctx/admin/catnoctx.sql
       drop procedure sys.validate_context;

       ---------------------------
       ----- Remove Spatial ------
       ---------------------------
       -- Drop Spatial user
       DROP USER MDSYS CASCADE;

       -- Drop all  public synonyms related to spatial
       BEGIN
          FOR cur IN (SELECT 'drop public synonym "' || synonym_name || '"' AS cmd
                        FROM dba_synonyms WHERE table_owner = 'MDSYS')
          LOOP
             EXECUTE IMMEDIATE cur.cmd;
          END LOOP;
       END;
       /

       ---------------------------
       --- Recompile database ----
       ---------------------------
       @${ORACLE_HOME}/rdbms/admin/utlrp.sql

       -- Restart DB in normal mode
       shutdown immediate;
       startup;

EOF
  fi;

  # Shrink datafiles
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Exit on any errors
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     ---------------------------
     -- Shrink SYSAUX tablespace
     ---------------------------

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

     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/sysaux.dbf' RESIZE ${SYSAUX_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/sysaux.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ---------------------------
     -- Shrink SYSTEM tablespace
     ---------------------------

     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/system.dbf' RESIZE ${SYSTEM_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/system.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -------------------------
     -- Shrink TEMP tablespace
     -------------------------

     ALTER TABLESPACE TEMP SHRINK SPACE;
     ALTER DATABASE TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/temp.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     --------------------------
     -- Shrink USERS tablespace
     --------------------------

     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/users.dbf' RESIZE ${USERS_SIZE}M;
     ALTER DATABASE DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/users.dbf'
        AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -------------------------
     -- Shrink UNDO tablespace
     -------------------------

     -- Create new temporary UNDO tablespace
     CREATE UNDO TABLESPACE UNDO_TMP DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/undotbs_tmp.dbf'
        SIZE 1M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -- Use new temporary UNDO tablespace (so that old one can be deleted)
     ALTER SYSTEM SET UNDO_TABLESPACE='UNDO_TMP';

     -- Delete old UNDO tablespace
     DROP TABLESPACE UNDOTBS1 INCLUDING CONTENTS AND DATAFILES;

     -- Recreate old UNDO tablespace with 1M size and AUTOEXTEND
     CREATE UNDO TABLESPACE UNDOTBS1 DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/undotbs1.dbf'
        SIZE 1M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -- Use newly created UNDO tablespace
     ALTER SYSTEM SET UNDO_TABLESPACE='UNDOTBS1';

     -- Drop temporary UNDO tablespace
     DROP TABLESPACE UNDO_TMP INCLUDING CONTENTS AND DATAFILES;

     ---------------------------------
     -- Shrink REDO log files
     ---------------------------------

     -- Remove original redo logs from fast_recovery_area and create new ones
     ALTER DATABASE ADD LOGFILE GROUP 3 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo03.log') SIZE ${REDO_SIZE}m;
     ALTER DATABASE ADD LOGFILE GROUP 4 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo04.log') SIZE ${REDO_SIZE}m;
     ALTER SYSTEM SWITCH LOGFILE;
     ALTER SYSTEM SWITCH LOGFILE;
     ALTER SYSTEM CHECKPOINT;
     ALTER DATABASE DROP LOGFILE GROUP 1;
     ALTER DATABASE DROP LOGFILE GROUP 2;
     ALTER DATABASE ADD LOGFILE GROUP 1 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo01.log') SIZE ${REDO_SIZE}m REUSE;
     ALTER DATABASE ADD LOGFILE GROUP 2 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo02.log') SIZE ${REDO_SIZE}m REUSE;
     ALTER SYSTEM SWITCH LOGFILE;
     ALTER SYSTEM SWITCH LOGFILE;
     ALTER SYSTEM CHECKPOINT;
     ALTER DATABASE DROP LOGFILE GROUP 3;
     ALTER DATABASE DROP LOGFILE GROUP 4;

     -- Non-managed (OMF) redo logs aren't deleted automatically (REDO GROUP 3 and 4 above)
     -- Need to be deleted manually
     HOST rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo03.log
     HOST rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo04.log

     exit;
EOF

  #TODO: create or replace directory XMLDIR as '${ORACLE_HOME}/rdbms/xml';

fi;

###################################
########### DB SHUTDOWN ###########
###################################

echo "BUILDER: graceful database shutdown"

# Shutdown database gracefully (listener is not yet running)
su -p oracle -c "sqlplus -s / as sysdba" << EOF

   -- Exit on any errors
   WHENEVER SQLERROR EXIT SQL.SQLCODE

   -- Shutdown database gracefully
   shutdown immediate;
   exit;
EOF

###############################
### Compress Database files ###
###############################

echo "BUILDER: compressing database data files"

cd "${ORACLE_BASE}"/oradata
7zzs a "${ORACLE_SID}".7z "${ORACLE_SID}"
chown oracle:dba "${ORACLE_SID}".7z
mv "${ORACLE_SID}".7z "${ORACLE_BASE}"/
# Delete database files but not directory structure,
# that way external mount can mount just a sub directory
find "${ORACLE_SID}" -type f -exec rm "{}" \;
cd - 1> /dev/null

########################
### Install run file ###
########################

echo "BUILDER: installing operational files"

# Move operational files to ${ORACLE_BASE}
mv /install/*.sh "${ORACLE_BASE}"/
mv /install/resetPassword "${ORACLE_BASE}"/
mv /install/createAppUser "${ORACLE_BASE}"/

################################
### Setting file permissions ###
################################

echo "BUILDER: setting file permissions"

chown oracle:dba "${ORACLE_BASE}"/*.sh \
                 "${ORACLE_BASE}"/resetPassword \
                 "${ORACLE_BASE}"/createAppUser

chmod u+x "${ORACLE_BASE}"/*.sh \
          "${ORACLE_BASE}"/resetPassword \
          "${ORACLE_BASE}"/createAppUser

# Setting permissions for all folders so that they can be mounted on tmpfs
# (see https://github.com/gvenzl/oci-oracle-xe/issues/202)
chmod a+rwx -R "${ORACLE_BASE}"/oradata

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
rm -r /var/tmp/oradiag_oracle

# Remove SYS audit files created during install
rm "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/adump/*.aud

# Remove Data Pump log file
rm "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/dpdump/dp.log

# Remove Oracle DB install logs
rm "${ORACLE_HOME}"/config/log/*

# Remove diag files
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/lck/*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/metadata/*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/trace/"${ORACLE_SID}"_*
rm -r "${ORACLE_BASE}"/diag/tnslsnr/*
rm -r "${ORACLE_BASE}"/oradiag_oracle/*

# Remove additional files for REGULAR and SLIM builds
if [ "${BUILD_MODE}" == "REGULAR" ] || [ "${BUILD_MODE}" == "SLIM" ]; then

  echo "BUILDER: further cleanup for REGULAR and SLIM image"

  # Remove APEX directory
  rm -r "${ORACLE_HOME}"/apex

  # Remove JDBC drivers
  rm -r "${ORACLE_HOME}"/jdbc
  rm -r "${ORACLE_HOME}"/jlib

  # Remove components from ORACLE_HOME
  if [ "${BUILD_MODE}" == "SLIM" ]; then

    echo "BUILDER: further cleanup for SLIM image"

    # Remove Oracle Text directory
    rm -r "${ORACLE_HOME}"/ctx

    # Remove XDK
    rm -r "${ORACLE_HOME}"/xdk

    # Remove Oracle Spatial directory
    rm -r "${ORACLE_HOME}"/md

    # Remove demo directory
    rm -r "${ORACLE_HOME}"/demo

    # Remove ODBC samples
    rm -r "${ORACLE_HOME}"/odbc

    # Remove TNS samples
    rm -r "${ORACLE_HOME}"/network/admin/samples

    # Remove NLS demo
    rm -r "${ORACLE_HOME}"/nls/demo

    # Remove hs directory
    rm -r "${ORACLE_HOME}"/hs

    # Remove ldap directory
    rm -r "${ORACLE_HOME}"/ldap

    # Remove precomp directory
    rm -r "${ORACLE_HOME}"/precomp

    # Remove rdbms/demo directory
    rm -r "${ORACLE_HOME}"/rdbms/demo

    # Remove rdbms/jlib directory
    rm -r "${ORACLE_HOME}"/rdbms/jlib

    # Remove rdbms/public directory
    rm -r "${ORACLE_HOME}"/rdbms/public

    # Remove rdbms/jlib directory
    rm -r "${ORACLE_HOME}"/rdbms/xml

    # TODO

  fi;

fi;

# Remove build packages
# Unfortunately microdnf does not automatically uninstall dependencies that have been
# installed with a package, so if you were to uninstall just util-linux, for example,
# it does not automatically also remove gzip again.
rpm -e --nodeps acl bc cryptsetup-libs dbus dbus-common dbus-daemon dbus-libs \
                dbus-tools device-mapper device-mapper-libs \
                elfutils-default-yama-scope elfutils-libs kmod-libs libfdisk \
                libseccomp libutempter net-tools procps-ng \
                systemd systemd-pam util-linux findutils

# Remove dnf cache
microdnf clean all

# Clean lastlog
echo "" > /var/log/lastlog
