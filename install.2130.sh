#!/bin/bash
# Since: September, 2021
# Author: gvenzl
# Name: install.2130.sh
# Description: Install script for Oracle DB XE 21.3.0
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
CDB_SYSAUX_SIZE=560
PDB_SYSAUX_SIZE=330
CDB_SYSTEM_SIZE=875
PDB_SYSTEM_SIZE=272
if [ "${BUILD_MODE}" == "REGULAR" ]; then
  REDO_SIZE=20
  USERS_SIZE=10
  CDB_TEMP_SIZE=10
elif [ "${BUILD_MODE}" == "SLIM" ]; then
  REDO_SIZE=10
  USERS_SIZE=2
  CDB_SYSAUX_SIZE=560
  CDB_TEMP_SIZE=2
fi;

echo "BUILDER: Installing OS dependencies"

# Install installation dependencies
microdnf -y install bc binutils file compat-openssl10 elfutils-libelf ksh sysstat \
                    procps-ng smartmontools make hostname

# Install runtime dependencies
microdnf -y install libnsl glibc glibc-devel libaio libgcc libstdc++ xz

# Install fortran runtime for libora_netlib.so (so that the Intel Math Kernel libraries are no longer needed)
if [ "${BUILD_MODE}" == "REGULAR" ] || [ "${BUILD_MODE}" == "SLIM" ]; then
  microdnf -y install compat-libgfortran-48
fi;

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

##############################################
###### Install and configure Database ########
##############################################

echo "BUILDER: installing database binaries"

# Install Oracle XE
rpm -iv --nodeps /install/oracle-database-xe-21c-1.0-1.ol8.x86_64.rpm

# Set 'oracle' user home directory to ${ORACE_BASE}
usermod -d ${ORACLE_BASE} oracle

# Add listener port and skip validations to conf file
sed -i "s/LISTENER_PORT=/LISTENER_PORT=1521/g" /etc/sysconfig/oracle-xe-21c.conf
sed -i "s/SKIP_VALIDATIONS=false/SKIP_VALIDATIONS=true/g" /etc/sysconfig/oracle-xe-21c.conf

# Disable netca to avoid "No IP address found" issue
mv "${ORACLE_HOME}"/bin/netca "${ORACLE_HOME}"/bin/netca.bak
echo "exit 0" > "${ORACLE_HOME}"/bin/netca
chmod a+x "${ORACLE_HOME}"/bin/netca

echo "BUILDER: configuring database"

# Set random password
ORACLE_PASSWORD=$(date '+%s' | sha256sum | base64 | head -c 8)
(echo "${ORACLE_PASSWORD}"; echo "${ORACLE_PASSWORD}";) | /etc/init.d/oracle-xe-21c configure 

# Stop unconfigured listener
su -p oracle -c "lsnrctl stop"

# Re-enable netca
mv "${ORACLE_HOME}"/bin/netca.bak "${ORACLE_HOME}"/bin/netca

echo "BUILDER: post config database steps"

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

DEFAULT_SERVICE_LISTENER = ${ORACLE_SID}" > "${ORACLE_BASE_HOME}"/network/admin/listener.ora

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

FREE =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = FREE)
    )
  )

FREEPDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = FREEPDB1)
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
" > "${ORACLE_BASE_HOME}"/network/admin/tnsnames.ora

# sqlnet.ora
echo \
"NAMES.DIRECTORY_PATH = (EZCONNECT, TNSNAMES)
# See https://github.com/gvenzl/oci-oracle-xe/issues/43
DISABLE_OOB=ON
BREAK_POLL_SKIP=1000
" > "${ORACLE_BASE_HOME}"/network/admin/sqlnet.ora

chown -R oracle:dba "${ORACLE_BASE_HOME}"/network/admin

# Start listener
su -p oracle -c "lsnrctl start"

####################
### bash_profile ###
####################

