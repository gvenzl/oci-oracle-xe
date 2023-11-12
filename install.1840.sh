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
if [ "${BUILD_MODE}" == "REGULAR" ]; then
  REDO_SIZE=20
  USERS_SIZE=10
  CDB_TEMP_SIZE=10
#  CDB_SYSAUX_SIZE=464
elif [ "${BUILD_MODE}" == "SLIM" ]; then
  REDO_SIZE=10
  USERS_SIZE=2
  CDB_TEMP_SIZE=2
#  CDB_SYSAUX_SIZE=464
fi;

echo "BUILDER: Installing OS dependencies"

# Install installation dependencies
microdnf -y install bc binutils file elfutils-libelf ksh sysstat procps-ng smartmontools make net-tools hostname

# Install runtime dependencies
microdnf -y install libnsl glibc libaio libgcc libstdc++ xz

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
rpm -iv --nodeps /install/oracle-database-xe-18c-1.0-1.x86_64.rpm

# Set 'oracle' user home directory to ${ORACE_BASE}
usermod -d ${ORACLE_BASE} oracle

# Add listener port and skip validations to conf file
sed -i "s/LISTENER_PORT=/LISTENER_PORT=1521/g" /etc/sysconfig/oracle-xe-18c.conf
sed -i "s/SKIP_VALIDATIONS=false/SKIP_VALIDATIONS=true/g" /etc/sysconfig/oracle-xe-18c.conf

# Disable netca to avoid "No IP address found" issue
mv "${ORACLE_HOME}"/bin/netca "${ORACLE_HOME}"/bin/netca.bak
echo "exit 0" > "${ORACLE_HOME}"/bin/netca
chmod a+x "${ORACLE_HOME}"/bin/netca

echo "BUILDER: configuring database"

# Set random password
ORACLE_PASSWORD=$(date '+%s' | sha256sum | base64 | head -c 8)
(echo "${ORACLE_PASSWORD}"; echo "${ORACLE_PASSWORD}";) | /etc/init.d/oracle-xe-18c configure 

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
" > "${ORACLE_HOME}"/network/admin/tnsnames.ora

# sqlnet.ora
echo "NAMES.DIRECTORY_PATH = (EZCONNECT, TNSNAMES)" > "${ORACLE_HOME}"/network/admin/sqlnet.ora

chown -R oracle:dba "${ORACLE_HOME}"/network/admin

# Start listener
su -p oracle -c "lsnrctl start"

####################
### bash_profile ###
####################