# Create .bash_profile for oracle user
echo "BUILDER: creating .bash_profile"
echo \
"export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_BASE_CONFIG=${ORACLE_BASE_CONFIG}
export ORACLE_BASE_HOME=\${ORACLE_BASE}/homes/OraDBHome21cXE
export ORACLE_HOME=\${ORACLE_BASE}/product/21c/dbhomeXE
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

   -- Enable Tuning and Diag packs
   ALTER SYSTEM SET CONTROL_MANAGEMENT_PACK_ACCESS='DIAGNOSTIC+TUNING' SCOPE=SPFILE;

   -- Disable auditing
   ALTER SYSTEM SET AUDIT_TRAIL=NONE SCOPE=SPFILE;
   ALTER SYSTEM SET AUDIT_SYS_OPERATIONS=FALSE SCOPE=SPFILE;

   -- Disable common_user_prefix (needed for OS authenticated user)
   ALTER SYSTEM SET COMMON_USER_PREFIX='' SCOPE=SPFILE;

   -- Remove local_listener entry (using default 1521)
   ALTER SYSTEM SET LOCAL_LISTENER='';
   
   -- Explicitly set CPU_COUNT=2 to avoid memory miscalculation (#64)
   --
   -- This will cause the CPU_COUNT=2 to be written to the SPFILE and then
   -- during memory requirement calculation, which happens before the
   -- hard coding of CPU_COUNT=2, taken as the base input value.
   -- Otherwise, CPU_COUNT is not present, which means it defaults to 0
   -- which will cause the memory requirement calculations to look at the available
   -- CPUs on the system (host instead of container) and derive a wrong value.
   -- On hosts with many CPUs, this could lead to estimate SGA requirements
   -- beyond 2GB RAM, which cannot be set on XE.
   ALTER SYSTEM SET CPU_COUNT=2 SCOPE=SPFILE;

   -- Enable new service name FREE for upwards compatibility with FREE.
   ALTER SESSION SET CONTAINER=XEPDB1;
   exec DBMS_SERVICE.CREATE_SERVICE('freepdb1','freepdb1');
   exec DBMS_SERVICE.START_SERVICE('freepdb1');
   ALTER PLUGGABLE DATABASE XEPDB1 SAVE STATE;

   -- Enable new service name FREE for upwards compatibility with FREE.
   -- DBMS_SERVICE.CREATE_SERVICE will not restart the service after reboot
   -- Hence setting the CDB service the old-fashioned (deprecated) way.
   ALTER SESSION SET CONTAINER=CDB\$ROOT;
   ALTER SYSTEM SET SERVICE_NAMES=XE,FREE;

   -- Reboot of DB
   SHUTDOWN IMMEDIATE;
   STARTUP;

   -- Setup healthcheck user
   CREATE USER OPS\$ORACLE IDENTIFIED EXTERNALLY;
   GRANT CONNECT, SELECT_CATALOG_ROLE TO OPS\$ORACLE;
   -- Permissions to see entries in v\$pdbs
   ALTER USER OPS\$ORACLE SET CONTAINER_DATA = ALL CONTAINER = CURRENT;

   exit;
EOF

###################################
######## FULL INSTALL DONE ########
###################################

# If not building the FULL image, remove and shrink additional components
if [ "${BUILD_MODE}" == "REGULAR" ] || [ "${BUILD_MODE}" == "SLIM" ]; then

  echo "BUILDER: further optimizations for REGULAR and SLIM image"

  # Open PDB\$SEED to READ/WRITE
  echo "BUILDER: Opening PDB\$SEED in READ/WRITE mode"
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Exit on any errors
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     -- Open PDB\$SEED to READ WRITE mode
     ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
     ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ WRITE;

     exit;
EOF

  # Change parameters/settings
  echo "BUILDER: changing database configuration and parameters for REGULAR and SLIM images"
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Exit on any errors
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     -- Deactivate Intel's Math Kernel Libraries
     -- Like with every underscore parameter, DO NOT SET THIS PARAMETER EVER UNLESS YOU KNOW WHAT THE HECK YOU ARE DOING!
     ALTER SYSTEM SET "_dmm_blas_library"='libora_netlib.so' SCOPE=SPFILE;

     -- Disable shared servers (enables faster shutdown)
     ALTER SYSTEM SET SHARED_SERVERS=0;

     -------------------------------------
     -- Disable password profile checks --
     -------------------------------------

     -- Disable password profile checks (can only be done container by container)
     ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED PASSWORD_LIFE_TIME UNLIMITED;

     ALTER SESSION SET CONTAINER=PDB\$SEED;
     ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED PASSWORD_LIFE_TIME UNLIMITED;

     ALTER SESSION SET CONTAINER=XEPDB1;
     ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED PASSWORD_LIFE_TIME UNLIMITED;

     exit;
EOF

  ########################
  # Remove DB components #
  ########################

  # Needs to be run as 'oracle' user (Perl script otherwise fails #TODO: see whether it can be run with su -c somehow instead)
  echo "BUILDER: Removing additional components for REGULAR image"
  su - oracle << EOF
    cd "${ORACLE_HOME}"/rdbms/admin

    # Remove Workspace Manager
    echo "BUILDER: Removing Oracle Workspace Manager"
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1  -C 'CDB\$ROOT' -b builder_remove_workspace_manager_pdbs -d "${ORACLE_HOME}"/rdbms/admin owmuinst.plb
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1  -c 'CDB\$ROOT' -b builder_remove_workspace_manager_cdb -d "${ORACLE_HOME}"/rdbms/admin owmuinst.plb

    # Remove Oracle Database Java Packages
    echo "BUILDER: Removing Oracle Database Java Packages"
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_remove_java_packages -d "${ORACLE_HOME}"/rdbms/admin catnojav.sql

    echo "BUILDER: Removing Oracle Multimedia"
    # Remove Multimedia (dependent on Oracle Database Java Packages)
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -C 'CDB\$ROOT' -b builder_remove_multimedia_pdbs -d "${ORACLE_HOME}"/ord/im/admin imremdo.sql
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'CDB\$ROOT' -b builder_remove_multimedia_cdb -d "${ORACLE_HOME}"/ord/im/admin imremdo.sql

    # Remove Oracle XDK
    echo "BUILDER: Removing Oracle XDK"
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_remove_xdk -d "${ORACLE_HOME}"/xdk/admin rmxml.sql

    # Remove Oracle JServer JAVA Virtual Machine
    echo "BUILDER: Removing Oracle JServer JAVA Virtual Machine"
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_remove_jvm -d "${ORACLE_HOME}"/javavm/install rmjvm.sql

    # Remove Oracle OLAP API
    echo "BUILDER: Removing  Oracle OLAP API"
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -C 'CDB\$ROOT' -b builder_remove_olap_api_pdbs_1 -d "${ORACLE_HOME}"/olap/admin/ olapidrp.plb
    # Needs to be done one by one, otherwise there is a ORA-65023: active transaction exists in container PDB\$SEED
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'PDB\$SEED' -b builder_remove_olap_api_pdbseed_2 -d "${ORACLE_HOME}"/olap/admin/ catnoxoq.sql
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'XEPDB1' -b builder_remove_olap_api_xepdb1_2 -d "${ORACLE_HOME}"/olap/admin/ catnoxoq.sql
    # Remove it from the CDB
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'CDB\$ROOT' -b builder_remove_olap_api_cdb_1 -d "${ORACLE_HOME}"/olap/admin/ olapidrp.plb
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'CDB\$ROOT' -b builder_remove_olap_api_cdb_2 -d "${ORACLE_HOME}"/olap/admin/ catnoxoq.sql

    # Remove OLAP Analytic Workspace
    echo "BUILDER: Removing OLAP Analytic Workspace"
    # Needs to be done one by one, otherwise there is a ORA-65023: active transaction exists in container PDB\$SEED
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'PDB\$SEED' -b builder_remove_olap_workspace_pdb_seed -d "${ORACLE_HOME}"/olap/admin/ catnoaps.sql
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'XEPDB1' -b builder_remove_olap_workspace_xepdb1 -d "${ORACLE_HOME}"/olap/admin/ catnoaps.sql
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'CDB\$ROOT' -b builder_remove_olap_workspace_cdb -d "${ORACLE_HOME}"/olap/admin/ catnoaps.sql

    # Recompile
    echo "BUILDER: Recompiling database objects"
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_recompile_all_objects -d "${ORACLE_HOME}"/rdbms/admin utlrp.sql

    # Remove all log files
    rm "${ORACLE_HOME}"/rdbms/admin/builder_*

    exit;
EOF

  # Drop leftover items
  echo "BUILDER: Dropping leftover Database dictionary objects for REGULAR image"
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Exit on any errors
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     -- Open PDB\$SEED to READ WRITE mode (catcon put it into READY ONLY again)
     ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
     ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ WRITE;

     -- Remove Java VM leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE DBMS_JAVA');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP FUNCTION DBJ_SHORT_NAME');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBMS_JAVA');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBJ_SHORT_NAME');

     ALTER SESSION SET CONTAINER=PDB\$SEED;

     -- Remove Java VM leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE DBMS_JAVA');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP FUNCTION DBJ_SHORT_NAME');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBMS_JAVA');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBJ_SHORT_NAME');

     -- Oracle Multimedia leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_COLOR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_STILLIMAGE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_AVERAGECOLOR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_COLORHISTOGRAM');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_POSITIONALCOLOR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_TEXTURE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FEATURELIST');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDAUDIO');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDIMAGE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDVIDEO');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDOC');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDIMAGESIGNATURE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDICOM');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDATASOURCE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDPLSGWYUTIL');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKSTILLIMAGE1');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKSTILLIMAGE2');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORA_SI_MKSTILLIMAGE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_CHGCONTENT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_CONVERTFORMAT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETTHMBNL');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETSIZEDTHMBNL');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETCONTENT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETCONTENTLNGTH');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETHEIGHT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETWIDTH');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETFORMAT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKRGBCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FINDAVGCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKAVGCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYAVGCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FINDCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_ARRAYCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_APPENDCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FINDPSTNLCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYPSTNLCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FINDTEXTURE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYTEXTURE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKFTRLIST');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SETAVGCLRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SETCLRHSTGRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SETPSTNLCLRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SETTEXTUREFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETAVGCLRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETAVGCLRFTRW');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETCLRHSTGRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETCLRHSTGRFTRW');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETPSTNLCLRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETPSTNLCLRFTRW');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETTEXTUREFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETTEXTUREFTRW');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYFTRLIST');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_DICOM');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_DICOM_ADMIN');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_IMAGE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_AUDIO');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_VIDEO');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_DOC');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_DBRELEASE_DOCS');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_DOCUMENTS');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_DOCUMENT_TYPES');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_CONSTRAINT_NAMES');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_DOCUMENT_REFS');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_CONFORMANCE_VLD_MSGS');

     ALTER SESSION SET CONTAINER=XEPDB1;

     -- Remove Java VM leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE DBMS_JAVA');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP FUNCTION DBJ_SHORT_NAME');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBMS_JAVA');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBJ_SHORT_NAME');

     -- Oracle Multimedia leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_COLOR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_STILLIMAGE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_AVERAGECOLOR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_COLORHISTOGRAM');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_POSITIONALCOLOR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_TEXTURE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FEATURELIST');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDAUDIO');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDIMAGE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDVIDEO');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDOC');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDIMAGESIGNATURE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDICOM');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDATASOURCE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDPLSGWYUTIL');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKSTILLIMAGE1');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKSTILLIMAGE2');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORA_SI_MKSTILLIMAGE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_CHGCONTENT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_CONVERTFORMAT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETTHMBNL');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETSIZEDTHMBNL');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETCONTENT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETCONTENTLNGTH');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETHEIGHT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETWIDTH');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETFORMAT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKRGBCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FINDAVGCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKAVGCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYAVGCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FINDCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_ARRAYCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_APPENDCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYCLRHSTGR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FINDPSTNLCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYPSTNLCLR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_FINDTEXTURE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYTEXTURE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_MKFTRLIST');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SETAVGCLRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SETCLRHSTGRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SETPSTNLCLRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SETTEXTUREFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETAVGCLRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETAVGCLRFTRW');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETCLRHSTGRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETCLRHSTGRFTRW');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETPSTNLCLRFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETPSTNLCLRFTRW');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETTEXTUREFTR');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_GETTEXTUREFTRW');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SI_SCOREBYFTRLIST');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_DICOM');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_DICOM_ADMIN');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_IMAGE');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_AUDIO');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_VIDEO');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORD_DOC');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_DBRELEASE_DOCS');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_DOCUMENTS');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_DOCUMENT_TYPES');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_CONSTRAINT_NAMES');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_DOCUMENT_REFS');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ORDDCM_CONFORMANCE_VLD_MSGS');

     exit;
EOF

  ####################################
  # SLIM Image: Remove DB components #
  ####################################

  if [ "${BUILD_MODE}" == "SLIM" ]; then

    # Needs to be run as 'oracle' user (Perl script otherwise fails #TODO: see whether it can be run with su -c somehow instead)

    echo "BUILDER: Removing additional components for SLIM image"
    su - oracle << EOF
      cd "${ORACLE_HOME}"/rdbms/admin

      # Remove Oracle Text
      echo "BUILDER: Removing Oracle Text"
      "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_remove_text_pdbs -C 'CDB\$ROOT' -d "${ORACLE_HOME}"/ctx/admin catnoctx.sql
      "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_remove_text_cdb -c 'CDB\$ROOT' -d "${ORACLE_HOME}"/ctx/admin catnoctx.sql

      # Remove Spatial
      echo "BUILDER: Removing Oracle Spatial"
      "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -C 'CDB\$ROOT' -b builder_remove_spatial_pdbs -d "${ORACLE_HOME}"/md/admin mddins.sql
      "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'CDB\$ROOT' -b builder_remove_spatial_cdb  -d "${ORACLE_HOME}"/md/admin mddins.sql

      # Remove Locator
      echo "BUILDER: Removing Oracle Locator"
      # Parent script mddinloc.sql does only check for SDO record removed or "OPTION OFF" but the script above leaves it as "REMOVED",
      # therefore this parent script doesn not do anything.
      "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_remove_locator_pdbs -d "${ORACLE_HOME}"/md/admin mddinsl.sql

      # Recompile
      echo "BUILDER: Recompiling database objects"
      "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_recompile_all_objects -d "${ORACLE_HOME}"/rdbms/admin utlrp.sql

      # Remove all log files
      rm "${ORACLE_HOME}"/rdbms/admin/builder_*

      exit;