# Create .bash_profile for oracle user
echo "BUILDER: creating .bash_profile"
echo \
"export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_HOME=\${ORACLE_BASE}/product/18c/dbhomeXE
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

   -- Disable controlfile splitbrain check
   -- Like with every underscore parameter, DO NOT SET THIS PARAMETER EVER UNLESS YOU KNOW WHAT THE HECK YOU ARE DOING!
   ALTER SYSTEM SET "_CONTROLFILE_SPLIT_BRAIN_CHECK"=FALSE;

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

     -------------------------------
     -- Remove HR schema from PDB --
     -------------------------------

     ALTER SESSION SET CONTAINER=XEPDB1;
     DROP user HR cascade;

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

    echo "BUILDER: Removing Oracle Multimedia"
    # Remove Multimedia (dependent on Oracle Database Java Packages)
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -C 'CDB\$ROOT' -b builder_remove_multimedia_pdbs -d "${ORACLE_HOME}"/ord/im/admin imremdo.sql
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -c 'CDB\$ROOT' -b builder_remove_multimedia_cdb -d "${ORACLE_HOME}"/ord/im/admin imremdo.sql

    # Remove Oracle Database Java Packages
    echo "BUILDER: Removing Oracle Database Java Packages"
    "${ORACLE_HOME}"/perl/bin/perl catcon.pl -n 1 -b builder_remove_java_packages -d "${ORACLE_HOME}"/rdbms/admin catnojav.sql

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

     -- Oracle Multimedia leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE SYS.ORD_ADMIN');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE SYS.ORDIMDPCALLOUTS');

     -- Open PDB\$SEED to READ WRITE mode (catcon put it into READY ONLY again)
     ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
     ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ WRITE;

     ALTER SESSION SET CONTAINER=PDB\$SEED;

     -- Remove Java VM leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE JAVAVM_SYS');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE JVMRJBCINV');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE DBMS_JAVA_MISC');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE OJDS_CONTEXT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$NODE_NUMBER\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$BINDINGS\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$INODE\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$ATTRIBUTES\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$REFADDR\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$PERMISSIONS\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$SHARED\$OBJ\$SEQ\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$SHARED\$OBJ\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP TRIGGER OJDS\$ROLE_TRIGGER\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER OJVMSYS');

     -- Oracle Multimedia leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE SYS.ORD_ADMIN');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE SYS.ORDIMDPCALLOUTS');
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
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE JAVAVM_SYS');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE JVMRJBCINV');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE DBMS_JAVA_MISC');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE OJDS_CONTEXT');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$NODE_NUMBER\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$BINDINGS\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$INODE\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$ATTRIBUTES\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$REFADDR\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$PERMISSIONS\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$SHARED\$OBJ\$SEQ\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP SYNONYM OJDS\$SHARED\$OBJ\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP TRIGGER OJDS\$ROLE_TRIGGER\$');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER OJVMSYS');

     -- Oracle Multimedia leftovers
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE SYS.ORD_ADMIN');
     exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE SYS.ORDIMDPCALLOUTS');
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

       -- Remove Spatial leftover components
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER MDDATA CASCADE');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER MDSYS CASCADE');

       -- Open PDB\$SEED to READ WRITE mode (catcon put it into READY ONLY again)
       ALTER PLUGGABLE DATABASE PDB\$SEED CLOSE;
       ALTER PLUGGABLE DATABASE PDB\$SEED OPEN READ WRITE;

       ALTER SESSION SET CONTAINER=PDB\$SEED;

       -- Oracle Text leftovers
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE XDB.XDB_DATASTORE_PROC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE XDB.DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE SYS.VALIDATE_CONTEXT');

       -- Remove Spatial leftover components
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER MDDATA CASCADE');

       ALTER SESSION SET CONTAINER=XEPDB1;

       -- Oracle Text leftovers
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE XDB.XDB_DATASTORE_PROC');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PUBLIC SYNONYM DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PACKAGE XDB.DBMS_XDBT');
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP PROCEDURE SYS.VALIDATE_CONTEXT');

       -- Remove Spatial leftover components
       exec DBMS_PDB.EXEC_AS_ORACLE_SCRIPT('DROP USER MDDATA CASCADE');

       exit;
EOF

  fi;

  #####################
  # Shrink data files #
  #####################
  su -p oracle -c "sqlplus -s / as sysdba" << EOF

     -- Exit on any errors
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