EOF

    # Drop leftover items
    echo "BUILDER: Dropping leftover Database dictionary objects for SLIM image"
    su -p oracle -c "sqlplus -s / as sysdba" << EOF

       -- Exit on any errors
       WHENEVER SQLERROR EXIT SQL.SQLCODE

       -- Oracle Text leftovers
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE XDB.XDB_DATASTORE_PROC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE XDB.DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE SYS.VALIDATE_CONTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CTX_USER_AUTOSYNC_STATUS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CTX_USER_AUTOSYNC_JOBS');

       -- Remove Spatial leftover components
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER MDDATA CASCADE');

       -- Open PDB\$SEED to READ WRITE mode (catcon put it into READY ONLY again)
       ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
       ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ WRITE;

       ALTER SESSION SET CONTAINER=PDB\$SEED;

       -- Oracle Text leftovers
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE XDB.XDB_DATASTORE_PROC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE XDB.DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE SYS.VALIDATE_CONTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CTX_USER_AUTOSYNC_STATUS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CTX_USER_AUTOSYNC_JOBS');

       -- Remove Spatial leftover components
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER MDDATA CASCADE');

       -- Remove Locator leftover components
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POINT2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POINT3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CURVE2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CURVE3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LINESTRING2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LINESTRING3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POLYGON2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POLYGON3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COLLECTION2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COLLECTION3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTIPOINT2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTIPOINT3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTICURVE2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTICURVE3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTILINESTRING2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTILINESTRING3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTIPOLYGON2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTIPOLYGON3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LONLAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WEBMERCATOR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_KEYWORDARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ADDR_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEO_ADDR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOMETRY_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOMETRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POINT_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ELEM_INFO_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ORDINATE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIM_ELEMENT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIM_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_VPOINT_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MBR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NUMBER_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NUMBER_ARRAYSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_STRING_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_STRING2_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_STRING2_ARRAYSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ROWIDPAIR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ROWIDSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_REGION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_REGIONSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_REGAGGR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_REGAGGRSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RANGE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RANGE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CLOSEST_POINTS_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ORGSCL_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PC_BLK');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TIN_BLK');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_TIN_PC_SYSDATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_TIN_PC_SYSDATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM TFM_PLAN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TFM_CHAIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_GEOMETRY_LAYER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_GEOMETRY_LAYER_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_GEOMETRY_LAYER_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LIST_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_OBJECT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_NSTD_TBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TGL_OBJECT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_EDGE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_OBJECT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TGL_OBJECT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_GEOMETRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_GEOM_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_GEOM_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_VERSION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OWM_INSTALLED');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRS_NAMESPACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRID_CHAIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM TMP_COORD_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM EPSG_PARAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM EPSG_PARAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NTV2_XML_DATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CS_SRS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUM_ENGINEERING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUM_GEODETIC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUM_VERTICAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_COMPOUND');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_ENGINEERING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_GEOCENTRIC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_GEOGRAPHIC2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_GEOGRAPHIC3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_PROJECTED');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_VERTICAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AREA_UNITS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIST_UNITS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ANGLE_UNITS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ELLIPSOIDS_OLD_FORMAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PROJECTIONS_OLD_FORMAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUMS_OLD_FORMAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AVAILABLE_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AVAILABLE_ELEM_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AVAILABLE_NON_ELEM_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_PATHS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PREFERRED_OPS_SYSTEM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PREFERRED_OPS_USER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_REF_SYS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_REF_SYSTEM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_UNITS_OF_MEASURE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PRIME_MERIDIANS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ELLIPSOIDS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_SYS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_AXES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_AXIS_NAMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_METHODS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_PARAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_PARAM_USE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_PARAM_VALS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRIDS_BY_URN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRIDS_BY_URN_PATTERN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TRANSIENT_RULE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TRANSIENT_RULE_SET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRID_LIST');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ELLIPSOIDS_OLD_SNAPSHOT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PROJECTIONS_OLD_SNAPSHOT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUMS_OLD_SNAPSHOT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_FEATURE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ST_TOLERANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TTS_METADATA_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INDEX_HISTOGRAM_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INDEX_HISTOGRAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INDEX_HISTOGRAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_INDEX_HISTOGRAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_INDEX_HISTOGRAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_INDEX_HISTOGRAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_INDEX_HISTOGRAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MY_SDO_INDEX_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INDEX_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_INDEX_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_INDEX_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_INDEX_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_INDEX_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TXN_JOURNAL_GTT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TXN_JOURNAL_REG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIST_METADATA_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIAG_MESSAGES_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_DIAG_MESSAGES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_DIAG_MESSAGES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TXN_IDX_EXP_UPD_RGN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_LRS_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_LRS_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_TOPO_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_TOPO_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_TOPO_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_TOPO_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_TRANSACT_DATA$');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_DATA$');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RELATEMASK_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_3GL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ADMIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGIS_GEOMETRY_COLUMNS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBA_GEOMETRY_COLUMNS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_GEOMETRY_COLUMNS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_GEOMETRY_COLUMNS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGIS_SPATIAL_REFERENCE_SYSTEMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CATALOG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NN_DISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_FILTER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RELATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RTREE_FILTER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RTREE_RELATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WITHIN_DISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LOCATOR_WITHIN_DISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ANYINTERACT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CONTAINS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INSIDE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOUCH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_EQUAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COVERS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COVEREDBY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OVERLAPBDYDISJOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OVERLAPBDYINTERSECT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OVERLAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SPATIAL_INDEX');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SPATIAL_INDEX_V2');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_GEOMETRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_POINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_SURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CURVEPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_LINESTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_POLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_GEOMCOLLECTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTIPOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTICURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTIFURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTILINESTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTIPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CIRCULARSTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_COMPOUNDCURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_GEOMETRY_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_POINT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CURVE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_SURFACE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_LINESTRING_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_POLYGON_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_INTERSECTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_RELATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_TOUCH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CONTAINS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_COVERS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_COVEREDBY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_EQUAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_INSIDE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_OVERLAPBDYDISJOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_OVERLAPBDYINTERSECT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_OVERLAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MBRCOORDLIST');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_STATISTICS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MIGRATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PRIDX');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RTREE_ADMIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM RTREEJOINFUNC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TUNE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHNDIM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHLENGTH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHBYTELEN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHPRECISION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHLEVELS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHENCODE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHDECODE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCELLBNDRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCELLSIZE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSUBSTR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCOLLAPSE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCOMPOSE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCOMMONCODE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHMATCH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHDISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHORDER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGROUP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHJLDATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCLDATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHIDPART');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHIDLPART');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCOMPARE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHNCOMPARE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSUBDIVIDE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSTBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGTBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHINCRLEV');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGETCID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSETCID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHAND');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHOR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHXOR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHENCODE_BYLEVEL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHMAXCODE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_LIGHTSOURCES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_ANIMATIONS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_VIEWFRAMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_SCENES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_3DTHEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_3DTXFMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_LIGHTSOURCES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_ANIMATIONS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_VIEWFRAMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_SCENES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_3DTHEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_3DTXFMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_STYLES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_THEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_STYLES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_THEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBA_SDO_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBA_SDO_STYLES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBA_SDO_THEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_CACHED_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_CACHED_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POLYGONFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LINESTRINGFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTIPOLYGONFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTILINESTRINGFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINTFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POLYGONFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LINESTRINGFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTIPOLYGONFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTILINESTRINGFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINTFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DIMENSION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ASTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ASBINARY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SRID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_X');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_Y');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NUMINTERIORRINGS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM INTERIORRINGN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM EXTERIORRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NUMGEOMETRIES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM GEOMETRYN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DISJOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM TOUCH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM WITHIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OVERLAP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_CONTAINS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM INTERSECTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DIFFERENCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_UNION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CONVEXHULL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CENTROID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM GEOMETRYTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM STARTPOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ENDPOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM BOUNDARY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ENVELOPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ISEMPTY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NUMPOINTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINTN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ISCLOSED');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINTONSURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM AREA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM BUFFER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM EQUALS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SYMMETRICDIFFERENCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_LENGTH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ISSIMPLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ISRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM INTERSECTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM RELATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CROSS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MD_LRS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LRS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDOAGGRTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_UNION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_MBR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_LRS_CONCAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_LRS_CONCAT_3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_CONVEXHULL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_CENTROID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_CONCAT_LINES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_SET_UNION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_CONCAVEHULL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_XML_SCHEMAS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_ANNOTATIONTEXTELEMENT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_ANNOT_TEXTELEMENT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_ANNOTATIONTEXTELEMENT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_ANNOTATION_TEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_ANNOTATION_TEXT_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_ANNOTATION_TEXT_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_UTIL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_JOIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDORIDTABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GET_TAB_SUBPART');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GET_TAB_PART');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PQRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CIRCULARSTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CURVEPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM COMPOUNDCURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM GEOMETRYCOLLECTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM GEOMETRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LINESTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTICURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTILINESTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTIPOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTIPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTISURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEORASTER_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_HISTOGRAM_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OLS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WFS_LOCK');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NETWORK_MANAGER_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NODE_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LINK_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PATH_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NETWORK_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM TRACKER_MSG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LOCATION_MSG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LOCATION_MSG_ARR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LOCATION_MSG_PKD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PROC_MSG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PROC_MSG_ARR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PROC_MSG_PKD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NOTIFICATION_MSG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PRVT_SAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GCDR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WFS_PROCESS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_CSW_SERVICE_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_CSW_SERVICE_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CSW');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POINTINPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TRKR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_MAP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_ANYINTERACT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RASTER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RASTERSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_SRS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_HISTOGRAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GRAYSCALE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_COLORMAP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GCP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GCP_COLLECTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GCPGEOREFTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_CELL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_CELL_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_GEOR_SYSDATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_GEOR_SYSDATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_AUX');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_ADMIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_UTL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_RA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_AGGR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_IP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GDAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PC_PKG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LODS_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PCS_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PC_RECORD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PC_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PC_COLUMN_RECORD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PC_COLUMN_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TIN_PKG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WCS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_CONSTRAINTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_CONSTRAINTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_JAVA_OBJECTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_JAVA_OBJECTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_LOCKS_WM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_LOCKS_WM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_USER_DATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_USER_DATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_HISTORIES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_HISTORIES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_TIMESTAMPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_TIMESTAMPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_UPD_HIST');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_UPD_HIST_TBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_UPD_HIST_N');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_UPD_HIST_NTBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_LINK');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_LINK_NTBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_OP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_OP_NTBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_FEAT_ELEM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_FEAT_ELEM_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_LAYER_FEAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_LAYER_FEAT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_FEATURE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_FEATURE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_PARTITION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_MEM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ROUTER_PARTITION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ELOCATION_EDGE_LINK_LEVEL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ROUTER_TIMEZONE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NDM_TRAFFIC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NFE_MODEL_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NFE_MODEL_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NFE_MODEL_FTLAYER_REL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NFE_MODEL_FTLAYER_REL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NFE_MODEL_WORKSPACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NFE_MODEL_WORKSPACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACT_POINT_FEAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACT_POINT_FEAT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACT_LINE_FEAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACT_LINE_FEAT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACTION_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NFE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OBJ_TRACING');

       ALTER SESSION SET CONTAINER=XEPDB1;

       -- Oracle Text leftovers
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE XDB.XDB_DATASTORE_PROC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE XDB.DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE SYS.VALIDATE_CONTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CTX_USER_AUTOSYNC_STATUS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CTX_USER_AUTOSYNC_JOBS');

       -- Remove Spatial leftover components
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER MDDATA CASCADE');

       -- Remove Locator leftover components
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POINT2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POINT3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CURVE2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CURVE3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LINESTRING2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LINESTRING3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POLYGON2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POLYGON3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COLLECTION2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COLLECTION3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTIPOINT2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTIPOINT3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTICURVE2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTICURVE3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTILINESTRING2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTILINESTRING3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTIPOLYGON2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MULTIPOLYGON3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LONLAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WEBMERCATOR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_KEYWORDARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ADDR_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEO_ADDR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOMETRY_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOMETRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POINT_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ELEM_INFO_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ORDINATE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIM_ELEMENT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIM_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_VPOINT_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MBR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NUMBER_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NUMBER_ARRAYSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_STRING_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_STRING2_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_STRING2_ARRAYSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ROWIDPAIR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ROWIDSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_REGION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_REGIONSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_REGAGGR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_REGAGGRSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RANGE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RANGE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CLOSEST_POINTS_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ORGSCL_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PC_BLK');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TIN_BLK');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_TIN_PC_SYSDATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_TIN_PC_SYSDATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM TFM_PLAN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TFM_CHAIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_GEOMETRY_LAYER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_GEOMETRY_LAYER_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_GEOMETRY_LAYER_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LIST_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_OBJECT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_NSTD_TBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TGL_OBJECT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_EDGE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_OBJECT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TGL_OBJECT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_GEOMETRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_GEOM_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_GEOM_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_VERSION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OWM_INSTALLED');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRS_NAMESPACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRID_CHAIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM TMP_COORD_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM EPSG_PARAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM EPSG_PARAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NTV2_XML_DATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CS_SRS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUM_ENGINEERING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUM_GEODETIC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUM_VERTICAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_COMPOUND');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_ENGINEERING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_GEOCENTRIC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_GEOGRAPHIC2D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_GEOGRAPHIC3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_PROJECTED');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CRS_VERTICAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AREA_UNITS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIST_UNITS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ANGLE_UNITS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ELLIPSOIDS_OLD_FORMAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PROJECTIONS_OLD_FORMAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUMS_OLD_FORMAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AVAILABLE_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AVAILABLE_ELEM_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AVAILABLE_NON_ELEM_OPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_PATHS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PREFERRED_OPS_SYSTEM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PREFERRED_OPS_USER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_REF_SYS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_REF_SYSTEM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_UNITS_OF_MEASURE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PRIME_MERIDIANS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ELLIPSOIDS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_SYS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_AXES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_AXIS_NAMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_METHODS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_PARAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_PARAM_USE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COORD_OP_PARAM_VALS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRIDS_BY_URN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRIDS_BY_URN_PATTERN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TRANSIENT_RULE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TRANSIENT_RULE_SET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SRID_LIST');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ELLIPSOIDS_OLD_SNAPSHOT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PROJECTIONS_OLD_SNAPSHOT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DATUMS_OLD_SNAPSHOT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_FEATURE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ST_TOLERANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TTS_METADATA_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INDEX_HISTOGRAM_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INDEX_HISTOGRAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INDEX_HISTOGRAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_INDEX_HISTOGRAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_INDEX_HISTOGRAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_INDEX_HISTOGRAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_INDEX_HISTOGRAMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MY_SDO_INDEX_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INDEX_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_INDEX_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_INDEX_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_INDEX_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_INDEX_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TXN_JOURNAL_GTT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TXN_JOURNAL_REG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIST_METADATA_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_DIAG_MESSAGES_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_DIAG_MESSAGES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_DIAG_MESSAGES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TXN_IDX_EXP_UPD_RGN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_LRS_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_LRS_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_TOPO_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_TOPO_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_TOPO_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_TOPO_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_TRANSACT_DATA$');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_DATA$');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RELATEMASK_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_3GL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ADMIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGIS_GEOMETRY_COLUMNS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBA_GEOMETRY_COLUMNS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_GEOMETRY_COLUMNS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_GEOMETRY_COLUMNS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGIS_SPATIAL_REFERENCE_SYSTEMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CATALOG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NN_DISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_FILTER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RELATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RTREE_FILTER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RTREE_RELATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WITHIN_DISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LOCATOR_WITHIN_DISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ANYINTERACT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CONTAINS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INSIDE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOUCH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_EQUAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COVERS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_COVEREDBY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OVERLAPBDYDISJOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OVERLAPBDYINTERSECT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OVERLAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SPATIAL_INDEX');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SPATIAL_INDEX_V2');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_GEOMETRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_POINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_SURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CURVEPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_LINESTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_POLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_GEOMCOLLECTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTIPOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTICURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTIFURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTILINESTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_MULTIPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CIRCULARSTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_COMPOUNDCURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_GEOMETRY_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_POINT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CURVE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_SURFACE_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_LINESTRING_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_POLYGON_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_INTERSECTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_RELATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_TOUCH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_CONTAINS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_COVERS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_COVEREDBY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_EQUAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_INSIDE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_OVERLAPBDYDISJOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_OVERLAPBDYINTERSECT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_OVERLAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MBRCOORDLIST');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_STATISTICS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_MIGRATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PRIDX');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RTREE_ADMIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM RTREEJOINFUNC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TUNE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHNDIM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHLENGTH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHBYTELEN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHPRECISION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHLEVELS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHENCODE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHDECODE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCELLBNDRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCELLSIZE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSUBSTR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCOLLAPSE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCOMPOSE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCOMMONCODE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHMATCH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHDISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHORDER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGROUP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHJLDATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCLDATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHIDPART');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHIDLPART');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCOMPARE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHNCOMPARE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSUBDIVIDE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSTBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGTBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHCBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGBIT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHINCRLEV');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHGETCID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHSETCID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHAND');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHOR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHXOR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHENCODE_BYLEVEL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM HHMAXCODE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_LIGHTSOURCES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_ANIMATIONS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_VIEWFRAMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_SCENES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_3DTHEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_3DTXFMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_LIGHTSOURCES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_ANIMATIONS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_VIEWFRAMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_SCENES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_3DTHEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_3DTXFMS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_STYLES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_THEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_STYLES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_THEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBA_SDO_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBA_SDO_STYLES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBA_SDO_THEMES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_CACHED_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_CACHED_MAPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POLYGONFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LINESTRINGFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTIPOLYGONFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTILINESTRINGFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINTFROMTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POLYGONFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LINESTRINGFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTIPOLYGONFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTILINESTRINGFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINTFROMWKB');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DIMENSION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ASTEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ASBINARY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SRID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_X');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_Y');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NUMINTERIORRINGS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM INTERIORRINGN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM EXTERIORRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NUMGEOMETRIES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM GEOMETRYN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DISJOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM TOUCH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM WITHIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OVERLAP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_CONTAINS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM INTERSECTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DIFFERENCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_UNION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CONVEXHULL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CENTROID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM GEOMETRYTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM STARTPOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ENDPOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM BOUNDARY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ENVELOPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ISEMPTY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NUMPOINTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINTN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ISCLOSED');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINTONSURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM AREA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM BUFFER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM EQUALS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SYMMETRICDIFFERENCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DISTANCE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM OGC_LENGTH');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ISSIMPLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ISRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM INTERSECTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM RELATE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CROSS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MD_LRS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LRS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDOAGGRTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_UNION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_MBR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_LRS_CONCAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_LRS_CONCAT_3D');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_CONVEXHULL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_CENTROID');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_CONCAT_LINES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_SET_UNION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_AGGR_CONCAVEHULL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_XML_SCHEMAS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_ANNOTATIONTEXTELEMENT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_ANNOT_TEXTELEMENT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_ANNOTATIONTEXTELEMENT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ST_ANNOTATION_TEXT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_ANNOTATION_TEXT_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_ANNOTATION_TEXT_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_UTIL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_JOIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDORIDTABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GET_TAB_SUBPART');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GET_TAB_PART');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PQRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CIRCULARSTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM CURVEPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM COMPOUNDCURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM GEOMETRYCOLLECTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM GEOMETRY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LINESTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTICURVE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTILINESTRING');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTIPOINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTIPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM MULTISURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POINT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM POLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SURFACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEORASTER_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_HISTOGRAM_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OLS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WFS_LOCK');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NETWORK_MANAGER_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NODE_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LINK_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PATH_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NETWORK_T');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM TRACKER_MSG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LOCATION_MSG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LOCATION_MSG_ARR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM LOCATION_MSG_PKD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PROC_MSG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PROC_MSG_ARR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PROC_MSG_PKD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM NOTIFICATION_MSG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PRVT_SAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_SAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GCDR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WFS_PROCESS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_CSW_SERVICE_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_CSW_SERVICE_INFO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_CSW');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_POINTINPOLYGON');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TRKR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_MAP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TOPO_ANYINTERACT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RASTER');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_RASTERSET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_SRS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_HISTOGRAM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GRAYSCALE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_COLORMAP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GCP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GCP_COLLECTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GCPGEOREFTYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_CELL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_CELL_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_GEOR_SYSDATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_GEOR_SYSDATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_AUX');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_ADMIN');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_UTL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_RA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_AGGR');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_IP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_GEOR_GDAL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PC_PKG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_LODS_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_PCS_TYPE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PC_RECORD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PC_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PC_COLUMN_RECORD');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM PC_COLUMN_TABLE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_TIN_PKG');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_WCS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_CONSTRAINTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_CONSTRAINTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_JAVA_OBJECTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_JAVA_OBJECTS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_LOCKS_WM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_LOCKS_WM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_USER_DATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_USER_DATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_HISTORIES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_HISTORIES');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_TIMESTAMPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_TIMESTAMPS');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_UPD_HIST');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_UPD_HIST_TBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_UPD_HIST_N');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_UPD_HIST_NTBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_LINK');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_LINK_NTBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_OP');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_OP_NTBL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_FEAT_ELEM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_FEAT_ELEM_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_LAYER_FEAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_LAYER_FEAT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NETWORK_FEATURE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NETWORK_FEATURE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_PARTITION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NET_MEM');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ROUTER_PARTITION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ELOCATION_EDGE_LINK_LEVEL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_ROUTER_TIMEZONE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NDM_TRAFFIC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NFE_MODEL_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NFE_MODEL_METADATA');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NFE_MODEL_FTLAYER_REL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NFE_MODEL_FTLAYER_REL');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM USER_SDO_NFE_MODEL_WORKSPACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM ALL_SDO_NFE_MODEL_WORKSPACE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACT_POINT_FEAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACT_POINT_FEAT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACT_LINE_FEAT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACT_LINE_FEAT_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACTION');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_INTERACTION_ARRAY');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_NFE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM SDO_OBJ_TRACING');

       exit;
EOF

  fi;

  #######################################################
  ################# Shrink data files ###################
  #######################################################

  #######################################################
  # Clean additional DB components to shrink data files #
  #######################################################

  su -p oracle -c "sqlplus -s / as sysdba" <<EOF

     -- Exit on any error
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     -- Create temporary tablespace to move objects
     CREATE TABLESPACE builder_temp DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/builder_temp.dbf' SIZE 100m;

     -- Clean up METASTYLESHEET LOBs sitting at the end of the SYSTEM tablespace
     ALTER TABLE metastylesheet MOVE LOB(stylesheet) STORE AS (TABLESPACE BUILDER_TEMP);
     ALTER TABLE metastylesheet MOVE LOB(stylesheet) STORE AS (TABLESPACE SYSTEM);

     -- Clean pdb_sync\$ table in CDB\$ROOT
     -- This is part of the REPLAY UPGRADE PDB feature that is not needed in REGULAR and SLIM
     TRUNCATE TABLE pdb_sync\$;
     ALTER INDEX i_pdbsync4 REBUILD;
     ALTER INDEX i_pdbsync3 REBUILD;
     ALTER INDEX i_pdbsync2 REBUILD;
     ALTER INDEX i_pdbsync1 REBUILD;

     -- Reinsert initial row to reinitialize replay counter, as found in \$ORACLE_HOME/rdbms/admin/dcore.bsq
     INSERT INTO pdb_sync\$(scnwrp, scnbas, ctime, name, opcode, flags, replay#)
        VALUES (0, 0, sysdate, 'PDB\$LASTREPLAY', -1, 0, 0);
     COMMIT;

     -- Clean up fed\$binds blocks at the end of SYSTEM tablespace
     ALTER TABLE fed\$binds MOVE TABLESPACE BUILDER_TEMP;
     ALTER INDEX i_fed_apps\$ REBUILD;
     ALTER INDEX i_fed_binds\$ REBUILD;
     ALTER TABLE fed\$binds MOVE TABLESPACE SYSTEM;

     -- Drop temporary tablespace
     DROP TABLESPACE builder_temp INCLUDING CONTENTS AND DATAFILES;

    exit;

EOF

  ############################
  # Shrink actual data files #
  ############################
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Exit on any error
     WHENEVER SQLERROR EXIT SQL.SQLCODE

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

     ALTER TABLESPACE TEMP SHRINK SPACE;
     ALTER DATABASE TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/temp01.dbf' RESIZE ${CDB_TEMP_SIZE}M;
     ALTER DATABASE TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/temp01.dbf'
     AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     --------------------------------------
     ALTER SESSION SET CONTAINER=PDB\$SEED;
     --------------------------------------

     CREATE TEMPORARY TABLESPACE TEMP_TMP TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/temp_tmp.dbf'
        SIZE 2M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER DATABASE DEFAULT TEMPORARY TABLESPACE TEMP_TMP;

     DROP TABLESPACE TEMP INCLUDING CONTENTS AND DATAFILES;

     CREATE TEMPORARY TABLESPACE TEMP TEMPFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/temp01.dbf'
        SIZE 2M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     ALTER DATABASE DEFAULT TEMPORARY TABLESPACE TEMP;

     DROP TABLESPACE TEMP_TMP INCLUDING CONTENTS AND DATAFILES;

     -----------------------------------
     ALTER SESSION SET CONTAINER=XEPDB1;
     -----------------------------------

     ALTER TABLESPACE TEMP SHRINK SPACE;
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

     -- Create new temporary UNDO tablespace
     CREATE UNDO TABLESPACE UNDO_TMP DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/undotbs_tmp.dbf'
        SIZE 1M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -- Use new temporary UNDO tablespace (so that old one can be deleted)
     ALTER SYSTEM SET UNDO_TABLESPACE='UNDO_TMP';

     -- Delete old UNDO tablespace
     DROP TABLESPACE UNDOTBS1 INCLUDING CONTENTS AND DATAFILES;

     -- Recreate old UNDO tablespace with 1M size and AUTOEXTEND
     CREATE UNDO TABLESPACE UNDOTBS1 DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/undotbs01.dbf'
        SIZE 1M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -- Use newly created UNDO tablespace
     ALTER SYSTEM SET UNDO_TABLESPACE='UNDOTBS1';

     -- Drop temporary UNDO tablespace
     DROP TABLESPACE UNDO_TMP INCLUDING CONTENTS AND DATAFILES;

     --------------------------------------
     ALTER SESSION SET CONTAINER=PDB\$SEED;
     --------------------------------------

     -- Create new temporary UNDO tablespace
     CREATE UNDO TABLESPACE UNDO_TMP DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/undotbs_tmp.dbf'
        SIZE 1M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -- Use new temporary UNDO tablespace (so that old one can be deleted)
     ALTER SYSTEM SET UNDO_TABLESPACE='UNDO_TMP';

     -- Delete old UNDO tablespace
     DROP TABLESPACE UNDOTBS1 INCLUDING CONTENTS AND DATAFILES;

     -- Recreate old UNDO tablespace with 1M size and AUTOEXTEND
     CREATE UNDO TABLESPACE UNDOTBS1 DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/pdbseed/undotbs01.dbf'
        SIZE 1M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -- Use newly created UNDO tablespace
     ALTER SYSTEM SET UNDO_TABLESPACE='UNDOTBS1';

     -- Drop temporary UNDO tablespace
     DROP TABLESPACE UNDO_TMP INCLUDING CONTENTS AND DATAFILES;

     -----------------------------------
     ALTER SESSION SET CONTAINER=XEPDB1;
     -----------------------------------

     -- Create new temporary UNDO tablespace
     CREATE UNDO TABLESPACE UNDO_TMP DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/undotbs_tmp.dbf'
        SIZE 1M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -- Use new temporary UNDO tablespace (so that old one can be deleted)
     ALTER SYSTEM SET UNDO_TABLESPACE='UNDO_TMP';
     ALTER SYSTEM CHECKPOINT;

     -- Delete old UNDO tablespace
     DROP TABLESPACE UNDOTBS1 INCLUDING CONTENTS AND DATAFILES;

     -- Recreate old UNDO tablespace with 1M size and AUTOEXTEND
     CREATE UNDO TABLESPACE UNDOTBS1 DATAFILE '${ORACLE_BASE}/oradata/${ORACLE_SID}/XEPDB1/undotbs01.dbf'
        SIZE 1M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

     -- Use newly created UNDO tablespace
     ALTER SYSTEM SET UNDO_TABLESPACE='UNDOTBS1';
     ALTER SYSTEM CHECKPOINT;

     -- Drop temporary UNDO tablespace
     DROP TABLESPACE UNDO_TMP INCLUDING CONTENTS AND DATAFILES;

     ---------------------------------
     -- Shrink REDO log files
     ---------------------------------

     ALTER SESSION SET CONTAINER=CDB\$ROOT;

     -- Remove original redo logs and create new ones
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
     HOST rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo03.log
     ALTER DATABASE ADD LOGFILE GROUP 1 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo01.log') SIZE ${REDO_SIZE}m REUSE;
     ALTER DATABASE ADD LOGFILE GROUP 2 ('${ORACLE_BASE}/oradata/${ORACLE_SID}/redo02.log') SIZE ${REDO_SIZE}m REUSE;
     ALTER SYSTEM SWITCH LOGFILE;
     ALTER SYSTEM SWITCH LOGFILE;
     ALTER SYSTEM CHECKPOINT;
     ALTER DATABASE DROP LOGFILE GROUP 4;
     HOST rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo04.log
     ALTER DATABASE DROP LOGFILE GROUP 5;
     HOST rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo05.log
     ALTER DATABASE DROP LOGFILE GROUP 6;
     HOST rm "${ORACLE_BASE}"/oradata/"${ORACLE_SID}"/redo06.log

     exit;
EOF

  # Close PDB\$SEED to READ ONLY again
  echo "BUILDER: Opening PDB\$SEED in READ ONLY (default) mode"
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Exit on any errors
     WHENEVER SQLERROR EXIT SQL.SQLCODE

     -- Open PDB\$SEED to READ WRITE mode
     ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
     ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ ONLY;

     exit;
EOF

fi;

###################################
########### DB SHUTDOWN ###########
###################################

echo "BUILDER: graceful database shutdown"

# Shutdown database gracefully
su -p oracle -c "sqlplus -s / as sysdba" << EOF

   -- Exit on any errors
   WHENEVER SQLERROR EXIT SQL.SQLCODE

   -- Shutdown database gracefully
   SHUTDOWN IMMEDIATE;

   exit;
EOF

# Stop listener
su -p oracle -c "lsnrctl stop"

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
/sbin/chkconfig --del oracle-xe-21c
rm /etc/init.d/oracle-xe-21c
rm /etc/sysconfig/oracle-xe-21c.conf
rm -r /var/log/oracle-database-xe-21c
rm -r /tmp/*

# Remove SYS audit directories and files created during install
rm -r "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/adump/*
rm -r "${ORACLE_BASE}"/audit/"${ORACLE_SID}"/*

# Remove Data Pump log file
rm "${ORACLE_BASE}"/admin/"${ORACLE_SID}"/dpdump/dp.log

# Remove Oracle DB install logs
rm    "${ORACLE_BASE}"/cfgtoollogs/dbca/XE/*
rm    "${ORACLE_BASE}"/cfgtoollogs/netca/*
rm    "${ORACLE_BASE}"/cfgtoollogs/roohctl/*
rm -r "${ORACLE_BASE_HOME}"/cfgtoollogs/sqlpatch/*
rm    "${ORACLE_BASE}"/oraInventory/logs/*
rm -r "${ORACLE_BASE_HOME}"/log/*
rm -r "${ORACLE_BASE_HOME}"/rdbms/log/*

# Remove diag files
rm -r "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/incident/*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/lck/*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/metadata/*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/trace/"${ORACLE_SID}"_*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/stage/*
rm -r "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/trace/cdmp_*
rm -r "${ORACLE_BASE}"/diag/tnslsnr/*

# Remove log4j-containing ndmserver.ear
rm "${ORACLE_HOME}"/md/jlib/ndmserver.ear*

# Remove additional files for NOMRAL and SLIM builds
if [ "${BUILD_MODE}" == "REGULAR" ] || [ "${BUILD_MODE}" == "SLIM" ]; then

  echo "BUILDER: further cleanup for REGULAR and SLIM image"

  # Remove OPatch and QOpatch
  rm -r "${ORACLE_HOME}"/OPatch
  rm -r "${ORACLE_HOME}"/QOpatch

  # Remove assistants
  rm -r "${ORACLE_HOME}"/assistants

  # Remove inventory directory
  rm -r "${ORACLE_HOME}"/inventory

  # Remove JDBC drivers
  rm -r "${ORACLE_HOME}"/jdbc
  rm -r "${ORACLE_HOME}"/jlib
  rm -r "${ORACLE_HOME}"/ucp

  # Remove Intel's Math kernel libraries
  rm "${ORACLE_HOME}"/lib/libmkl_*

  # Remove zip artifacts in $ORACLE_HOME/lib
  rm "${ORACLE_HOME}"/lib/*.zip

  # Remove lib/*.jar files
  rm "${ORACLE_HOME}"/lib/*.jar

  # Remove unnecessary timezone information
  rm    "${ORACLE_HOME}"/oracore/zoneinfo/readme.txt
  rm    "${ORACLE_HOME}"/oracore/zoneinfo/timezdif.csv
  rm -r "${ORACLE_HOME}"/oracore/zoneinfo/big
  rm -r "${ORACLE_HOME}"/oracore/zoneinfo/little
  rm    "${ORACLE_HOME}"/oracore/zoneinfo/timezone*
  mv    "${ORACLE_HOME}"/oracore/zoneinfo/timezlrg_35.dat "${ORACLE_HOME}"/oracore/zoneinfo/current.dat
  rm    "${ORACLE_HOME}"/oracore/zoneinfo/timezlrg*
  mv    "${ORACLE_HOME}"/oracore/zoneinfo/current.dat "${ORACLE_HOME}"/oracore/zoneinfo/timezlrg_35.dat

  # Remove Multimedia
  rm -r "${ORACLE_HOME}"/ord/im

  # Remove Oracle XDK
  rm -r "${ORACLE_HOME}"/xdk

  # Remove JServer JAVA Virtual Machine
  rm -r  "${ORACLE_HOME}"/javavm

  # Remove Java JDK
  rm -r "${ORACLE_HOME}"/jdk

  # Remove rdbms/jlib
  rm -r "${ORACLE_HOME}"/rdbms/jlib

  # Remove OLAP
  rm -r "${ORACLE_HOME}"/olap
  rm "${ORACLE_HOME}"/lib/libolapapi.so

  # Remove Cluster Ready Services
  rm -r "${ORACLE_HOME}"/crs

  # Remove Cluster Verification Utility (CVU)
  rm -r "${ORACLE_HOME}"/cv

  # Remove everything in install directory except orabasetab (needed for read-only homes)
  mv "${ORACLE_HOME}"/install/orabasetab "${ORACLE_HOME}"/
  rm -r "${ORACLE_HOME}"/install/*
  mv "${ORACLE_HOME}"/orabasetab "${ORACLE_HOME}"/install/

  # Remove network/jlib directory
  rm -r "${ORACLE_HOME}"/network/jlib

  # Remove network/tools directory
  rm -r "${ORACLE_HOME}"/network/tools

  # Remove opmn directory
  rm -r "${ORACLE_HOME}"/opmn

  # Remove oml4py directory
  rm -r "${ORACLE_HOME}"/oml4py

  # Remove python directory
  rm -r "${ORACLE_HOME}"/python

  # Remove unnecessary binaries (see http://yong321.freeshell.org/computer/oraclebin.html)
  rm "${ORACLE_HOME}"/bin/acfs*       # ACFS File system components
  rm "${ORACLE_HOME}"/bin/adrci       # Automatic Diagnostic Repository Command Interpreter
  rm "${ORACLE_HOME}"/bin/agtctl      # Multi-Threaded extproc agent control utility
  rm "${ORACLE_HOME}"/bin/afd*        # ASM Filter Drive components
  rm "${ORACLE_HOME}"/bin/amdu        # ASM Disk Utility
  rm "${ORACLE_HOME}"/bin/dg4*        # Database Gateway
  rm "${ORACLE_HOME}"/bin/dgmgrl      # Data Guard Manager CLI
  rm "${ORACLE_HOME}"/bin/dbnest*     # DataBase NEST
  rm "${ORACLE_HOME}"/bin/orion       # ORacle IO Numbers benchmark tool
  rm "${ORACLE_HOME}"/bin/oms_daemon  # Oracle Memory Speed (PMEM support) daemon
  rm "${ORACLE_HOME}"/bin/omsfscmds   # Oracle Memory Speed command line utility
  rm "${ORACLE_HOME}"/bin/proc        # Pro*C/C++ Precompiler
  rm "${ORACLE_HOME}"/bin/procob      # Pro COBOL Precompiler
  rm "${ORACLE_HOME}"/bin/renamedg    # Rename Disk Group binary

  # Replace `orabase` with static path shell script
  su -p oracle -c "echo 'echo ${ORACLE_BASE}' > ${ORACLE_HOME}/bin/orabase"

  # Replace `orabasehome` with static path shell script
  su -p oracle -c "echo 'echo ${ORACLE_BASE_HOME}' > ${ORACLE_HOME}/bin/orabasehome"

  # Replace `orabaseconfig` with static path shell script
  su -p oracle -c "echo 'echo ${ORACLE_BASE_CONFIG}' > ${ORACLE_HOME}/bin/orabaseconfig"

  # Remove unnecessary libraries
  rm "${ORACLE_HOME}"/lib/libmle.so   # Multilingual Engine
  rm "${ORACLE_HOME}"/lib/libopc.so   # Oracle Public Cloud
  rm "${ORACLE_HOME}"/lib/libosbws.so # Oracle Secure Backup Cloud Module
  rm "${ORACLE_HOME}"/lib/libra.so    # Recovery Appliance

  # Remove not needed packages
  # Use rpm instad of microdnf to allow removing packages regardless of their dependencies
  rpm -e --nodeps glibc-devel glibc-headers kernel-headers libpkgconf libxcrypt-devel \
                  pkgconf pkgconf-m4 pkgconf-pkg-config

  # Remove components from ORACLE_HOME
  if [ "${BUILD_MODE}" == "SLIM" ]; then

    echo "BUILDER: further cleanup for SLIM image"

    # Remove Oracle Text directory
    rm -r "${ORACLE_HOME}"/ctx
    rm "${ORACLE_HOME}"/bin/ctx*        # Oracle Text binaries

    # Remove demo directory
    rm -r "${ORACLE_HOME}"/demo

    # Remove ODBC samples
    rm -r "${ORACLE_HOME}"/odbc

    # Remove TNS samples
    rm -r "${ORACLE_HOME}"/network/admin/samples

    # Remove NLS LBuilder
    rm -r "${ORACLE_HOME}"/nls/lbuilder

    # Remove hs directory
    rm -r "${ORACLE_HOME}"/hs

    # DO NOT remove ldap directory.
    # Some message files (mesg/*.msb) are needed for ALTER USER ... IDENTIFIED BY
    # TODO: Clean up not needed ldap files
    #rm -r "${ORACLE_HOME}"/ldap

    # Remove precomp directory
    rm -r "${ORACLE_HOME}"/precomp

    # Remove rdbms/public directory
    rm -r "${ORACLE_HOME}"/rdbms/public

    # Remove rdbms/jlib directory
    rm -r "${ORACLE_HOME}"/rdbms/xml

    # Remove Spatial
    rm -r "${ORACLE_HOME}"/md

    # Remove ord directory
    rm -r "${ORACLE_HOME}"/ord

    # Remove Oracle R
    rm -r "${ORACLE_HOME}"/R

    # Remove deinstall directory
    rm -r "${ORACLE_HOME}"/deinstall

    # Remove Oracle Universal Installer
    rm -r "${ORACLE_HOME}"/oui

    # Remove Perl
    rm -r "${ORACLE_HOME}"/perl

    # Remove unnecessary binaries
    rm "${ORACLE_HOME}"/bin/cursize    # Cursor Size binary
    rm "${ORACLE_HOME}"/bin/dbfs*      # DataBase File System
    rm "${ORACLE_HOME}"/bin/ORE        # Oracle R Enterprise
    rm "${ORACLE_HOME}"/bin/rman       # Oracle Recovery Manager
    rm "${ORACLE_HOME}"/bin/wrap       # PL/SQL Wrapper

    # Remove unnecessary libraries
    rm "${ORACLE_HOME}"/lib/asm* # Oracle Automatic Storage Management
    rm "${ORACLE_HOME}"/lib/ore.so

  fi;

fi;

# Remove installation dependencies
# Use rpm instead of microdnf to allow removing packages regardless of dependencies specified by the Oracle XE RPM
rpm -e --nodeps acl bc binutils cryptsetup-libs dbus dbus-common dbus-daemon \
                dbus-libs dbus-tools device-mapper device-mapper-libs diffutils \
                elfutils-default-yama-scope elfutils-libs file findutils hostname \
                kmod-libs ksh libfdisk libseccomp libutempter lm_sensors-libs \
                make procps-ng smartmontools sysstat systemd systemd-pam util-linux xz

# Remove dnf cache
microdnf clean all

# Clean lastlog
echo "" > /var/log/lastlog