# Shutdown database gracefully (listener is not yet running)
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
rm -r "${ORACLE_HOME}"/log/*

# Remove diag files
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/lck/*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/metadata/*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/trace/"${ORACLE_SID}"_*
rm    "${ORACLE_BASE}"/diag/rdbms/xe/"${ORACLE_SID}"/trace/drc"${ORACLE_SID}".log
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

  # Remove Oracle Database Migration Assistant for Unicode (dmu)
  rm -r "${ORACLE_HOME}"/dmu

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
  mv    "${ORACLE_HOME}"/oracore/zoneinfo/timezlrg_31.dat "${ORACLE_HOME}"/oracore/zoneinfo/current.dat
  rm    "${ORACLE_HOME}"/oracore/zoneinfo/timezlrg*
  mv    "${ORACLE_HOME}"/oracore/zoneinfo/current.dat "${ORACLE_HOME}"/oracore/zoneinfo/timezlrg_31.dat

  # Remove Multimedia
  rm -r "${ORACLE_HOME}"/ord/im

  # Remove Oracle XDK
  rm -r "${ORACLE_HOME}"/xdk

  # Remove JServer JAVA Virtual Machine
  rm -r  "${ORACLE_HOME}"/javavm

  # Remove Java JDK
  rm -r "${ORACLE_HOME}"/jdk

  # Remove dbjava directory
  rm -r "${ORACLE_HOME}"/dbjava

  # Remove rdbms/jlib
  rm -r "${ORACLE_HOME}"/rdbms/jlib

  # Remove OLAP
  rm -r "${ORACLE_HOME}"/olap
  rm "${ORACLE_HOME}"/lib/libolapapi18.so

  # Remove property graph (standalone component that can be downloaded from the web)
  rm -r "${ORACLE_HOME}"/md/property_graph

  # Remove Cluster Ready Services
  rm -r "${ORACLE_HOME}"/crs

  # Remove Cluster Verification Utility (CVU)
  rm -r "${ORACLE_HOME}"/cv

  # Remove install directory
  rm -r "${ORACLE_HOME}"/install

  # Remove network/jlib directory
  rm -r "${ORACLE_HOME}"/network/jlib

  # Remove network/tools directory
  rm -r "${ORACLE_HOME}"/network/tools

  # Remove opmn directory
  rm -r "${ORACLE_HOME}"/opmn

  # Remove unnecessary binaries (see http://yong321.freeshell.org/computer/oraclebin.html#18c)
  rm "${ORACLE_HOME}"/bin/acfs*      # ACFS File system components
  rm "${ORACLE_HOME}"/bin/adrci      # Automatic Diagnostic Repository Command Interpreter
  rm "${ORACLE_HOME}"/bin/agtctl     # Multi-Threaded extproc agent control utility
  rm "${ORACLE_HOME}"/bin/afd*       # ASM Filter Drive components
  rm "${ORACLE_HOME}"/bin/amdu       # ASM Disk Utility
  rm "${ORACLE_HOME}"/bin/dg4*       # Database Gateway
  rm "${ORACLE_HOME}"/bin/dgmgrl     # Data Guard Manager CLI
  rm "${ORACLE_HOME}"/bin/drda*      # Distributed Relational Database Architecture components
  rm "${ORACLE_HOME}"/bin/orion      # ORacle IO Numbers benchmark tool
  rm "${ORACLE_HOME}"/bin/proc       # Pro*C/C++ Precompiler
  rm "${ORACLE_HOME}"/bin/procob     # Pro COBOL Precompiler
  rm "${ORACLE_HOME}"/bin/renamedg   # Rename Disk Group binary


  # Replace `orabase` with static path shell script
  su -p oracle -c "echo 'echo ${ORACLE_BASE}' > ${ORACLE_HOME}/bin/orabase"

  # Replace `orabasehome` with static path shell script
  su -p oracle -c "echo 'echo ${ORACLE_HOME}' > ${ORACLE_HOME}/bin/orabasehome"

  # Replace `orabaseconfig` with static path shell script
  su -p oracle -c "echo 'echo ${ORACLE_HOME}' > ${ORACLE_HOME}/bin/orabaseconfig"

  # Remove unnecessary libraries
  rm "${ORACLE_HOME}"/lib/libra.so    # Recovery Appliance
  rm "${ORACLE_HOME}"/lib/libopc.so   # Oracle Public Cloud
  rm "${ORACLE_HOME}"/lib/libosbws.so # Oracle Secure Backup Cloud Module

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

    # Remove ordim directory
    rm -r "${ORACLE_HOME}"/ordim

    # Remove Oracle R
    rm -r "${ORACLE_HOME}"/R

    # Remove deinstall directory
    rm -r "${ORACLE_HOME}"/deinstall

    # Remove Oracle Database Provider for Distributed Relational Database Architecture (DRDA)
    rm -r "${ORACLE_HOME}"/drdaas

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
                make net-tools procps-ng smartmontools sysstat systemd \
                systemd-pam util-linux xz

rm /etc/sysctl.conf.rpmsave

# Remove dnf cache
microdnf clean all

# Clean lastlog
echo "" > /var/log/lastlog
